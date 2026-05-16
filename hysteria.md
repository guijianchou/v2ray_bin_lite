# Hysteria2 / HY2 支持链路审查

## 1. 结论

当前仓库已经把 Hysteria2 接入到了插件主链路，但实现方式仍然是“挂在 Trojan 类型下面的一个 binary 分支”，不是独立协议模型。

现有 HY2 支持的实际能力：

- Web 可以手动新增/编辑 Hysteria2 节点。
- Web 可以把运行节点切换为 `ss_basic_type=4` + `ss_basic_trojan_binary=Hysteria2`。
- Web 可以触发 `hysteria` 二进制在线更新。
- 订阅和单链接导入支持 `hysteria2://`。
- 主运行流程会生成 `/koolshare/ss/hysteria.json`。
- 主运行流程会启动 `/koolshare/bin/hysteria`。
- 测速脚本可以临时生成 HY2 配置并跑 SOCKS5 测速。
- 状态脚本会显示 hysteria 版本和进程状态。

现有 HY2 支持的核心限制：

- 只有 `server`、`auth`、`tls.sni`、`tls.insecure`、`socks5.listen`、`tcpRedirect.listen` 这些最小字段。
- Web 没有 HY2 专属字段，仍复用 Trojan 的 `server/port/password/sni/allowinsecure`。
- 订阅解析只处理 `sni` 和 `insecure`，忽略 obfs、pinSHA256、带宽、QUIC、端口跳跃、TUN、TProxy 等 Hysteria2 常见字段。
- 透明代理 TCP 能对上 `tcpRedirect: 0.0.0.0:3333`；UDP/TProxy 链路不完整，因为 iptables 可能把 UDP TPROXY 到 3333，但 HY2 配置没有 `udpTProxy`。
- 当前代码只识别 `hysteria2://`，没有识别常见别名 `hy2://`。
- JSON 生成是 heredoc 直拼，没有 JSON 转义；密码、SNI、server 中有特殊字符时可能生成非法 JSON。

如果目标是“完整支持 HY2 协议”，下一步不应该只改 `create_hy2_json`，而要把 Web 字段、dbus key、订阅解析、运行 JSON、测速 JSON、UDP/TProxy、状态/更新一起补齐。

## 2. HY2 在当前架构中的位置

HY2 没有独立的 `ss_basic_type`。当前类型判断如下：

```text
ss_basic_type=4
ss_basic_trojan_binary=Hysteria2
```

也就是说，HY2 与 Trojan、Trojan-Go 共用 type=4。

核心链路：

```text
Main_Ss_Content.asp
-> 写 ss_basic_trojan_binary=Hysteria2
-> SystemCmd=ss_config.sh
-> ss_config.sh
-> /koolshare/ss/ssconfig.sh restart
-> apply_ss
-> create_hy2_json
-> start_hy2
-> load_nat / start_dns / restart_dnsmasq
```

相关文件：

| 文件 | 作用 |
| --- | --- |
| `shadowsocks/webs/Main_Ss_Content.asp` | Web 主界面、节点新增/编辑、运行节点保存、订阅入口、二进制更新入口。 |
| `shadowsocks/scripts/ss_config.sh` | Web 保存后的最短入口，按 `ss_basic_enable` 调 `ssconfig.sh restart/stop`。 |
| `shadowsocks/ss/ssconfig.sh` | 生成 HY2 配置、启动/停止进程、加载 DNS/NAT。 |
| `shadowsocks/scripts/ss_online_update.sh` | 解析 `hysteria2://` 订阅或手动导入链接。 |
| `shadowsocks/scripts/ss_webtest.sh` | 临时启动 HY2 客户端做 Web 测速。 |
| `shadowsocks/scripts/ss_v2ray_xray.sh` | 更新 `hysteria` 二进制。 |
| `shadowsocks/scripts/ss_proc_status.sh` | 显示 hysteria 版本和进程状态。 |
| `shadowsocks/webs/Main_SsXray_Aggregate.asp` | 聚合页明确排除 Hysteria2。 |

## 3. dbus 字段模型

HY2 复用 Trojan 节点字段。

### 3.1 当前运行节点字段

