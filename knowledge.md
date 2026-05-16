# v2ray_bin-main / Merlin 科学上网插件知识库

本文合并并重整 `knowledge_codex.md`、`knowledge_opus4.6.md`、当前 `knowledge.md`、`hysteria.md`、`hysteria_doc.md` 的结论。定位不是普通源码编译项目，而是 Merlin/Koolshare 插件包：Web 页面读写 dbus，后端 Shell 编排运行时配置、DNS、iptables/ipset 和预编译二进制。

侧重点：

- HY2/Hysteria2 当前支持链路、缺口和拓展落点。
- Web -> dbus -> SystemCmd -> Shell -> JSON -> 进程 -> DNS/NAT 的完整路径。
- Merlin 固件网络事件、iptables 表状态、DNS 分流、透明代理实现。

---

## 1. 核心结论

1. 这个项目本质是 `web 壳 + dbus 配置 + shell 编排 + 预编译二进制`，不是需要交叉编译主程序的源码工程。`shadowsocks` 目录直接就是插件包主体，打包逻辑见 `shadowsocks/scripts/ss_pack.sh`。
2. HY2 当前已经接入了基础 TCP 透明代理链路：Web 选择 Hysteria2 -> dbus 写 `ss_basic_type=4` 和 `ss_basic_trojan_binary=Hysteria2` -> `ssconfig.sh` 生成 `/koolshare/ss/hysteria.json` -> 启动 `/koolshare/bin/hysteria` -> iptables TCP REDIRECT 到 `3333`。
3. HY2 当前没有完整支持官方 Hysteria2 参数。已支持 `server/auth/tls.sni/tls.insecure/fastOpen/lazy/socks5/tcpRedirect`；未支持 `obfs.salamander`、`bandwidth.up/down`、`tls.pinSHA256`、`udpTProxy`、`hy2://` 前缀、端口跳跃、QUIC 细项。
4. HY2 的关键断点是 UDP：插件在游戏模式或 UDP 同步时会写 mangle/TPROXY 规则，把 UDP 送到本机 `3333`，但当前 `hysteria.json` 只有 `tcpRedirect.listen=0.0.0.0:3333`，没有 `udpTProxy.listen`。所以 iptables 侧基本不用重写，HY2 侧需要补 UDP 入站。
5. HY2 魔改主战场不是 `start_hy2()`，而是四处保持一致：`Main_Ss_Content.asp` 字段和节点保存、`ss_online_update.sh` 订阅解析、`ssconfig.sh:create_hy2_json()` 运行配置、`ss_webtest.sh:create_hy2_json()` 测速配置。
6. ARMv7 只需要确认二进制适配和打包。`install.sh` 检查 `uname -m=armv7l`；当前仓库更新路径仍是 `380_armv5/hysteria`，实际设备上要用 `hysteria version` 和 `file /koolshare/bin/hysteria` 验证。

---

## 2. 运行时架构

### 2.1 四层模型

```text
Web ASP/JS
  shadowsocks/webs/Main_Ss_Content.asp
  -> 表单读写 dbus key
  -> post SystemCmd=ss_config.sh / ss_online_update.sh / ss_v2ray_xray.sh

dbus(skipd)
  ss_basic_*                 当前运行节点和全局设置
  ssconf_basic_*_<node_id>   节点库
  ss_acl_*                   访问控制

Shell 编排
  /koolshare/scripts/ss_config.sh
  -> /koolshare/ss/ssconfig.sh restart|stop|flush_nat
  -> 生成 JSON、启动进程、创建 DNS 配置、写 iptables/ipset

二进制进程
  hysteria/xray/trojan-go/naive/ss-redir/dns2socks/smartdns/chinadns-ng 等
```

### 2.2 安装后目录布局

| 位置 | 来源 | 职责 |
|---|---|---|
| `/koolshare/bin/` | `shadowsocks/bin/*` | 预编译二进制，包含 `hysteria`、`xray`、`jq`、`dns2socks`、`ss-redir` 等 |
| `/koolshare/ss/` | `shadowsocks/ss/*` | 主控脚本、规则文件、运行时 JSON |
| `/koolshare/scripts/` | `shadowsocks/scripts/*` | Web 调用入口、订阅、测速、状态、更新、打包 |
| `/koolshare/webs/` | `shadowsocks/webs/*` | Merlin Web 页面 |
| `/koolshare/res/` | `shadowsocks/res/*` | Web 静态资源 |
| `/jffs/scripts/` | `auto_start()` 注入 | Merlin 事件钩子：`wan-start`、`nat-start`、`dnsmasq.postconf` |
| `/jffs/configs/dnsmasq.d/` | `create_dnsmasq_conf()` | dnsmasq 分流配置软链接 |
| `/tmp/` | 运行时 | 日志、测速临时 JSON、临时规则文件 |

### 2.3 安装、打包、更新不是交叉编译

`shadowsocks/install.sh` 的流程：

1. `uname -m` 必须是 `armv7l`。
2. 检查 Merlin 固件版本，低于 X7.2 退出。
3. 若插件已启用，先执行 `/koolshare/ss/ssconfig.sh stop`。
4. 清理旧文件和旧二进制。
5. 从 `/tmp/shadowsocks/` 复制 `bin/ ss/ scripts/ webs/ res/` 到 `/koolshare/`。
6. 设置权限、创建软链接、写默认 dbus key。

`shadowsocks/scripts/ss_pack.sh` 的逻辑是从路由器现有 `/koolshare` 安装目录反向组装 `/tmp/shadowsocks/`，再：

```sh
tar -czv -f /tmp/shadowsocks.tar.gz shadowsocks/
```

所以魔改后可以直接打包整个 `shadowsocks` 插件目录为 `shadowsocks.tar.gz`，前提是目录结构必须保持：

```text
shadowsocks/
  install.sh
  uninstall.sh
  bin/
  ss/
  scripts/
  webs/
  res/
```

---

## 3. dbus 数据模型

### 3.1 当前运行节点

当前运行配置以 `ss_basic_*` 为主。HY2 复用 Trojan 系字段：

| key | HY2 当前含义 |
|---|---|
| `ss_basic_type=4` | 协议大类：Trojan/Xray 系 |
| `ss_basic_trojan_binary=Hysteria2` | 在 type=4 内选择 Hysteria2 |
| `ss_basic_server` | HY2 服务器域名或 IP |
| `ss_basic_port` | HY2 服务器端口 |
| `ss_basic_password` | HY2 `auth`，Web 保存时 base64，Shell 通过 `dbus export ss` 得到明文变量 |
| `ss_basic_trojan_sni` | HY2 `tls.sni` |
| `ss_basic_allowinsecure` | HY2 `tls.insecure` |
| `ss_basic_mode` | 代理模式：GFW/CHN/GAM/GLO/HOM |
| `ss_basic_udp_sync` | 非游戏模式下是否同步开启 UDP mangle |

### 3.2 节点库字段