| dbus key | 来源 | 运行侧用途 |
| --- | --- | --- |
| `ss_basic_type` | Web 保存或节点应用 | 必须为 `4`。 |
| `ss_basic_trojan_binary` | Web 下拉选择 | 必须为 `Hysteria2`。 |
| `ss_basic_server` | Web/订阅 | 写入 `hysteria.json.server`。 |
| `ss_basic_port` | Web/订阅 | 拼到 `server:port`。 |
| `ss_basic_password` | Web/订阅 | 写入 `hysteria.json.auth`。 |
| `ss_basic_trojan_sni` | Web/订阅 | 写入 `hysteria.json.tls.sni`。 |
| `ss_basic_allowinsecure` | Web/订阅 | 经 `get_function_switch` 转成 JSON boolean，写入 `tls.insecure`。 |
| `ss_basic_mode` | Web | 决定 NAT/IPSet 分流链。 |
| `ss_basic_udp_sync` | Web | 可能打开 mangle/TPROXY UDP 链路。 |

### 3.2 节点列表字段

| dbus key | 用途 |
| --- | --- |
| `ssconf_basic_type_<n>` | HY2 节点为 `4`。 |
| `ssconf_basic_trojan_binary_<n>` | HY2 节点为 `Hysteria2`。 |
| `ssconf_basic_name_<n>` | 节点名。 |
| `ssconf_basic_server_<n>` | 服务端。 |
| `ssconf_basic_port_<n>` | 端口。 |
| `ssconf_basic_password_<n>` | 密码/auth。 |
| `ssconf_basic_trojan_sni_<n>` | TLS SNI。 |
| `ssconf_basic_trojan_network_<n>` | 当前 HY2 写成 `0`，实际没有被 `create_hy2_json` 使用。 |
| `ssconf_basic_allowinsecure_<n>` | 是否跳过证书校验。 |
| `ssconf_basic_mode_<n>` | 节点默认模式。 |
| `ssconf_basic_group_<n>` | 订阅分组。 |

## 4. 主运行实现：create_hy2_json

位置：`shadowsocks/ss/ssconfig.sh:2127`

当前实现：

```sh
create_hy2_json(){
	rm -f "$HY2_CONFIG_FILE"
	if  [ "$ss_basic_type" == "4" ] && [ "$ss_basic_trojan_binary" == "Hysteria2" ]; then
		cat >"$HY2_CONFIG_FILE" <<-EOF
			{
				"server": "$(dbus get ss_basic_server):$ss_basic_port",
				"auth": "${ss_basic_password}",
				"tls": {
					"sni": "$ss_basic_trojan_sni",
					"insecure": $(get_function_switch $ss_basic_allowinsecure)
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
	EOF
	fi
}
```

### 4.1 字段含义

| JSON 字段 | 当前来源 | 说明 |
| --- | --- | --- |
| `server` | `dbus get ss_basic_server` + `$ss_basic_port` | 远端 HY2 服务地址。 |
| `auth` | `$ss_basic_password` | HY2 鉴权。 |
| `tls.sni` | `$ss_basic_trojan_sni` | 复用 Trojan SNI 字段。 |
| `tls.insecure` | `get_function_switch $ss_basic_allowinsecure` | Web checkbox `1/0` 转 `true/false`。 |
| `fastOpen` | 固定 `true` | Web 不可配置。 |
| `lazy` | 固定 `true` | Web 不可配置。 |
| `socks5.listen` | 固定 `127.0.0.1:23456` | 供 DNS、订阅代理、手动 SOCKS 使用。 |
| `tcpRedirect.listen` | 固定 `0.0.0.0:3333` | 对接 iptables TCP REDIRECT。 |

### 4.2 已经接通的能力

- TCP 透明代理链路是完整的：iptables 把 TCP REDIRECT 到 3333，HY2 的 `tcpRedirect.listen` 监听 3333。
- SOCKS5 链路是完整的：DNS 相关脚本和在线更新代理检测都使用 `127.0.0.1:23456`。
- `allowinsecure` 能从 Web 和订阅进入 JSON。
- `sni` 能从 Web 和订阅进入 JSON。

### 4.3 主要问题

1. JSON 字符串没有转义。

   `server`、`auth`、`sni` 直接拼进 JSON。只要值里包含双引号、反斜杠、换行等字符，就可能生成非法 JSON。

2. `server` 用 `dbus get ss_basic_server`，其它字段用 shell 变量。

   这不一定会坏，但风格不一致。更稳的方式是统一使用 `$ss_basic_server`，并统一做 JSON 转义。

3. IPv6 地址不安全。

   当前格式是 `host:port`。如果 `server` 是 IPv6，需要 `[ipv6]:port` 形式，否则会和端口冒号冲突。

4. UDP/TProxy 没接完整。

   `apply_nat_rules` 在 mangle 开启时会把 UDP 通过 TPROXY 丢到 3333，但 HY2 配置只有 `tcpRedirect.listen`，没有 `udpTProxy`。这会导致游戏模式或 `ss_basic_udp_sync=1` 场景下 UDP 透明代理无法按预期工作。

5. HY2 高级字段完全缺失。

   当前没有映射 obfs、带宽、QUIC 参数、端口跳跃、TLS pin、CA、TUN、HTTP/SOCKS 用户认证等字段。按“完整支持”目标，这些需要单独建模。

6. 没有配置文件有效性检查。

   `create_hy2_json` 写完后不跑 `hysteria` 的配置校验，也没有检查文件是否非空。启动失败时只会等 PID，错误细节被重定向丢弃。

## 5. 主运行实现：start_hy2

位置：`shadowsocks/ss/ssconfig.sh:2241`

当前实现：

```sh
start_hy2() {
	export QUIC_GO_DISABLE_ECN=true
	cd /koolshare/bin
	hysteria -c $HY2_CONFIG_FILE -l error --disable-update-check >/dev/null 2>&1 &
	local hy2PID
	local i=10
	until [ -n "$hy2PID" ]; do
		i=$(($i - 1))
		hy2PID=$(pidof hysteria)
		if [ "$i" -lt 1 ]; then
			echo_date "Hysteria2进程启动失败！"
			close_in_five
		fi
		sleep 1
	done
	echo_date Hysteria2启动成功，pid：$hy2PID
}
```

### 5.1 已经接通的能力

- 启动命令使用 `/koolshare/bin/hysteria`。
- 使用 `-c /koolshare/ss/hysteria.json` 指定配置。
- 禁用自动更新检查，适合路由器插件环境。
- 设置 `QUIC_GO_DISABLE_ECN=true`，规避部分旧内核/网络对 QUIC ECN 的兼容问题。
- 最多等 10 秒，拿到 `pidof hysteria` 后认为启动成功。

### 5.2 主要问题

1. 没有确认配置文件存在。

   如果 `WAN_ACTION` 场景跳过生成配置，但 `/koolshare/ss/hysteria.json` 不存在，启动会失败，只能通过 PID 超时感知。

2. 没有配置粒度的 PID 检查。

   `pidof hysteria` 只要看到任何 hysteria 进程就算成功。正常 restart 前会 `kill_process`，问题不大；但如果其它脚本残留了 hysteria 进程，可能误判。

3. 错误日志完全丢弃。

   `>/dev/null 2>&1` 会让 JSON 解析错误、TLS 错误、字段不支持等启动问题不可见。至少建议把 stderr 写到 `/tmp/hysteria_start.log` 或 `/tmp/syslog.log`。

4. 没有和 UDP/TProxy 配置联动。

   当 `mangle=1` 时，iptables 会准备 UDP TPROXY 到 3333。`start_hy2` 不知道当前 HY2 配置是否真的启用了 UDP TProxy。

## 6. apply_ss 中的 HY2 分支

位置：`shadowsocks/ss/ssconfig.sh:2948`

关键顺序：

```text
kill_process
restore_conf
restart_dnsmasq
flush_nat
kill_cron_job
ss_pre_start
detect
resolv_server_ip
load_module
create_ipset
create_dnsmasq_conf
create_hy2_json
start_hy2
start_kcp
start_dns
load_nat
mount_dnsmasq_now
restart_dnsmasq
auto_start
write_cron_job
set_ss_reboot_job
set_ss_trigger_job
ss_post_start
```

HY2 特殊点：

- `create_hy2_json` 只在 `WAN_ACTION` 为空时执行。路由器 WAN 启动触发时复用旧配置。
- `start_hy2` 不受 `WAN_ACTION` 限制，只要当前 type/binary 匹配就启动。
- `start_kcp` 仍会在 HY2 下执行，因为条件只是 `ss_basic_type != 2`。HY2 本身是 QUIC/UDP 协议，再叠 KCP/UDPspeeder/udp2raw 需要特别确认是否合理。
- `start_dns` 在 HY2 下照常使用 `127.0.0.1:23456`。
- `load_nat` 在 HY2 下照常把 TCP 透明流量指向 3333。

## 7. 停止流程

位置：`shadowsocks/ss/ssconfig.sh:192`

`kill_process` 会：

```text
pidof hysteria
-> killall hysteria
-> kill -9 <pid>
```