节点列表使用 `ssconf_basic_*_<n>`。HY2 节点当前字段：

```text
ssconf_basic_type_<n>=4
ssconf_basic_trojan_binary_<n>=Hysteria2
ssconf_basic_server_<n>
ssconf_basic_port_<n>
ssconf_basic_password_<n>
ssconf_basic_trojan_sni_<n>
ssconf_basic_allowinsecure_<n>
ssconf_basic_mode_<n>
```

### 3.3 建议新增 HY2 专属字段

不要继续挤进 Trojan-Go/V2Ray 字段，否则后续 Web 表单、订阅解析、节点编辑会越来越难维护。建议新增：

```text
# 当前运行节点
ss_basic_hy2_obfs_type          # 空/none/salamander
ss_basic_hy2_obfs_password
ss_basic_hy2_up_mbps
ss_basic_hy2_down_mbps
ss_basic_hy2_pin_sha256
ss_basic_hy2_hop_interval       # 可选，端口跳跃

# 节点库
ssconf_basic_hy2_obfs_type_<n>
ssconf_basic_hy2_obfs_password_<n>
ssconf_basic_hy2_up_mbps_<n>
ssconf_basic_hy2_down_mbps_<n>
ssconf_basic_hy2_pin_sha256_<n>
ssconf_basic_hy2_hop_interval_<n>
```

`udpTProxy` 不建议先做成独立用户开关。因为 iptables 是否写 UDP TPROXY 由 `mangle=1` 决定，HY2 JSON 最稳妥的策略是：只要 `mangle=1`，就自动写入 `udpTProxy.listen=0.0.0.0:3333`，保证配置与防火墙一致。

---

## 4. Web 端接口和实现

### 4.1 保存当前运行配置

文件：`shadowsocks/webs/Main_Ss_Content.asp`

主函数：

- `save()`：收集表单，生成 dbus 对象。
- `push_data()`：POST 到 `/applydb.cgi?p=ss`。
- `post_dbus["SystemCmd"]="ss_config.sh"`：触发后端 `/koolshare/scripts/ss_config.sh`。

`save()` 的关键点：

1. `params_input` 收集普通输入，当前只含 `ss_basic_trojan_sni`、`ss_basic_trojan_binary` 等通用 Trojan 字段，没有 HY2 专属字段。
2. `params_check` 收集 checkbox，当前只含 `ss_basic_allowinsecure`、`ss_basic_udp_sync` 等，没有 HY2 专属 checkbox。
3. `params_base64_b` 对 `ss_basic_password` 做 base64。
4. 保存当前运行节点时，会把一组 `ss_basic_*` 同步写回当前 `ssconf_basic_*_<node>`。
5. 根据 `ssconf_basic_trojan_binary_<node>` 是否存在，把当前节点判定为 `ss_basic_type=4`。

HY2 拓展 Web 必改点：

| 位置 | 当前行为 | HY2 拓展动作 |
|---|---|---|
| `params_input` | 无 HY2 专属字段 | 加 `ss_basic_hy2_obfs_type`、`ss_basic_hy2_obfs_password`、`ss_basic_hy2_up_mbps`、`ss_basic_hy2_down_mbps`、`ss_basic_hy2_pin_sha256`、可选 `ss_basic_hy2_hop_interval` |
| `save()` 节点同步 `params` | 只同步 `trojan_sni/trojan_binary/trojan_network` | 加 `hy2_*` 字段同步到 `ssconf_basic_hy2_*_<node>` |
| `verifyFields()` | Hysteria2 只显示 SNI、allowinsecure、更新按钮 | 当 `ss_basic_trojan_binary=Hysteria2` 时显示 HY2 obfs/bandwidth/pin 字段 |
| `update_ss_ui()` | 按字段 id 恢复表单 | 新字段 id 必须与 dbus key 一致 |

### 4.2 节点新增、编辑、删除

相关函数：

- `add_ss_node_conf('trojan')`
- `edit_conf_table()`
- `edit_ss_node_conf('trojan')`
- `remove_conf_table()`
- `ssconf_node2obj()`

当前 HY2 只是 Trojan 面板的一个 `select` 值：

```html
<option value="Trojan">Trojan</option>
<option value="Trojan-Go">Trojan-Go</option>
<option value="Hysteria2">Hysteria2</option>
```

`paramsTrojan` 当前负责保存 Trojan/Trojan-Go/Hysteria2 共同字段：

```js
["name", "server", "mode", "port", "trojan_binary", "trojan_network",
 "v2ray_network_path", "v2ray_network_host", "trojan_sni",
 "fingerprint", "allowinsecure", "fragment", "v2ray_mux_concurrency"]
```

HY2 拓展时要同时更新：

1. `add_ss_node_conf()` 的 `paramsTrojan`。
2. `edit_ss_node_conf()` 的 `paramsTrojan`。
3. `edit_conf_table()` 的 `params1_input`，否则编辑时字段不会回显。
4. `remove_conf_table()` 的 `params`，否则删除节点时会残留 `ssconf_basic_hy2_*_<n>`。
5. `ssconf_node2obj()` 的 `params2`/对象构造，否则应用节点时不会把 `ssconf_basic_hy2_*_<n>` 带到运行配置。
6. 连续添加后表单 reset 逻辑，避免新建下一个节点时继承上一个 HY2 的 obfs/bandwidth。

### 4.3 订阅和单链接入口

Web 订阅入口：

- `save_online_nodes(action)`
- `SystemCmd=ss_online_update.sh`
- `ss_online_links`：订阅地址，base64。
- `ss_base64_links`：单链接导入，原样传给脚本。

当前页面文案只写 `hysteria2://`，不写 `hy2://`。如果要完整兼容官方 URI，需要同步改：

- 订阅 textarea placeholder。
- 单链接 textarea placeholder。
- Web 端提示说明。
- 后端 `ss_online_update.sh` 的 grep 识别正则。

### 4.4 二进制更新和状态入口

Web 更新 HY2 二进制：

```js
ss_binary_update(4)
SystemCmd = "ss_v2ray_xray.sh"
ss_binary_update = 4
```

后端 `ss_v2ray_xray.sh`：

```sh
case "$ss_binary_update" in
  4) core_bin="hysteria" ;;
esac
```

状态页面 `ss_proc_status.sh` 会读取：

- `/koolshare/bin/hysteria version`
- `pidof hysteria`

所以 HY2 参数拓展后，状态页不一定要改；但如果加了 UDP/TProxy，建议状态页检查 `netstat -nlp` 是否有 `3333` 的 TCP/UDP 入站。

---

## 5. 后端主流程

### 5.1 Web 到 Shell

```text
Main_Ss_Content.asp:save()
  -> POST /applydb.cgi?p=ss
     fields: ss_basic_*, ssconf_basic_*_<node>, SystemCmd=ss_config.sh
  -> Koolshare 执行 /koolshare/scripts/ss_config.sh
  -> ss_config.sh:
       eval `dbus export ss`
       ss_basic_enable=1 -> sh /koolshare/ss/ssconfig.sh restart
       ss_basic_enable!=1 -> sh /koolshare/ss/ssconfig.sh stop
  -> ssconfig.sh: apply_ss() / disable_ss()
```