这能清理主 HY2 进程，但也会杀掉所有 hysteria 进程，包括可能正在测速的 `/tmp/tmp_hysteria.json` 进程。当前插件本来就是单任务模型，这个行为可以接受，但如果未来加独立本地 HY2 或多实例，就需要按配置文件或 pidfile 精确杀进程。

## 8. NAT 和 UDP/TProxy 链路

### 8.1 TCP 透明代理

`apply_nat_rules` 会把 TCP 分流到 3333：

```text
iptables -t nat ... -j REDIRECT --to-ports 3333
```

HY2 JSON 有：

```json
"tcpRedirect": {
  "listen": "0.0.0.0:3333"
}
```

所以 TCP 透明代理链路是对齐的。

### 8.2 SOCKS5

HY2 JSON 有：

```json
"socks5": {
  "listen": "127.0.0.1:23456"
}
```

下列功能会复用这个 SOCKS5：

- DNS 方案里的 `dns2socks 127.0.0.1:23456 ...`
- 订阅更新脚本里代理检测 `netstat -nlp | grep -w 23456 | grep hysteria`
- Web 测速临时代理。

### 8.3 UDP 透明代理缺口

`ssconfig.sh` 顶部会在以下条件设置 `mangle=1`：

```text
game_on 存在
或 ss_basic_mode=3
或 ss_basic_udp_sync=1
```

`apply_nat_rules` 在 `mangle=1` 时会：

```text
ip rule add fwmark 0x07 table 310
ip route add local 0.0.0.0/0 dev lo table 310
iptables -t mangle ... -j TPROXY --on-port 3333 --tproxy-mark 0x07
```

但 HY2 JSON 没有 `udpTProxy`。这意味着：

- TCP 进入 3333 是 REDIRECT，匹配 `tcpRedirect`。
- UDP 进入 3333 是 TPROXY，但 3333 上没有 HY2 的 UDP TProxy listener。
- 游戏模式和 UDP 同步模式下，HY2 的 UDP 透明代理大概率不可用或行为不确定。

如果要完整支持 HY2，建议新增 HY2 UDP 模式字段：

```text
ss_basic_hy2_udp_mode=off/socks/tproxy
ss_basic_hy2_udp_tproxy_port=3333
ss_basic_hy2_tcp_redirect_port=3333
```

然后在 JSON 中按需生成：

```json
"tcpRedirect": {
  "listen": "0.0.0.0:3333"
},
"udpTProxy": {
  "listen": "0.0.0.0:3333"
}
```

同时要让 `load_nat` 只在 HY2 确认支持 UDP TProxy 时开启对应 UDP mangle 分支。

## 9. Web 主界面实现

文件：`shadowsocks/webs/Main_Ss_Content.asp`

### 9.1 保存运行节点

`save()` 的核心：

```text
收集 ss_basic_* 字段
-> 收集 checkbox 字段
-> 把当前运行节点字段同步回 ssconf_basic_*_<node>
-> 设置 SystemCmd=ss_config.sh
-> POST /applydb.cgi?p=ss
```

HY2 相关字段在 `params_input` / `params_check` 中：

| Web DOM id | dbus key | HY2 用途 |
| --- | --- | --- |
| `ss_basic_trojan_binary` | `ss_basic_trojan_binary` | 值为 `Hysteria2` 时进入 HY2 分支。 |
| `ss_basic_server` | `ss_basic_server` | HY2 server。 |
| `ss_basic_port` | `ss_basic_port` | HY2 port。 |
| `ss_basic_password` | `ss_basic_password` | HY2 auth。 |
| `ss_basic_trojan_sni` | `ss_basic_trojan_sni` | HY2 SNI。 |
| `ss_basic_allowinsecure` | `ss_basic_allowinsecure` | HY2 TLS insecure。 |

`save()` 会把当前运行节点同步回节点列表：

```text
ssconf_basic_trojan_binary_<n>
ssconf_basic_trojan_sni_<n>
ssconf_basic_allowinsecure_<n>
```

### 9.2 UI 显隐

`verifyFields()` 对 HY2 的处理：

- `ss_basic_trojan_binary=Hysteria2` 时显示 Hysteria2 更新按钮。
- HY2 显示 `trojan_sni_basic_tr`。
- HY2 显示 `allowinsecure_basic_tr`。
- HY2 不显示 fragment。
- HY2 不显示 Trojan-Go 的网络、host、path、fingerprint、mux 等字段。

这说明 Web 侧当前把 HY2 视为“Trojan-like TLS auth 协议”，不是独立 HY2 配置模型。

### 9.3 手动新增节点

新增入口：

```text
pop_node_add()
-> Add_profile()
-> tabclickhandler(4)
-> add_ss_node_conf('trojan')
```

HY2 是在 Trojan/Trojan-Go/Hysteria2 下拉框里选择：

```html
<option value="Hysteria2">Hysteria2</option>
```

新增保存时使用：

```js
var paramsTrojan = [
  "name", "server", "mode", "port",
  "v2ray_network_path", "v2ray_network_host",
  "trojan_sni", "trojan_binary", "trojan_network",
  "allowinsecure", "v2ray_mux_concurrency", "fingerprint"
];
```

对 HY2 有效的字段只有：

```text
name/server/mode/port/trojan_sni/trojan_binary/allowinsecure/password/type
```

`v2ray_network_path`、`v2ray_network_host`、`trojan_network`、`v2ray_mux_concurrency`、`fingerprint` 对当前 `create_hy2_json` 没有实际作用。

### 9.4 编辑节点

编辑入口：

```text
edit_conf_table()
-> 判断 c["trojan_binary"] == "Hysteria2"
-> tabclickhandler(4)
-> edit_ss_node_conf('trojan')
```

编辑保存会写：

```text
ssconf_basic_trojan_binary_<n>
ssconf_basic_trojan_sni_<n>
ssconf_basic_allowinsecure_<n>
ssconf_basic_password_<n>
ssconf_basic_type_<n>=4
```

### 9.5 应用某节点

`apply_this_ss_node()` 通过 `ssconf_node2obj()` 把 `ssconf_basic_*_<n>` 转成 `ss_basic_*`，然后调用 `save()`。

`ssconf_node2obj()` 里有专门判断：

```js
if(trojan_binary=="Trojan-Go"){
  obj["ss_basic_trojan_binary"] = "Trojan-Go"
}else if(trojan_binary=="Hysteria2"){
  obj["ss_basic_trojan_binary"] = "Hysteria2"
}else{
  obj["ss_basic_trojan_binary"] = "Trojan"
}
```

这条链路是通的。

### 9.6 Web 二进制更新入口

Web 按钮：

```html
<a onclick="ss_binary_update(4)">更新Hysteria2程序</a>
```

`ss_binary_update(4)` 会提交：

```text
SystemCmd=ss_v2ray_xray.sh
ss_binary_update=4
```

后端会映射到：

```text
core_bin=hysteria
```

## 10. 订阅和单链接导入

文件：`shadowsocks/scripts/ss_online_update.sh`

### 10.1 订阅格式识别

订阅流程会识别：

```text
^hysteria2://
```

然后把协议名中的 `-` 替换成 `_`：

```sh
NODE_FORMAT="${line%%://*}"
NODE_FORMAT="${NODE_FORMAT//-/_}"
```

因此 `hysteria2://` 会调用：

```text
get_hysteria2_config
update_hysteria2_config
add_hysteria2_servers
```

当前不识别：

```text
hy2://
```

如果要兼容常见 HY2 URI，应该把 grep 正则和函数分派都补上 `hy2://`，并加一个 `get_hy2_config` 包装或在分派时映射 `hy2 -> hysteria2`。

### 10.2 get_hysteria2_config

当前解析：

```sh
server=$(echo "$decode_link" | awk -F':' '{print $1}' | awk -F'@' '{print $2}')
server_port=$(echo "$decode_link" | awk -F':' '{print $2}' | awk -F'\\/\\?' '{print $1}')
password=$(echo "$decode_link" | awk -F':' '{print $1}' | awk -F'@' '{print $1}')
password=`echo $password|base64_encode`
sni=$(echo "$decode_link" | tr '?#&' '\n' | grep 'sni=' | awk -F'=' '{print $2}')
insecure=$(echo "$decode_link" | tr '?#&' '\n' | grep 'insecure=' | awk -F'=' '{print $2}')
v2ray_net=0
binary="Hysteria2"
```

支持字段：

| URI 字段 | dbus 写入 |
| --- | --- |
| `auth/password` userinfo | `ssconf_basic_password_<n>` |
| host | `ssconf_basic_server_<n>` |
| port | `ssconf_basic_port_<n>` |
| `sni=` | `ssconf_basic_trojan_sni_<n>` |
| `insecure=` | `ssconf_basic_allowinsecure_<n>` |
| fragment `#name` | `ssconf_basic_name_<n>` |

问题：