### 5.2 `apply_ss()` 执行序列

文件：`shadowsocks/ss/ssconfig.sh`

```text
apply_ss()
  ss_pre_stop()
  kill_process()
  restore_conf()
  restart_dnsmasq()
  flush_nat()
  kill_cron_job()

  ss_pre_start()
  detect()
  resolv_server_ip()
  load_module()
  create_ipset()
  create_dnsmasq_conf()

  按协议生成 JSON
    create_ss_json / create_v2ray_json / create_trojan_json /
    create_trojango_json / create_naive_json / create_hy2_json

  按协议启动进程
    start_ss_redir / start_xray_core / start_trojango /
    start_naiveproxy / start_hy2

  start_kcp()
  start_dns()
  load_nat()
    add_white_black_ip()
    apply_nat_rules()
    chromecast()

  mount_dnsmasq_now()
  restart_dnsmasq()
  auto_start()
  write_cron_job()
  set_ss_reboot_job()
  set_ss_trigger_job()
  ss_post_start()
```

HY2 分支位于：

```sh
[ -z "$WAN_ACTION" ] && [ "$ss_basic_type" = "4" -a "$ss_basic_trojan_binary" == "Hysteria2" ] && create_hy2_json
[ "$ss_basic_type" == "4" -a "$ss_basic_trojan_binary" == "Hysteria2" ] && start_hy2
```

注意：开机 `WAN_ACTION` 非空时不会重新生成 JSON，而是复用旧 `/koolshare/ss/hysteria.json`。如果后续 HY2 JSON 依赖 `mangle` 或新增字段，最好确认开机时文件一定存在且字段没有过期；否则可以考虑让 HY2 每次都重新生成 JSON。

### 5.3 协议启动矩阵

| `ss_basic_type` | 子类型 | 配置函数 | 启动函数 | 二进制 | 本地透明入口 |
|---|---|---|---|---|---|
| `0` | SS-libev | `create_ss_json` | `start_ss_redir` | `ss-redir` | `3333` |
| `0 -> 3` | SS2022 | `create_ss2022_json` | `start_ss2022` | `xray` | dokodemo-door |
| `1` | SSR-libev | `create_ss_json` | `start_ss_redir` | `rss-redir` | `3333` |
| `2` | KoolGame | 自有配置 | `start_koolgame` | `koolgame` | 游戏 UDP |
| `3` | V2Ray/Xray | `create_v2ray_json` | `start_xray` | `xray` | dokodemo-door |
| `4` | Trojan | `create_trojan_json` | `start_trojan` | `xray` | dokodemo-door |
| `4` | Trojan-Go | `create_trojango_json` | `start_trojango` | `trojan-go` | nat/redirect |
| `4` | Hysteria2 | `create_hy2_json` | `start_hy2` | `hysteria` | `tcpRedirect :3333`，UDP 待补 `udpTProxy` |
| `5` | NaiveProxy | `create_naive_json` | `start_naiveproxy` | `naive` | redir |

---

## 6. HY2 当前实现链路

### 6.1 类型判定

HY2 没有独立 `ss_basic_type`，而是：

```text
ss_basic_type = 4
ss_basic_trojan_binary = Hysteria2
```

这意味着：

- Web 上和 Trojan/Trojan-Go 共用一组 UI 逻辑。
- 后端和 Trojan/Trojan-Go 共用部分字段命名。
- 订阅节点被写成 `ssconf_basic_type_<n>=4`。
- 聚合页 `Main_SsXray_Aggregate.asp` 明确排除 Trojan-Go/Hysteria2，只聚合 VLESS/VMESS/Trojan。

### 6.2 `create_hy2_json()`

文件：`shadowsocks/ss/ssconfig.sh`

当前生成：

```json
{
  "server": "host:port",
  "auth": "password",
  "tls": {
    "sni": "example.com",
    "insecure": false
  },
  "fastOpen": true,
  "lazy": true,
  "socks5": {
    "listen": "127.0.0.1:23456"
  },
  "tcpRedirect": {
    "listen": "0.0.0.0:3333"
  }
}
```

已接通能力：

| 能力 | 当前状态 |
|---|---|
| 远端地址 | `server=$(dbus get ss_basic_server):$ss_basic_port` |
| 鉴权 | `auth=$ss_basic_password` |
| TLS SNI | `tls.sni=$ss_basic_trojan_sni` |
| 跳过证书验证 | `tls.insecure=$(get_function_switch $ss_basic_allowinsecure)` |
| SOCKS5 | `127.0.0.1:23456` |
| TCP 透明代理 | `tcpRedirect 0.0.0.0:3333` |
| QUIC ECN 兼容 | 在 `start_hy2()` 设置 `QUIC_GO_DISABLE_ECN=true` |

未接通能力：

| 能力 | 官方字段 | 当前影响 |
|---|---|---|
| 混淆 | `obfs.type=salamander`、`obfs.salamander.password` | 使用带 obfs 的节点无法连通 |
| 速率声明 | `bandwidth.up/down` | 无法启用 Brutal CC，只能默认 BBR |
| 证书 pin | `tls.pinSHA256` | 无法 pin 证书 |
| UDP 透明代理 | `udpTProxy.listen` | 游戏模式/UDP 同步链路断在本地入口 |
| URI 简写 | `hy2://` | 订阅/单链接导入不识别 |
| 端口跳跃 | `server` 多端口 + `transport.udp.hopInterval` | 无法完整表达端口跳跃 |

### 6.3 `start_hy2()`

文件：`shadowsocks/ss/ssconfig.sh`

```sh
start_hy2() {
  export QUIC_GO_DISABLE_ECN=true
  cd /koolshare/bin
  hysteria -c $HY2_CONFIG_FILE -l error --disable-update-check >/dev/null 2>&1 &
  pidof hysteria 等待最多 10 秒
}
```

`start_hy2()` 基本足够，不需要为了 obfs/bandwidth 改命令行；这些都是 JSON 配置字段。可选优化：

- 启动失败时输出 `/koolshare/ss/hysteria.json` 校验结果或 `hysteria -c ... check` 类命令，如果当前二进制支持。
- `pidof hysteria` 只能判断进程存在，不能判断监听是否成功；实机验证要看 `netstat -nlp`。

### 6.4 Web 测速

文件：`shadowsocks/scripts/ss_webtest.sh`

`create_hy2_json()` 生成 `/tmp/tmp_hysteria.json`，只含：

- `server/auth/tls`
- `fastOpen/lazy`
- `socks5.listen=127.0.0.1:23458`

测速启动：

```sh
hysteria -c /tmp/tmp_hysteria.json -l error --disable-update-check &
speed_test_curl
```