- `awk -F':'` 解析不支持 IPv6。
- 密码里有 `@` 或 `:` 会解析错误。
- `insecure=true` 这类字符串不会被转换成 `1`，后续 `get_function_switch` 只认 `1`，所以订阅里的 `insecure=true` 最终会变成 JSON `false`。
- 只支持 `sni` 和 `insecure`，忽略其它 HY2 参数。
- 没有默认 SNI 逻辑；如果链接没有 `sni`，JSON 里会生成空字符串。
- 备注名只按 `#` 直接取，依赖前面全局 `urldecode`；单链接导入路径虽也有 `urldecode`，但仍缺少字段级健壮性。

### 10.3 add_hysteria2_servers / update_hysteria2_config

新增写入：

```text
ssconf_basic_type_<n>=4
ssconf_basic_trojan_binary_<n>=Hysteria2
ssconf_basic_trojan_sni_<n>=<sni>
ssconf_basic_allowinsecure_<n>=<insecure>
```

更新时会比较并更新：

```text
name/server/port/password/trojan_binary/trojan_network/trojan_sni/allowinsecure
```

缺口：

- 如果未来新增 HY2 专属字段，必须同步补到新增、更新、删除和配置压缩逻辑。
- 当前删除逻辑能识别 `type=4 + trojan_binary=Hysteria2` 并计入 `delnum7`。

### 10.4 单链接导入

Web 的“解析并保存为节点”提交 `ss_base64_links`，后端 `add()` 会逐条解析：

```text
NODE_FORMAT=hysteria2
get_hysteria2_config
add_hysteria2_servers 1
```

这条链路可用，但同样不支持 `hy2://` 和高级参数。

## 11. Web 测速

文件：`shadowsocks/scripts/ss_webtest.sh`

HY2 测速配置生成：

```json
{
  "server": "${array1}:${array2}",
  "auth": "${array3}",
  "tls": {
    "sni": "$(eval echo \$ssconf_basic_trojan_sni_$nu)",
    "insecure": $(get_function_switch $(eval echo \$ssconf_basic_allowinsecure_$nu))
  },
  "fastOpen": true,
  "lazy": true,
  "socks5": {
    "listen": "127.0.0.1:23458"
  }
}
```

测速启动：

```text
hysteria -c /tmp/tmp_hysteria.json -l error --disable-update-check
curl --socks5-hostname 127.0.0.1:23458 ...
kill ps|grep hysteria|grep tmp_hysteria
rm /tmp/tmp_hysteria.json
```

与主运行配置的差异：

| 项目 | 主运行 | Web 测速 |
| --- | --- | --- |
| SOCKS5 | `127.0.0.1:23456` | `127.0.0.1:23458` |
| TCP REDIRECT | 有，`0.0.0.0:3333` | 无 |
| UDP/TProxy | 无专门配置 | 无 |
| 日志 | 丢弃 | 丢弃 |

如果未来新增 HY2 参数，必须同步改 `ss_webtest.sh::create_hy2_json`，否则会出现“正式运行支持、测速不支持”的分裂。

## 12. 状态和更新

### 12.1 进程状态

`ss_proc_status.sh` 会：

- 读取 `/koolshare/bin/hysteria version`。
- 缓存到 `ss_basic_hysteria_version`。
- 用 `pidof hysteria` 判断进程。
- 在 `ss_basic_type=4` 分支中同时展示 xray、trojan-go、Hysteria2。

显示文字仍是 type=4 的 Trojan 语义：

```text
你正在使用Trojan
```

这对 HY2 用户不准确。建议按 `ss_basic_trojan_binary` 细分：

```text
Trojan
Trojan-Go
Hysteria2
```

### 12.2 二进制更新

`ss_v2ray_xray.sh`：

```text
ss_binary_update=4
-> core_bin=hysteria
-> url_main=.../380_armv5/hysteria
-> latest.txt
-> md5sum.txt
-> /koolshare/bin/hysteria
```

更新后如果进程正在运行，会调用 `start_v2ray()`，其中 HY2 分支会重新执行：

```sh
hysteria -c $HY2_CONFIG_FILE -l error --disable-update-check
```

这条链路可用。

风险：

- 如果更新时当前运行的不是 HY2，但系统里存在其它 hysteria 进程，更新脚本也会杀进程并按 HY2 配置启动。
- 更新后版本 key 写到 `ss_basic_hysteria_version`，状态脚本会复用。

## 13. 聚合页面

`Main_SsXray_Aggregate.asp` 读取 `trojan_binary`，但明确只允许：

```text
VMess
VLESS
Trojan
```

注释写明排除 Trojan-Go/Hysteria2。这个行为合理，因为 HY2 不是 Xray outbound，不应参与 Xray 聚合 JSON。

## 14. 与官方 Hysteria2 配置能力的差距

按 Hysteria2 官方客户端配置和 URI 文档，HY2 客户端配置远不止当前字段。当前代码只覆盖最小 TCP/SOCKS 场景。

需要评估是否补齐的能力：

| 能力 | 当前状态 | 建议 |
| --- | --- | --- |
| `hy2://` URI 别名 | 不支持 | 加入订阅和单链接导入。 |
| `hysteria2://` | 支持 | 保留。 |
| `sni` | 支持 | 继续保留。 |
| `insecure` | 部分支持 | 把 `true/1/yes` 统一转 `1`，`false/0/no` 转 `0`。 |
| obfs | 不支持 | 增加 Web/dbus/订阅/JSON 字段。 |
| TLS pin / CA | 不支持 | 若要增强安全性，应加字段。 |
| bandwidth / up / down | 不支持 | 路由器环境可选，默认留空。 |
| QUIC 参数 | 不支持 | 建议作为高级折叠项。 |
| fastOpen/lazy | 固定 true | 建议可配置或至少写入文档说明。 |
| tcpRedirect | 支持 | 端口建议可配置，默认 3333。 |
| udpTProxy | 不支持 | 若要游戏/UDP 完整支持，必须补。 |
| TUN | 不支持 | Merlin 插件不一定需要，谨慎。 |
| HTTP proxy | 不支持 | 当前插件主链路不需要。 |
| SOCKS5 listen | 支持固定端口 | 维持 23456，测速用 23458。 |

官方参考：

- `https://v2.hysteria.network/docs/advanced/Full-Client-Config/`
- `https://v2.hysteria.network/docs/developers/URI-Scheme/`

## 15. 完整支持 HY2 的建议改造方案

### 15.1 新增 HY2 专属 dbus 字段

建议不要继续把所有字段塞进 `trojan_*` 和 `v2ray_*`。

可以新增：

```text
ss_basic_hy2_sni
ss_basic_hy2_insecure
ss_basic_hy2_obfs_type
ss_basic_hy2_obfs_password
ss_basic_hy2_pin_sha256
ss_basic_hy2_fastopen
ss_basic_hy2_lazy
ss_basic_hy2_tcp_redirect_enable
ss_basic_hy2_tcp_redirect_port
ss_basic_hy2_udp_tproxy_enable
ss_basic_hy2_udp_tproxy_port
ss_basic_hy2_up_mbps
ss_basic_hy2_down_mbps
ss_basic_hy2_alpn
```

对应节点字段：

```text
ssconf_basic_hy2_*_<n>
```

为了兼容旧节点，可以在 `create_hy2_json` 中 fallback：

```text
hy2_sni 为空 -> 使用 ss_basic_trojan_sni
hy2_insecure 为空 -> 使用 ss_basic_allowinsecure
```

### 15.2 Web UI

新增 HY2 专属区域，只在 `ss_basic_trojan_binary=Hysteria2` 时显示：

```text
SNI
跳过证书校验
混淆类型
混淆密码
TLS pinSHA256
fastOpen
lazy
TCP REDIRECT
UDP TProxy
上行/下行带宽
```

要修改的位置：

- `params_input`
- `params_check`
- `ssconf_node2obj`
- `save()`
- `Add_profile()`
- `add_ss_node_conf('trojan')`
- `edit_conf_table()`
- `edit_ss_node_conf('trojan')`
- `remove_conf_table()`
- `verifyFields()`
- `tabclickhandler(4)`
- HTML 表单区域

### 15.3 create_hy2_json

建议重构成“按字段拼片段”，不要直接写死一个 heredoc。

至少应补：

```json
{
  "server": "...",
  "auth": "...",
  "tls": {
    "sni": "...",
    "insecure": false,
    "pinSHA256": "..."
  },
  "obfs": {
    "type": "salamander",
    "salamander": {
      "password": "..."
    }
  },
  "socks5": {
    "listen": "127.0.0.1:23456"
  },
  "tcpRedirect": {
    "listen": "0.0.0.0:3333"
  },
  "udpTProxy": {
    "listen": "0.0.0.0:3333"
  }
}
```

只在字段启用时写入对应 JSON 块。

### 15.4 NAT 联动

HY2 需要明确三种模式：