HY2 拓展时，测速配置必须同步支持 `obfs`、`bandwidth`、`pinSHA256`。不需要写 `tcpRedirect/udpTProxy`，因为测速只走 SOCKS5 `23458`。

### 6.5 二进制更新

文件：`shadowsocks/scripts/ss_v2ray_xray.sh`

`ss_binary_update=4` 时：

```sh
core_bin="hysteria"
url_main="https://raw.githubusercontent.com/cary-sas/v2ray_bin/main/380_armv5/$core_bin"
```

该脚本还会在代理已运行且允许代理更新时，通过 `127.0.0.1:23456` 走 SOCKS5 下载。HY2 运行时的 SOCKS5 因此不仅服务 DNS，也服务更新/订阅代理。

---

## 7. HY2 订阅解析

### 7.1 当前支持格式

文件：`shadowsocks/scripts/ss_online_update.sh`

当前识别：

```sh
^ss://|^ssr://|^vmess://|^trojan://|^vless://|^trojan-go://|^hysteria2://
```

循环中：

```sh
NODE_FORMAT="${line%%://*}"
NODE_FORMAT="${NODE_FORMAT//-/_}"
link="${line#*://}"
get_${NODE_FORMAT}_config $link "$group"
update_${NODE_FORMAT}_config $group_index
```

因此 `hysteria2://` 会进入：

- `get_hysteria2_config`
- `update_hysteria2_config`
- `add_hysteria2_servers`

单链接导入也动态调用：

```sh
NODE_FORMAT=$(echo $ssrlink | awk -F":" '{print $1}' | sed 's/-/_/')
get_${NODE_FORMAT}_config $link
add_${NODE_FORMAT}_servers 1
```

### 7.2 当前 `get_hysteria2_config()` 字段

当前解析：

```text
hysteria2://auth@host:port?sni=x&insecure=1#name
```

写入变量：

| 变量 | 来源 | 写入 dbus |
|---|---|---|
| `server` | `auth@host:port` 中的 host | `ssconf_basic_server_<n>` |
| `server_port` | port | `ssconf_basic_port_<n>` |
| `password` | auth，base64 后保存 | `ssconf_basic_password_<n>` |
| `sni` | query `sni=` | `ssconf_basic_trojan_sni_<n>` |
| `insecure` | query `insecure=` | `ssconf_basic_allowinsecure_<n>` |
| `binary` | 固定 `Hysteria2` | `ssconf_basic_trojan_binary_<n>` |
| `type` | 固定 `4` | `ssconf_basic_type_<n>` |

未解析：

- `hy2://`
- `obfs`
- `obfs-password`
- `upmbps/downmbps` 或其他带宽参数
- `pinSHA256`
- `hopInterval`

### 7.3 订阅拓展策略

推荐兼容规则：

1. grep 识别加入 `^hy2://`。
2. 在取 `NODE_FORMAT` 后做别名：

```sh
[ "$NODE_FORMAT" = "hy2" ] && NODE_FORMAT="hysteria2"
```

3. `get_hysteria2_config()` 中解析官方常见参数：

```text
sni
insecure
obfs
obfs-password
pinSHA256
upmbps / downmbps     # 若采用此 URI 参数命名
```

4. `add_hysteria2_servers()` 和 `update_hysteria2_config()` 同步写/比较新增 `ssconf_basic_hy2_*_<n>`。
5. 单链接导入路径也必须支持 `hy2://`，不能只改订阅路径。

订阅字段建议映射：

| URI 参数 | dbus 节点字段 |
|---|---|
| `obfs=salamander` | `ssconf_basic_hy2_obfs_type_<n>` |
| `obfs-password=xxx` | `ssconf_basic_hy2_obfs_password_<n>` |
| `pinSHA256=xxx` | `ssconf_basic_hy2_pin_sha256_<n>` |
| `upmbps=20` | `ssconf_basic_hy2_up_mbps_<n>` |
| `downmbps=100` | `ssconf_basic_hy2_down_mbps_<n>` |

注意：Hysteria2 URI 对带宽字段没有像 JSON 那样天然完整，订阅提供商可能命名不一致。代码要容忍字段缺失，不要因缺少带宽而拒绝节点。

---

## 8. Merlin 网络实现

### 8.1 Merlin 钩子链

`auto_start()` 注入两个启动钩子：

```text
/jffs/scripts/wan-start
  sh /koolshare/scripts/ss_config.sh

/jffs/scripts/nat-start
  sh /koolshare/ss/ssconfig.sh
```

`create_dnsmasq_conf()` 注入：

```text
/jffs/scripts/dnsmasq.postconf -> /koolshare/ss/rules/dnsmasq.postconf
```

Merlin 事件中的职责：

| 事件 | 触发时机 | 插件动作 |
|---|---|---|
| `wan-start` | WAN 获取地址后 | 按 dbus 开关重启/停止插件 |
| `nat-start` | 固件重建 NAT 表后 | 重新加载插件 NAT/mangle 规则 |
| `dnsmasq.postconf` | dnsmasq 生成配置后 | 修改 DNS 上游、缓存、分流配置 |

`detect()` 会检查 `nvram get jffs2_scripts`，未开启会影响自启和 dnsmasq 后处理。

### 8.2 端口分配

| 端口 | 用途 |
|---|---|
| `3333` | 主透明代理入口：TCP REDIRECT；UDP TPROXY 也打到这里 |
| `23456` | 运行时 SOCKS5，本地 DNS/订阅/更新代理使用 |
| `23458` | Web 测速临时 SOCKS5 |
| `7913` | 国外 DNS 入口 `DNSF_PORT` |
| `5335` | SmartDNS |
| `1091` | kcptun |
| `1092` | UDPspeeder |
| `1093` | UDP2raw |

### 8.3 ipset 集合

`create_ipset()` 创建：

| ipset | 来源 | 用途 |
|---|---|---|
| `chnroute` | `/koolshare/ss/rules/chnroute.txt` | 国内 IP 判断 |
| `gfwlist` | dnsmasq `ipset=/domain/gfwlist` | GFW 模式代理目标 |
| `white_list` | 用户白名单 IP/域名 | 强制直连 |
| `black_list` | 用户黑名单 IP/域名 | 强制代理 |
| `router` | 内置路由器自身需要代理域名 | OUTPUT 链代理路由器自身 TCP |

DNS 与 ipset 是联动的：dnsmasq 解析某些域名时，会把解析结果写入 `gfwlist`、`black_list`、`white_list`、`router`，iptables 再按 ipset 匹配目标 IP。

### 8.4 DNS 处理

主入口是 `start_dns()` 和 `create_dnsmasq_conf()`。

```text
LAN 客户端 DNS -> dnsmasq:53
  -> gfwlist / 黑名单域名 -> 127.0.0.1:7913
  -> cdn / 白名单域名 -> 国内 DNS
  -> 默认上游由 dnsmasq.postconf 决定
```