| 模式 | iptables | HY2 JSON |
| --- | --- | --- |
| 仅 SOCKS/DNS | 不需要 3333 | `socks5` |
| TCP 透明代理 | nat REDIRECT 到 3333 | `tcpRedirect` |
| TCP + UDP 透明代理 | nat REDIRECT + mangle TPROXY 到 3333 | `tcpRedirect` + `udpTProxy` |

当前代码无条件沿用其它协议的 3333 约定。完整支持时应避免“iptables 已经导 UDP，但 HY2 没监听 UDP TProxy”的状态。

### 15.5 订阅解析

需要改：

- grep 正则加入 `hy2://`。
- 分派时把 `hy2` 映射到 `hysteria2`。
- parser 改用 query parser 思路，不要只用 `awk -F ':'`。
- `insecure=true` 转换为 `1`。
- 支持 obfs、obfs-password、pinSHA256、sni、alpn、upmbps/downmbps 等字段。
- 支持 IPv6 host。
- 对 password、remarks 做 URL decode 后再写 dbus。

### 15.6 Web 测速同步

`ss_webtest.sh::create_hy2_json` 必须和主 `create_hy2_json` 保持字段一致，只改监听端口：

```text
主运行 SOCKS5: 23456
测速 SOCKS5: 23458
```

否则完整支持只会在正式运行生效，测速仍按旧最小配置跑。

## 16. 当前高优先级问题清单

| 优先级 | 问题 | 影响 |
| --- | --- | --- |
| P1 | mangle/TPROXY UDP 到 3333，但 HY2 配置没有 `udpTProxy` | 游戏模式或 UDP 同步场景下 HY2 UDP 透明代理不完整。 |
| P1 | 订阅 `insecure=true` 不会转成 `1` | 常见 HY2 链接导入后可能仍校验证书，连接失败。 |
| P1 | JSON heredoc 无转义 | 特殊字符会导致配置损坏。 |
| P2 | 不支持 `hy2://` | 常见 HY2 URI 无法导入。 |
| P2 | 不支持 obfs/pinSHA256 等 HY2 字段 | 许多节点无法完整导入。 |
| P2 | Web 没有 HY2 专属字段 | 用户无法手动配置完整 HY2。 |
| P2 | Web 测速配置和主配置需要同步维护 | 新增字段容易漏到测速侧。 |
| P3 | 状态页 type=4 文案仍写 Trojan | 对 HY2 用户不准确。 |
| P3 | `start_hy2` 无日志、无配置存在检查 | 排错成本高。 |

## 17. 实机验证清单

在 Merlin 380 设备上验证：

```sh
dbus get ss_basic_type
dbus get ss_basic_trojan_binary
dbus get ss_basic_server
dbus get ss_basic_port
dbus get ss_basic_trojan_sni
dbus get ss_basic_allowinsecure
cat /koolshare/ss/hysteria.json
ps | grep hysteria
netstat -nlp | grep -E '23456|3333'
iptables-save | grep -E '3333|SHADOWSOCKS|TPROXY'
ip rule show | grep 310
ip route show table 310
```

验证场景：

1. 手动新增 HY2 节点，保存并应用。
2. 编辑 HY2 节点，切换 SNI 和 insecure 后保存。
3. 导入 `hysteria2://` 链接。
4. 导入 `hy2://` 链接，当前应失败；改造后应成功。
5. Web 测速 HY2 节点。
6. GFWList/大陆白名单/全局模式下 TCP 访问。
7. 游戏模式或 `ss_basic_udp_sync=1` 下 UDP 访问。
8. 更新 Hysteria2 二进制后是否自动重启当前 HY2。
9. 路由器 WAN/NAT 重建后是否能复用 `/koolshare/ss/hysteria.json` 启动。

## 18. 推荐改造顺序

1. 修订订阅解析：`hy2://`、`insecure=true`、IPv6、字段 URL decode。
2. 修订 `create_hy2_json`：统一 JSON 转义，支持可选字段块。
3. 补 `udpTProxy` 与 NAT 联动，先解决 HY2 UDP 透明代理。
4. Web 增加 HY2 专属高级字段，保留旧 Trojan 字段 fallback。
5. 同步 `ss_webtest.sh` 的 HY2 JSON。
6. 状态页按 `ss_basic_trojan_binary` 显示真实协议。
7. 增加启动错误日志和配置存在检查。

这样改的好处是先保证现有节点不坏，再逐步把 HY2 从“Trojan 的一个 binary 选项”升级成可完整表达的协议分支。