`127.0.0.1:7913` 的实现取决于 `ss_foreign_dns`：

| `ss_foreign_dns` | 方案 |
|---|---|
| `1` | cdns |
| `2` | chinadns2 |
| `3` 或空 | dns2socks -> `127.0.0.1:23456` |
| `4` | ss-tunnel |
| `5` | chinadns1 + dns2socks |
| `6` | https_dns_proxy |
| `7` | xray 内置 DNS，非 Xray/Trojan 时会退回 dns2socks |
| `8` | 直连 DNS，回国模式常用 |
| `9` | SmartDNS |
| `10` | chinadns-ng |

对 HY2 来说，最稳定的是 `dns2socks`：`dns2socks 127.0.0.1:23456 ... 127.0.0.1:7913`，它会走 HY2 的 `socks5.listen=127.0.0.1:23456`。

### 8.5 nat 表状态

`apply_nat_rules()` 创建 nat 表链：

```text
PREROUTING
  -> SHADOWSOCKS_DNS_<br>   udp dpt:53, DNS 劫持
  -> SHADOWSOCKS            tcp, 主透明代理链

SHADOWSOCKS
  white_list dst -> RETURN
  ACL 源 IP/端口规则 -> RETURN/GFW/CHN/GAM/GLO/HOM
  默认规则 -> get_action_chain(ss_acl_default_mode)

SHADOWSOCKS_GFW
  black_list dst -> REDIRECT --to-ports 3333
  gfwlist dst    -> REDIRECT --to-ports 3333

SHADOWSOCKS_CHN
  black_list dst -> REDIRECT --to-ports 3333
  !chnroute dst  -> REDIRECT --to-ports 3333

SHADOWSOCKS_GAM
  black_list dst -> REDIRECT --to-ports 3333
  !chnroute dst  -> REDIRECT --to-ports 3333

SHADOWSOCKS_GLO
  all tcp -> REDIRECT --to-ports 3333

SHADOWSOCKS_HOM
  black_list dst -> REDIRECT --to-ports 3333
  chnroute dst   -> REDIRECT --to-ports 3333

OUTPUT
  router ipset dst -> REDIRECT --to-ports 3333
  mark ip_prefix_hex -> SHADOWSOCKS_EXT
```

`get_action_chain()` 映射：

| 模式 | 链 |
|---|---|
| `0` 不通过 | `RETURN` |
| `1` GFW | `SHADOWSOCKS_GFW` |
| `2` 大陆白名单 | `SHADOWSOCKS_CHN` |
| `3` 游戏 | `SHADOWSOCKS_GAM` |
| `5` 全局 | `SHADOWSOCKS_GLO` |
| `6` 回国 | `SHADOWSOCKS_HOM` |

HY2 的 TCP 路径：

```text
LAN TCP
  -> nat PREROUTING
  -> SHADOWSOCKS_*
  -> REDIRECT :3333
  -> hysteria tcpRedirect 0.0.0.0:3333
  -> QUIC 到 HY2 服务器
```

### 8.6 mangle/TPROXY 状态

顶部逻辑中，以下情况会启用 `mangle=1`：

- 有 ACL 主机使用游戏模式。
- 主模式是游戏模式 `ss_basic_mode=3`。
- 开启 `ss_basic_udp_sync=1`。

`apply_nat_rules()` 中：

```text
load_tproxy()
ip rule add fwmark 0x07 table 310
ip route add local 0.0.0.0/0 dev lo table 310

mangle PREROUTING
  udp -> SHADOWSOCKS

mangle SHADOWSOCKS
  white_list dst -> RETURN
  ACL 游戏模式主机 -> SHADOWSOCKS_GAM
  非游戏主机 -> RETURN
  默认 UDP -> SHADOWSOCKS_GAM   # 主模式游戏或 udp_sync

mangle SHADOWSOCKS_GAM
  black_list dst -> TPROXY --on-port 3333 --tproxy-mark 0x07
  !chnroute dst  -> TPROXY --on-port 3333 --tproxy-mark 0x07
```

HY2 当前 UDP 路径：

```text
LAN UDP
  -> mangle PREROUTING
  -> TPROXY :3333 mark 0x07
  -> table 310 -> local lo
  -> 没有 hysteria udpTProxy 监听
  -> UDP 透明代理失败
```

HY2 目标 UDP 路径：

```text
LAN UDP
  -> mangle PREROUTING
  -> TPROXY :3333 mark 0x07
  -> table 310 -> local lo
  -> hysteria udpTProxy 0.0.0.0:3333
  -> QUIC 到 HY2 服务器
```

### 8.7 `flush_nat()` 清理状态

`flush_nat()` 清理：

- 删除 nat `PREROUTING` 中所有 `SHADOWSOCKS*` 跳转。
- flush/delete `SHADOWSOCKS`、`SHADOWSOCKS_GFW/CHN/GAM/GLO/HOM`。
- 删除 mangle `PREROUTING` 中 `SHADOWSOCKS`。
- flush/delete mangle `SHADOWSOCKS` 和当前模式链。
- 删除 DNS 劫持链 `SHADOWSOCKS_DNS_<br>`。
- flush/delete ipset：`chnroute/white_list/black_list/gfwlist/router`。
- 删除 `lookup 310` 的 `ip rule` 和 table 310 路由。

风险点：当前代码有 `iptables -t nat -F OUTPUT`，这会清空 nat OUTPUT 表中其他插件或用户规则。合并文档后要保留这个风险，因为魔改 HY2 时如果频繁 restart，会放大对其他插件的影响。

---

## 9. HY2 官方 ARMv7 能力对照

基于 `hysteria_doc.md` 的 ARMv7 客户端能力整理：

| 官方字段 | 当前插件 | 建议优先级 | 说明 |
|---|---|---|---|
| `server` | 已支持 | 必须 | 可扩展多端口表达端口跳跃 |
| `auth` | 已支持 | 必须 | 来自 `ss_basic_password` |
| `tls.sni` | 已支持 | 必须 | 当前复用 `ss_basic_trojan_sni` |
| `tls.insecure` | 已支持 | 必须 | 当前复用 `ss_basic_allowinsecure` |
| `tls.pinSHA256` | 未支持 | 高 | 证书 pin |
| `obfs.type` | 未支持 | 高 | 目前官方实用类型是 `salamander` |
| `obfs.salamander.password` | 未支持 | 高 | 很多 HY2 节点会使用 |
| `bandwidth.up/down` | 未支持 | 高 | 决定 Brutal CC；不填则 BBR |
| `fastOpen` | 已固定 true | 可选 | 当前可保留 |
| `lazy` | 已固定 true | 可选 | 当前可保留 |
| `socks5.listen` | 已支持 | 必须 | `127.0.0.1:23456` |
| `tcpRedirect.listen` | 已支持 | 必须 | `0.0.0.0:3333` |
| `udpTProxy.listen` | 未支持 | 高 | Merlin UDP 链路关键 |
| `transport.udp.hopInterval` | 未支持 | 中 | 端口跳跃可选 |
| `quic.*` | 未支持 | 低 | ARMv7 默认不建议暴露太多 |
| `http/tun/tcpForwarding/udpForwarding` | 不支持 | 低 | 当前插件透明代理架构暂不需要 |

---

## 10. HY2 拓展设计

### 10.1 总体原则

1. 保持 `ss_basic_type=4 + ss_basic_trojan_binary=Hysteria2` 的兼容模型，不先大改协议枚举。
2. HY2 专属参数使用 `hy2_*` 新字段，不污染 Trojan/Trojan-Go 字段。
3. `create_hy2_json()` 和 `ss_webtest.sh:create_hy2_json()` 必须共享同一套字段含义。
4. JSON 生成要避免手写拼接逗号和未转义字符串。仓库已经包含 `jq`，优先用 `jq -n --arg ...` 生成。
5. UDP/TProxy 由 `mangle=1` 自动决定，保证 iptables 与 Hysteria 入站一致。

### 10.2 目标运行 JSON

最小状态：

```json
{
  "server": "example.com:443",
  "auth": "password",
  "tls": {
    "sni": "example.com",
    "insecure": false
  },
  "fastOpen": true,
  "lazy": true,
  "socks5": {
    "listen": "127.0.0.1:23456"
  },
  "tcpRedirect": {
    "listen": "0.0.0.0:3333"
  }
}
```

完整状态：

```json
{
  "server": "example.com:443",
  "auth": "password",
  "tls": {
    "sni": "example.com",
    "insecure": false,
    "pinSHA256": "base64-sha256-pin"
  },
  "obfs": {
    "type": "salamander",
    "salamander": {
      "password": "obfs-password"
    }
  },
  "bandwidth": {
    "up": "20 mbps",
    "down": "100 mbps"
  },
  "fastOpen": true,
  "lazy": true,
  "socks5": {
    "listen": "127.0.0.1:23456"
  },
  "tcpRedirect": {
    "listen": "0.0.0.0:3333"
  },
  "udpTProxy": {
    "listen": "0.0.0.0:3333",
    "timeout": "60s"
  }
}
```

### 10.3 `create_hy2_json()` 改造点

文件：`shadowsocks/ss/ssconfig.sh`

要改：

1. 读取新字段，空值不写可选块。
2. `obfs_type=salamander` 且 `obfs_password` 非空时写 `obfs`。
3. `up_mbps/down_mbps` 都是数字时写 `bandwidth`，格式是 `"数字 mbps"`。
4. `pin_sha256` 非空时写 `tls.pinSHA256`。
5. `mangle=1` 时写 `udpTProxy`。
6. 生成后用 `jq . "$HY2_CONFIG_FILE"` 验证。

伪代码：

```sh
create_hy2_json() {
  rm -f "$HY2_CONFIG_FILE"
  [ "$ss_basic_type" = "4" ] || return 0
  [ "$ss_basic_trojan_binary" = "Hysteria2" ] || return 0

  server="$(dbus get ss_basic_server):$ss_basic_port"
  sni="${ss_basic_trojan_sni}"
  insecure="$(get_function_switch "$ss_basic_allowinsecure")"

  jq -n \
    --arg server "$server" \
    --arg auth "$ss_basic_password" \
    --arg sni "$sni" \
    --argjson insecure "$insecure" \
    '{
      server: $server,
      auth: $auth,
      tls: {sni: $sni, insecure: $insecure},
      fastOpen: true,
      lazy: true,
      socks5: {listen: "127.0.0.1:23456"},
      tcpRedirect: {listen: "0.0.0.0:3333"}
    }' > "$HY2_CONFIG_FILE"

  # 可选字段用 jq 继续 merge，避免 shell 手写 JSON 逗号。
}
```

### 10.4 Web 测速同步

文件：`shadowsocks/scripts/ss_webtest.sh`

要加数组读取：

```text
array_hy2_obfs_type=$(dbus get ssconf_basic_hy2_obfs_type_$nu)
array_hy2_obfs_password=$(dbus get ssconf_basic_hy2_obfs_password_$nu)
array_hy2_up_mbps=$(dbus get ssconf_basic_hy2_up_mbps_$nu)
array_hy2_down_mbps=$(dbus get ssconf_basic_hy2_down_mbps_$nu)
array_hy2_pin_sha256=$(dbus get ssconf_basic_hy2_pin_sha256_$nu)
```

测速 JSON 不写 `tcpRedirect/udpTProxy`，只写 `socks5.listen=127.0.0.1:23458`。

### 10.5 Web UI 同步

建议在 Trojan/Hysteria2 面板中，当选择 `Hysteria2` 时显示：

| UI 字段 | dbus key | 说明 |
|---|---|---|
| HY2 混淆类型 | `ss_basic_hy2_obfs_type` | 空/none/salamander |
| HY2 混淆密码 | `ss_basic_hy2_obfs_password` | `obfs.salamander.password` |
| 上行 Mbps | `ss_basic_hy2_up_mbps` | 只填数字 |
| 下行 Mbps | `ss_basic_hy2_down_mbps` | 只填数字 |
| 证书 pin | `ss_basic_hy2_pin_sha256` | 可选 |
| 端口跳跃间隔 | `ss_basic_hy2_hop_interval` | 可选，配合 server 多端口 |

校验建议：

- `obfs_type=salamander` 时 `obfs_password` 必填。
- `up_mbps/down_mbps` 要么都空，要么都为正整数。
- 不要强制 bandwidth 必填；不填时走 BBR。
- HY2 选中时隐藏 Trojan-Go 的 WebSocket/path/host/mux 字段。

### 10.6 订阅同步

文件：`shadowsocks/scripts/ss_online_update.sh`

要改：

1. 订阅节点计数和过滤正则加入 `^hy2://`。
2. 单链接导入允许 `hy2://`。
3. `NODE_FORMAT=hy2` 时归一到 `hysteria2`。
4. `get_hysteria2_config()` 解析新增参数。
5. `add_hysteria2_servers()` 写入新增 `ssconf_basic_hy2_*_<n>`。
6. `update_hysteria2_config()` 用 `dbus_update_if_diff` 比较新增字段。
7. 删除节点和订阅清理时删除新增字段，避免残留。

---

## 11. 关键风险清单

| 风险 | 位置 | 影响 | 建议 |
|---|---|---|---|
| HY2 JSON 手写 heredoc 未转义 | `ssconfig.sh:create_hy2_json`、`ss_webtest.sh:create_hy2_json` | 密码/SNI/obfs 含引号或反斜杠会破坏 JSON | 用 `jq -n --arg` 生成 |
| UDP/TProxy 入站缺失 | `create_hy2_json` | 游戏模式/UDP 同步不可用 | `mangle=1` 时写 `udpTProxy` |
| 开机不重新生成 HY2 JSON | `apply_ss()` 的 `WAN_ACTION` 判断 | 文件不存在或字段过期会启动失败 | HY2 可考虑每次启动前生成 |
| `flush_nat()` 清空 nat OUTPUT | `ssconfig.sh:flush_nat` | 影响其他插件或用户规则 | 后续重构为只删除自身规则 |
| `load_tproxy()` 模块计数可疑 | `MODULES` 有 4 个，但校验逻辑比较 3 且使用 `j++` | 可能误判模块加载状态 | 重写为显式计数 |
| `hy2://` 未识别 | `ss_online_update.sh`、Web placeholder | 官方短前缀导入失败 | 正则和 NODE_FORMAT 加 alias |
| HY2 字段未加入所有 Web 数组 | `Main_Ss_Content.asp` 多处数组 | 保存、编辑、应用、删除不一致 | 按 10.5 清单逐项同步 |
| Web 测速未同步 HY2 参数 | `ss_webtest.sh` | 实际能用的节点测速失败 | 同步 `obfs/bandwidth/pin` |
| ARMv7 二进制来源混用 | `ss_v2ray_xray.sh` 当前 URL `380_armv5/hysteria` | 运行失败或版本不符 | 实机验证 `hysteria version` |

---

## 12. 实机验证清单

### 12.1 基础环境

```sh
uname -m
/koolshare/bin/hysteria version
file /koolshare/bin/hysteria
dbus list ss_basic | sort
dbus list ssconf_basic | grep Hysteria2
```

### 12.2 HY2 JSON

```sh
cat /koolshare/ss/hysteria.json
jq . /koolshare/ss/hysteria.json
```

必须确认：

- `server/auth/tls` 正确。
- 使用 obfs 的节点有 `obfs.type=salamander`。
- 使用带宽的节点有 `bandwidth.up/down`。
- 游戏模式或 UDP 同步时有 `udpTProxy.listen=0.0.0.0:3333`。

### 12.3 进程和监听

```sh
ps | grep hysteria | grep -v grep
netstat -nlp | grep hysteria
netstat -nlp | grep 3333
netstat -nlp | grep 23456
```

期望：

- TCP 透明代理：`0.0.0.0:3333`
- SOCKS5：`127.0.0.1:23456`
- 开启 UDP/TProxy 时：能看到 UDP 侧 `3333` 监听，具体输出取决于 busybox/netstat 版本。

### 12.4 iptables/ipset

```sh
iptables-save -t nat | grep SHADOWSOCKS
iptables-save -t mangle | grep SHADOWSOCKS
ip rule show | grep 310
ip route show table 310
ipset list gfwlist | head
ipset list chnroute | head
```

HY2 TCP 能用但 UDP 不通时，重点看：

```sh
iptables-save -t mangle | grep TPROXY
cat /koolshare/ss/hysteria.json | grep udpTProxy
```

如果有 TPROXY 规则但 JSON 没有 `udpTProxy`，就是当前已确认的 HY2 缺口。

### 12.5 DNS

```sh
netstat -nlp | grep 7913
netstat -nlp | grep 53
cat /jffs/configs/dnsmasq.d/gfwlist.conf | head
cat /tmp/wblist.conf | head
```

默认 `dns2socks` 路径：

```text
dnsmasq -> 127.0.0.1:7913 -> dns2socks -> 127.0.0.1:23456 -> hysteria socks5 -> HY2 server
```

### 12.6 Web 和订阅

```sh
/koolshare/scripts/ss_online_update.sh 4
/koolshare/scripts/ss_webtest.sh
/koolshare/scripts/ss_proc_status.sh
```

验证点：

- `hysteria2://` 和 `hy2://` 都能导入。
- 导入后 `ssconf_basic_hy2_*_<n>` 有值。
- 应用节点后 `ss_basic_hy2_*` 有值。
- 测速临时 JSON 包含 obfs/bandwidth/pin。

---

## 13. 推荐改造顺序

1. 先改数据模型和 Web 字段：让 `ss_basic_hy2_*`、`ssconf_basic_hy2_*_<n>` 能保存、回显、应用、删除。
2. 改 `ssconfig.sh:create_hy2_json()`：支持 `obfs`、`bandwidth`、`pinSHA256`，并在 `mangle=1` 时写 `udpTProxy`。
3. 改 `ss_webtest.sh:create_hy2_json()`：同步 obfs/bandwidth/pin，确保测速和真实运行一致。
4. 改 `ss_online_update.sh`：支持 `hy2://`，解析新增 URI 参数，新增/更新/删除都处理 HY2 字段。
5. 改 Web 文案和提示：订阅输入说明加入 `hy2://`，Hysteria2 面板显示新字段。
6. 实机按第 12 节验证 TCP、UDP、DNS、订阅、测速、重启恢复。

最小可用目标是：

```text
HY2 TCP 透明代理 + SOCKS5 DNS/订阅 + obfs + bandwidth + pinSHA256
```

完整链路目标是：

```text
HY2 TCP REDIRECT + UDP TPROXY + SOCKS5 + 订阅 hy2/hysteria2 + Web 节点管理 + Web 测速 + Merlin 重启恢复
```

---

## 14. 源码函数索引和魔改触点

这一节用于按文件找入口。HY2 魔改优先看“HY2 相关/必须同步”列。

### 14.1 `shadowsocks/ss/ssconfig.sh`

主控脚本，负责真正运行插件。

| 函数/区域 | 职责 | HY2 相关/必须同步 |
|---|---|---|
| 顶部全局变量 | `CONFIG_FILE`、`V2RAY_CONFIG_FILE`、`HY2_CONFIG_FILE`、端口、DNS、`mangle` 判断 | `HY2_CONFIG_FILE=/koolshare/ss/hysteria.json`；`mangle=1` 决定是否需要 `udpTProxy` |
| `kill_process()` | 停止代理、DNS、加速相关进程 | 已包含 `hysteria`，新增 HY2 子进程时要同步 |
| `restore_conf()` | 清理 dnsmasq、gfwlist、临时配置 | 一般不用改 |
| `start_dns()` | 启动国外 DNS 方案 | HY2 主要走 `dns2socks -> 23456` |
| `create_dnsmasq_conf()` | 生成/挂载 dnsmasq 分流配置 | HY2 不直接改这里，但影响 DNS 到 SOCKS5 链路 |
| `auto_start()` | 注入 `/jffs/scripts/wan-start`、`nat-start` | HY2 开机恢复依赖它 |
| `create_ipset()` | 创建 `chnroute/gfwlist/white_list/black_list/router` | HY2 复用 |
| `get_action_chain()` | 模式到链名映射 | HY2 复用所有模式 |
| `lan_acess_control()` | ACL 源 IP/端口分流 | HY2 复用；UDP ACL 只在 `mangle=1` 时生效 |
| `load_tproxy()` | 加载 TPROXY 内核模块 | HY2 UDP 必经；当前模块计数逻辑建议复查 |
| `flush_nat()` | 清理 iptables/ipset/策略路由 | HY2 复用；注意 nat OUTPUT 被清空风险 |
| `apply_nat_rules()` | 写 nat/mangle 规则 | HY2 TCP/UDP 入口都复用 `3333` |
| `chromecast()`/`dns_hijack_control()` | DNS 劫持到路由器 dnsmasq | HY2 复用 |
| `create_hy2_json()` | 生成 Hysteria2 运行 JSON | HY2 主改点：obfs/bandwidth/pin/udpTProxy |
| `start_hy2()` | 启动 `hysteria -c hysteria.json` | 通常无需为参数改命令行 |
| `apply_ss()` | 总启动流程 | HY2 配置生成、进程启动、NAT 加载都在这里串起来 |
| `disable_ss()` | 总停止流程 | HY2 停止和规则清理依赖它 |
| case 入口 | `start/restart/stop/flush_nat/*` | Web 最终会落到这里 |

### 14.2 `shadowsocks/webs/Main_Ss_Content.asp`

主 Web 页面，是 HY2 字段落库的第一关。

| 函数/区域 | 职责 | HY2 相关/必须同步 |
|---|---|---|
| `save()` | 保存当前运行配置，写 `ss_basic_*` 和当前节点 `ssconf_basic_*_<n>` | 新增 `ss_basic_hy2_*` 必须加入 `params_input` 和节点同步数组 |
| `push_data()` | POST `/applydb.cgi?p=ss` | 触发 `SystemCmd=ss_config.sh` |
| `update_ss_ui()` | 从对象恢复表单 | 新字段 id 与 key 一致即可自动恢复 |
| `verifyFields()` | 控制协议面板显隐 | Hysteria2 选中时显示 obfs/bandwidth/pin |
| `ssconf_node2obj()` | 节点 dbus -> 当前运行对象 | 新增 `ssconf_basic_hy2_*_<n>` 要映射到 `ss_basic_hy2_*` |
| `trojan_change_off()` | Trojan/Trojan-Go/Hysteria2 切换 | HY2 下隐藏 Trojan-Go 专属字段，显示 HY2 专属字段 |
| `add_ss_node_conf('trojan')` | 新增 Trojan 系节点 | `paramsTrojan` 加 HY2 字段 |
| `edit_conf_table()` | 编辑节点时回显 | `params1_input` 加 HY2 字段 |
| `edit_ss_node_conf('trojan')` | 保存编辑后的 Trojan 系节点 | `paramsTrojan` 加 HY2 字段 |
| `remove_conf_table()` | 删除节点字段 | 删除 `ssconf_basic_hy2_*_<n>`，避免残留 |
| `apply_this_ss_node()` | 应用节点为当前运行节点 | 依赖 `ssconf_node2obj()` 是否带齐 HY2 字段 |
| `save_online_nodes()` | 订阅/单链接入口 | 文案和后端都要支持 `hy2://` |
| `ss_binary_update(4)` | 更新 Hysteria2 二进制 | 走 `ss_v2ray_xray.sh` |

### 14.3 `shadowsocks/scripts/ss_online_update.sh`

订阅和单链接导入。

| 函数/区域 | 职责 | HY2 相关/必须同步 |
|---|---|---|
| 协议 grep 正则 | 从订阅文本中过滤节点链接 | 加 `^hy2://` |
| `NODE_FORMAT` 归一 | `trojan-go` -> `trojan_go` | 加 `hy2 -> hysteria2` |
| `get_hysteria2_config()` | 解析 HY2 URI | 加 obfs、obfs-password、pin、up/down、hy2 alias |
| `add_hysteria2_servers()` | 新增 HY2 节点 dbus | 写 `ssconf_basic_hy2_*_<n>` |
| `update_hysteria2_config()` | 更新已有 HY2 节点 | 比较并更新 `ssconf_basic_hy2_*_<n>` |
| 订阅删除/清理逻辑 | 删除不存在节点、清理协议残留字段 | 删除 HY2 新字段 |
| 单链接导入逻辑 | `ss_base64_links` 逐行导入 | 同样支持 `hy2://` 和新字段 |

### 14.4 `shadowsocks/scripts/ss_webtest.sh`

节点测速脚本。

| 函数/区域 | 职责 | HY2 相关/必须同步 |
|---|---|---|
| `start_webtest()` | 读取 `ssconf_basic_*_<n>` 到数组变量 | 加 HY2 新字段读取 |
| `create_hy2_json()` | 生成 `/tmp/tmp_hysteria.json` | 加 obfs/bandwidth/pin；不写 `tcpRedirect/udpTProxy` |
| HY2 分支 | 启动临时 hysteria 并 `speed_test_curl` | 确保测速端口是 `127.0.0.1:23458` |

### 14.5 其他脚本

| 文件 | 职责 | HY2 相关 |
|---|---|---|
| `scripts/ss_config.sh` | Web 应用入口，根据 `ss_basic_enable` 调 `ssconfig.sh restart/stop` | 不需要改 |
| `scripts/ss_v2ray_xray.sh` | xray/naive/hysteria 二进制更新和重启 | `ss_binary_update=4 -> hysteria` |
| `scripts/ss_proc_status.sh` | 状态页：版本、进程、iptables 状态 | 可加 UDP 监听检查 |
| `scripts/ss_lb_config.sh` | 负载均衡配置 | 当前 HY2 不属于核心改造点，若要 LB 支持 HY2 需另审 |
| `scripts/ss_socks5.sh` | 独立本地 Socks5 | 与 HY2 主运行 SOCKS5 不同 |
| `scripts/ss_rule_update.sh` | 规则更新 | HY2 复用 ipset/规则 |
| `scripts/ss_reboot_job.sh` | 定时重启/IP 变化触发 | HY2 复用 |
| `scripts/ss_pack.sh` | 从 `/koolshare` 打包插件 | HY2 二进制在 `TARGET_BIN` 中 |
| `install.sh` | 安装插件 | `TARGET_BIN` 包含 `hysteria` |
| `uninstall.sh` | 卸载插件 | `TARGET_BIN` 包含 `hysteria` |

### 14.6 运行时文件

| 文件 | 生成者 | 用途 |
|---|---|---|
| `/koolshare/ss/hysteria.json` | `ssconfig.sh:create_hy2_json()` | HY2 主运行配置 |
| `/tmp/tmp_hysteria.json` | `ss_webtest.sh:create_hy2_json()` | HY2 测速配置 |
| `/tmp/wblist.conf` | `create_dnsmasq_conf()` | 用户黑白名单域名分流 |
| `/tmp/gfwlist.conf` | `create_dnsmasq_conf()` | 回国模式等临时 gfwlist |
| `/jffs/configs/dnsmasq.d/gfwlist.conf` | 软链接 | dnsmasq gfwlist 分流 |
| `/jffs/scripts/dnsmasq.postconf` | 软链接 | dnsmasq 后处理 |
| `/var/lock/koolss.lock` | `set_lock()` | 防止并发启动/停止 |

