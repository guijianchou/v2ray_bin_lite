# v2ray_bin-main 知识拆解

## 0. 核心架构结论

这个项目首先应按“Web 壳 + dbus 配置层 + Shell 编排层 + 预编译二进制”的模型理解，而不是按常规源码工程或编译工程理解。

主调用链很短：

```text
Web ASP/JS 页面
-> 读写 dbus key
-> 设置 SystemCmd
-> Koolshare applydb.cgi/apply.cgi 执行 /koolshare/scripts/<SystemCmd>
-> 后端 Shell eval `dbus export ss`
-> 生成 json/dnsmasq/ipset/iptables/cru/nat-start/wan-start
-> 启动或停止 /koolshare/bin 下的预编译代理和 DNS 二进制
```

因此，魔改优先级不是“搭编译环境”，而是先抓住这四层：

| 层级 | 核心文件 | 主要问题 |
| --- | --- | --- |
| Web 壳 | `webs/Main_Ss_Content.asp`、`Main_Ss_LoadBlance.asp`、`Main_SsLocal_Content.asp`、`Main_SsXray_Aggregate.asp`、`res/ss-menu.js` | 页面把哪些字段写进 dbus，哪个按钮触发哪个 `SystemCmd`。 |
| dbus 配置层 | `ss_basic_*`、`ssconf_basic_*_<n>`、`ss_acl_*`、`ss_online_*`、`ss_lb_*`、`ss_local_*` | 字段命名、节点索引、当前节点复制、订阅节点维护。 |
| Shell 编排层 | `scripts/*.sh`、`ss/ssconfig.sh` | 根据 dbus 值生成运行配置，执行启动/停止/更新/测速/状态/规则/NAT/DNS。 |
| 运行二进制 | `bin/*`、`380_armv5/*` | 大多是预编译产物。文档只分析脚本如何配置和调用它们，不把它们当源码反编译对象。 |

日常改功能时最有效的读法：

1. 先在 Web 页面里找按钮、表单字段、`SystemCmd` 和提交对象。
2. 再找对应 `/koolshare/scripts/*.sh` 如何读取 dbus 和分派 action。
3. 涉及透明代理、DNS、iptables、进程启动时，再进 `ss/ssconfig.sh`。
4. 只有替换核心二进制时，才需要看 `380_armv5/` 和交叉编译/UPX 归档内容。

## 1. 项目定位

`v2ray_bin-main` 不是一个常规源码编译项目，而是一个面向 Koolshare/Merlin 固件的软件中心插件包。核心内容是 Shell 脚本、路由器 Web ASP 页面、dnsmasq/iptables 规则模板、预编译 ARMv5/ARMv7 二进制和历史发布包。

当前真正的运行主体在 `shadowsocks/` 目录下：

- `shadowsocks/ss/ssconfig.sh`：主运行脚本，负责启动、停止、重启、DNS、iptables/ipset、透明代理、守护任务和状态。
- `shadowsocks/webs/*.asp`：软件中心 Web UI，负责读写 dbus 配置、节点编辑、订阅、测速、状态展示。
- `shadowsocks/scripts/*.sh`：安装后辅助脚本，包括配置应用、订阅更新、规则更新、二进制更新、测速、状态、负载均衡、Socks5 本地服务。
- `shadowsocks/bin/*`：插件运行依赖的预编译二进制。
- `shadowsocks/ss/rules/*`：GFWList、chnroute、CDN、dnsmasq、SmartDNS、cdns 等规则和模板。
- `380_armv5/*`：历史核心二进制归档和在线更新源目录。
- `380_armv5_packge/*`：脚本引用的远端历史软件包发布路径；当前本地工作区未包含该目录。

如果主程序 `shadowsocks` 已经单独拷贝出来准备魔改，优先理解 `ssconfig.sh`、`Main_Ss_Content.asp` 和 `ss_online_update.sh` 三个文件。它们分别控制运行期、主 UI 和节点来源。

## 2. 目录结构

```text
v2ray_bin-main/
├─ README.md
├─ 380_armv5/
│  ├─ xray/
│  ├─ v2ray/
│  ├─ naive/
│  ├─ hysteria/
│  ├─ trojan-go/
│  ├─ shadowsocks-libev/
│  ├─ simple-obfs/
│  ├─ curl/
│  └─ readme.md
└─ shadowsocks/
   ├─ install.sh
   ├─ uninstall.sh
   ├─ bin/
   ├─ ss/
   │  ├─ ssconfig.sh
   │  ├─ version
   │  ├─ cru/
   │  │  ├─ china.sh
   │  │  └─ foreign.sh
   │  ├─ postscripts/
   │  │  └─ change_my_name.sh
   │  └─ rules/
   │     ├─ cdn.txt
   │     ├─ cdns.json
   │     ├─ chn.acl
   │     ├─ chnroute.txt
   │     ├─ dnsmasq.postconf
   │     ├─ gfwlist.acl
   │     ├─ gfwlist.conf
   │     ├─ smartdns_template.conf
   │     └─ version
   ├─ scripts/
   ├─ webs/
   └─ res/
```

### 2.1 主要目录职责

| 路径 | 作用 |
| --- | --- |
| `shadowsocks/install.sh` | 安装插件到 `/koolshare`，写默认 dbus 键，注册软件中心元信息。 |
| `shadowsocks/uninstall.sh` | 停止服务、删除文件、删除 dbus 配置、恢复 dnsmasq 和启动脚本。 |
| `shadowsocks/ss/ssconfig.sh` | 插件主控。所有透明代理、DNS、NAT、进程启动、cru 定时任务都集中在这里。 |
| `shadowsocks/scripts/ss_config.sh` | Web UI 提交后的入口，根据 `ss_basic_enable` 调用 `ssconfig.sh restart` 或 `stop`。 |
| `shadowsocks/scripts/ss_online_update.sh` | 订阅下载、链接解析、节点新增、节点更新、节点删除、索引压缩。 |
| `shadowsocks/scripts/ss_rule_update.sh` | 更新 `gfwlist.conf`、`chnroute.txt`、`cdn.txt`。 |
| `shadowsocks/scripts/ss_update.sh` | 更新整个 shadowsocks 插件包。 |
| `shadowsocks/scripts/ss_v2ray_xray.sh` | 更新 `xray`、`naive`、`hysteria` 等核心二进制。 |
| `shadowsocks/scripts/ss_webtest.sh` | 临时启动单节点本地代理并测试访问速度。 |
| `shadowsocks/scripts/ss_ping.sh` | 节点 ping 测试。 |
| `shadowsocks/scripts/ss_proc_status.sh` | 输出进程、DNS、iptables、规则版本状态。 |
| `shadowsocks/scripts/ss_udp_status.sh` | 输出 UDP 加速相关状态。 |
| `shadowsocks/scripts/ss_lb_config.sh` | 生成 haproxy 配置并启动负载均衡。 |
| `shadowsocks/scripts/ss_socks5.sh` | 单独启动或停止本地 Socks5 客户端。 |
| `shadowsocks/webs/Main_Ss_Content.asp` | 主页面，负责节点、模式、ACL、订阅、状态、更新。 |
| `shadowsocks/webs/Main_Ss_LoadBlance.asp` | 负载均衡页面。 |
| `shadowsocks/webs/Main_SsLocal_Content.asp` | 本地 Socks5 页面。 |
| `shadowsocks/webs/Main_SsXray_Aggregate.asp` | Xray 多出口聚合 JSON 生成页面。 |
| `shadowsocks/res/ss-menu.js` | 软件中心 UI 公共 JS、加载条、菜单、客户端下拉框、内置 Base64/beautify。 |

## 3. 安装和运行时布局

安装后，插件主要被复制到这些路径：

| 运行时路径 | 来源 | 作用 |
| --- | --- | --- |
| `/koolshare/bin/*` | `shadowsocks/bin/*` | 代理核心、DNS 工具、辅助工具。 |
| `/koolshare/ss/*` | `shadowsocks/ss/*` | 主控脚本、规则、模板、版本。 |
| `/koolshare/scripts/*` | `shadowsocks/scripts/*` | 软件中心可调用脚本。 |
| `/koolshare/webs/*` | `shadowsocks/webs/*` | Web UI 页面。 |
| `/koolshare/res/*` | `shadowsocks/res/*` | UI CSS、JS、图片、状态片段。 |
| `/jffs/configs/dnsmasq.d/*` | 运行时生成或挂载 | dnsmasq 分流配置。 |
| `/tmp/*.json`、`/koolshare/ss/*.json` | 运行时生成 | Xray、Trojan、Naive、Hysteria、SS2022 配置。 |
| `/tmp/ss_proc_status.log` | 状态脚本生成 | Web 页面进程状态数据。 |
| `/tmp/ss_udp_status.log` | 状态脚本生成 | Web 页面 UDP 状态数据。 |
| `/tmp/upload/ss_log.txt` | 各脚本追加 | Web UI 实时日志。 |

## 4. 数据模型和 dbus key

该插件没有传统数据库。所有持久配置主要通过 `dbus` 键值保存。Shell 侧通过：

```sh
eval `dbus export ss`
```

把所有 `ss*` 前缀配置导出成 Shell 变量。Web 侧通过 `/_api/ss`、`applydb.cgi`、`apply.cgi` 读写。

### 4.1 主要 key 家族

| key 前缀 | 含义 |
| --- | --- |
| `ss_basic_*` | 当前运行节点和插件全局设置，比如启用、模式、当前节点、DNS、端口、订阅、更新、KCP/UDP 加速。 |
| `ssconf_basic_*_<n>` | 节点列表，第 `n` 个节点的协议、地址、端口、密码、传输层、TLS、Reality、Fragment、测速数据等。 |
| `ss_acl_*` | 局域网访问控制 ACL，按客户端 IP/MAC/端口/代理模式生成分流规则。 |
| `ss_wan_*` | WAN 侧黑白名单，包括域名、IP、Chromecast 等特殊处理。 |
| `ss_online_*`、`ss_basic_online_*` | 订阅链接、订阅动作、订阅策略、订阅分组。 |
| `ss_lb_*` | haproxy 负载均衡开关、端口、节点、心跳检测。 |
| `ss_local_*` | 独立 Socks5 本地客户端配置。 |
| `ss_binary_update` | 二进制更新目标，通常映射到 Xray、Naive、Hysteria。 |
| `ss_basic_rule_update*` | 规则自动更新计划。 |

### 4.2 节点协议字段

每个节点主要由 `ssconf_basic_*_<n>` 保存，再在应用节点时复制到 `ss_basic_*`：

| 字段 | 说明 |
| --- | --- |
| `ssconf_basic_type_<n>` | 协议大类。`0` SS，`1` SSR，`2` koolgame，`3` Xray/V2Ray/SS2022，`4` Trojan/Trojan-Go/Hysteria2，`5` NaiveProxy。 |
| `ssconf_basic_name_<n>` | 节点名称。 |
| `ssconf_basic_server_<n>` | 服务器域名或 IP。 |
| `ssconf_basic_port_<n>` | 远端端口。 |
| `ssconf_basic_password_<n>` | 密码或 UUID。 |
| `ssconf_basic_method_<n>` | 加密方式。SS2022 通过 `2022-blake3-*` 或 `none` 识别。 |
| `ssconf_basic_v2ray_protocol_<n>` | Xray 协议，常见为 `vmess`、`vless`。 |
| `ssconf_basic_v2ray_network_<n>` | 传输层，常见为 `tcp`、`ws`、`h2`、`grpc`、`quic`、`kcp`。 |
| `ssconf_basic_v2ray_network_security_<n>` | `tls`、`reality` 或空。 |
| `ssconf_basic_v2ray_use_json_<n>` | 是否使用自定义 JSON。 |
| `ssconf_basic_v2ray_json_<n>` | 自定义 Xray JSON。 |
| `ssconf_basic_ping_<n>` | ping 测试结果。 |
| `ssconf_basic_webtest_<n>` | Web 测速结果。 |
| `ssconf_basic_group_<n>` | 订阅分组标记。 |
| `ssconf_basic_online_<n>` | 是否来自订阅。 |
| `ssconf_basic_use_lb_<n>` | 是否被负载均衡选中。 |

## 5. 关键端口和进程

| 端口 | 进程或用途 |
| --- | --- |
| `3333` | 透明代理 redir 入站，iptables 会把 TCP 流量转到这里。 |
| `23456` | 插件内部 Socks5 端口，用于 DNS 出口、订阅下载代理、测速代理。 |
| `23458` | `ss_webtest.sh` 临时测速 Socks5 端口。 |
| `7913` | 国外 DNS 本地转发端口。 |
| `53` | dnsmasq 或 SmartDNS 监听端口。 |
| `1091` | KCP 本地端口。 |
| `1092` | UDP 加速链路中间端口。 |
| `1093` | UDP2RAW 链路中间端口。 |
| `ss_lb_port` | haproxy 负载均衡本地端口。 |

| 进程 | 触发条件 |
| --- | --- |
| `ss-redir` | SS-libev 透明代理。 |
| `rss-redir` | SSR-libev 透明代理。 |
| `ss-local` | 本地 Socks5，SS 或独立 local 页面。 |
| `rss-local` | SSR 本地 Socks5。 |
| `ss-tunnel`、`rss-tunnel` | DNS 走远端解析时使用。 |
| `xray` | Vmess、Vless、Trojan、SS2022、Xray 自定义 JSON。 |
| `trojan-go` | Trojan-Go。 |
| `naive` | NaiveProxy。 |
| `hysteria` | Hysteria2。 |
| `koolgame` | Koolgame 模式。 |
| `haproxy` | 负载均衡。 |
| `dns2socks` | DNS over Socks。 |
| `chinadns`、`chinadns1`、`chinadns-ng` | 国内外 DNS 分流。 |
| `cdns` | cdns DNS 方案。 |
| `smartdns` | SmartDNS 方案。 |
| `https_dns_proxy` | DoH 方案。 |
| `client_linux_arm5` | KCP 客户端。 |
| `speederv1`、`speederv2`、`udp2raw` | UDP 加速。 |
| `haveged` | 熵池补充。 |

## 6. 协议启动矩阵

| `ss_basic_type` | 协议族 | 配置生成函数 | 启动函数 | 主要二进制 |
| --- | --- | --- | --- | --- |
| `0` | Shadowsocks-libev | `create_ss_json` | `start_ss_redir`、`start_sslocal` | `ss-redir`、`ss-local`、`ss-tunnel` |
| `1` | ShadowsocksR-libev | `create_ss_json` | `start_ss_redir`、`start_sslocal` | `rss-redir`、`rss-local`、`rss-tunnel` |
| `2` | koolgame | 无独立 JSON | `start_koolgame` | `koolgame`、`pdu` |
| `3` | Vmess/Vless/Xray/SS2022 | `create_v2ray_json` 或 `create_ss2022_json` | `start_xray` 或 `start_ss2022` | `xray` |
| `4` | Trojan | `create_trojan_json` | `start_trojan` | `xray` |
| `4` | Trojan-Go | `create_trojango_json` | `start_trojango` | `trojan-go` |
| `4` | Hysteria2 | `create_hy2_json` | `start_hy2` | `hysteria` |
| `5` | NaiveProxy | `create_naive_json` | `start_naiveproxy` | `naive` |

`SS2022` 是特殊分支：如果 `ss_basic_type=0` 且 method 命中 `2022-blake3-*` 或 `none`，脚本会把类型修正为 `3` 并设置 `SS2022=Y`，后续由 Xray 承载。

## 7. 主流程总览

### 7.1 安装流程

入口：`shadowsocks/install.sh`

```text
检查架构和固件版本
-> 如果插件已启用，先调用 /koolshare/ss/ssconfig.sh stop
-> 备份 postscripts
-> 如 dnsmasq-fastlookup 已挂载则卸载
-> 删除旧版插件文件
-> 拷贝 bin、ss、scripts、webs、res 到 /koolshare
-> chmod 可执行权限
-> 创建必要软链，例如 rss-tunnel、base64、shuf、netstat、S99socks5
-> 写入默认 dbus 配置和软件中心 metadata
-> 如果安装前启用，则恢复启动
```

重点：安装脚本会直接操作 `/koolshare`、`/jffs/scripts`、`/tmp`、dbus 和软件中心。魔改安装逻辑时要同时考虑升级安装和首次安装。

### 7.2 卸载流程

入口：`shadowsocks/uninstall.sh`

```text
调用 /koolshare/ss/ssconfig.sh stop
-> 调用 ss_conf_remove.sh 清理节点和配置
-> 恢复 dnsmasq 相关挂载
-> 删除 /koolshare 中的脚本、Web、资源、二进制、启动项
-> 从 nat-start、wan-start 等启动脚本删除插件注入行
-> 删除软件中心和 dbus metadata
```

### 7.3 Web 主页面应用流程

入口：`shadowsocks/webs/Main_Ss_Content.asp`

```text
init()
-> getAllConfigs() 从 /_api/ss 读取所有配置
-> loadBasicOptions() 渲染基础设置
-> loadAllConfigs() 渲染节点列表、ACL、订阅、状态
-> 用户修改配置或节点
-> save() 收集表单和 checkbox
-> 对密码、自定义 JSON、自定义规则等字段做 base64 编码
-> 将当前节点 ssconf_basic_*_<n> 同步到 ss_basic_*
-> 设置 SystemCmd=ss_config.sh
-> POST /applydb.cgi?p=ss
```

后端入口：`shadowsocks/scripts/ss_config.sh`

```text
eval `dbus export ss`
if ss_basic_enable=1:
    /koolshare/ss/ssconfig.sh restart
else:
    /koolshare/ss/ssconfig.sh stop
```

### 7.4 主控 restart 流程

入口：`shadowsocks/ss/ssconfig.sh restart`，核心函数：`apply_ss`

```text
set_lock
-> apply_ss
   -> ss_pre_stop
   -> 清理 nvram/dbus 状态标记
   -> kill_process
   -> remove_ss_reboot_job
   -> remove_ss_trigger_job
   -> restore_conf
   -> restart_dnsmasq
   -> flush_nat
   -> kill_cron_job
   -> ss_pre_start
   -> detect
   -> resolv_server_ip
   -> load_module
   -> create_ipset
   -> create_dnsmasq_conf
   -> 按协议生成 JSON 或参数
   -> 启动代理进程
   -> start_kcp
   -> start_dns
   -> load_nat
   -> mount_dnsmasq_now
   -> restart_dnsmasq
   -> auto_start
   -> write_cron_job
   -> set_ss_reboot_job
   -> set_ss_trigger_job
   -> ss_post_start
-> unset_lock
```

关键点：

- stop 和 start 不是简单进程重启。它会重建 dnsmasq、ipset、iptables、cru 定时任务、启动脚本注入。
- NAT 必须在代理和 DNS 基本就绪后加载，否则透明代理链可能指向不存在的本地端口。
- `ss_pre_start` 会处理负载均衡预启动，可能把当前节点切换到本地 haproxy。

### 7.5 stop 流程

入口：`ssconfig.sh stop`，核心函数：`disable_ss`

```text
set_lock
-> disable_ss
   -> ss_pre_stop
   -> kill_process
   -> remove_ss_reboot_job
   -> remove_ss_trigger_job
   -> restore_conf
   -> restart_dnsmasq
   -> flush_nat
   -> kill_cron_job
   -> umount_dnsmasq_now
   -> 重置 dbus/nvram 状态
-> unset_lock
```

### 7.6 DNS 流程

主要函数：`create_dnsmasq_conf`、`start_dns`、`mount_dnsmasq_now`、`restart_dnsmasq`

```text
读取 ss_dns_china 和 ss_foreign_dns
-> 生成 /tmp/custom.conf、/tmp/wblist.conf、/tmp/sscdn.conf
-> 根据代理模式写 gfwlist、chnroute、cdn、黑白名单域名规则
-> 将生成文件挂载或链接到 /jffs/configs/dnsmasq.d/
-> start_dns 按 foreign DNS 模式启动一个或多个 DNS 辅助进程
-> 重启 dnsmasq
```

常见方案：

| `ss_foreign_dns` | 作用 |
| --- | --- |
| `1` | 使用远端解析，通常配合 `ss-tunnel` 或 `rss-tunnel`。 |
| `2` | `chinadns` 方案。 |
| `3` 或空 | dns2socks 方案。 |
| `4` | tunnel 类方案，随 SS/SSR 类型变化。 |
| `5` | cdns 方案。 |
| `6` | chinadns1。 |
| `7` | Xray DNS。 |
| `8` | 不走国外 DNS，适合回国或特殊模式。 |
| `9` | SmartDNS。 |
| `10` | chinadns-ng。 |

国内 DNS 主要由 `ss_dns_china` 决定。相关规则模板在 `ss/rules/`。

### 7.7 NAT 和透明代理流程

主要函数：`load_module`、`flush_nat`、`create_ipset`、`add_white_black_ip`、`apply_nat_rules`、`lan_acess_control`、`dns_hijack_control`、`chromecast`

```text
load_module 加载 xt_set、xt_TPROXY、xt_socket 等模块
-> flush_nat 清理历史链、ipset 和策略路由
-> create_ipset 导入 chnroute、gfwlist、cdn、黑白名单
-> apply_nat_rules 创建 SHADOWSOCKS 系列 nat 链
-> 如开启 UDP/game 模式，创建 mangle TPROXY 链
-> lan_acess_control 按客户端 ACL 追加规则
-> dns_hijack_control 接管 LAN DNS
-> chromecast 做特殊 DNS 绕行
```

主要链：

| 链 | 作用 |
| --- | --- |
| `SHADOWSOCKS` | 主透明代理链。 |
| `SHADOWSOCKS_EXT` | 扩展链，处理黑白名单、局域网、端口。 |
| `SHADOWSOCKS_GFW` | GFWList 模式。 |
| `SHADOWSOCKS_CHN` | 大陆白名单或 chnroute 模式。 |
| `SHADOWSOCKS_GAM` | 游戏/UDP 模式。 |
| `SHADOWSOCKS_GLO` | 全局模式。 |
| `SHADOWSOCKS_HOM` | 回国模式。 |

### 7.8 订阅导入和更新流程

入口：`Main_Ss_Content.asp` 的 `get_online_nodes()`、`save_online_nodes()`，后端：`ss_online_update.sh`

动作映射：

| `ss_online_action` | 含义 |
| --- | --- |
| `0` | 删除所有节点。 |
| `1` | 删除订阅节点。 |
| `2` | 只保存订阅设置和定时任务。 |
| `3` | 下载订阅并更新节点。 |
| `4` | 从输入框解析并导入链接。 |

更新流程：

```text
detect 检查固件和环境
-> prepare 读取已有节点，建立本地节点索引
-> 如果需要代理下载，open_socks_23456 临时打开 Socks5
-> 下载订阅内容或读取手动输入内容
-> base64decode_link、urldecode 解码
-> 按链接前缀识别 ss、ssr、vmess、trojan、vless、trojan-go、hysteria2
-> get_${format}_config 解析链接到临时变量
-> update_${format}_config 尝试匹配并更新已有节点
-> add_${format}_servers 新增不存在节点
-> del_none_exist 删除订阅中已经消失的旧节点
-> remove_node_gap 压缩节点编号空洞
-> change_cru 设置或取消订阅定时任务
```

分组逻辑：每个订阅 URL 使用 `url_count * 1000` 作为分组区间基础，便于识别同一个订阅来源。

### 7.9 节点测速流程

ping 测试：

```text
Main_Ss_Content.asp::ping_test()
-> apply.cgi 执行 ss_ping.sh
-> ss_ping.sh 遍历选中或全部节点
-> 写入 ssconf_basic_ping_<n>
-> UI 轮询 refresh_ss_node_list_ping()
```

Web 测速：

```text
Main_Ss_Content.asp::web_test()
-> apply.cgi 执行 ss_webtest.sh
-> ss_webtest.sh 按节点生成临时客户端配置
-> 在 23458 启动临时 Socks5
-> curl/httping 访问测试域名
-> 写入 ssconf_basic_webtest_<n>
-> 清理临时进程
-> UI 轮询 refresh_ss_node_list_webtest()
```

### 7.10 状态展示流程

```text
Main_Ss_Content.asp::get_proc_status()
-> apply.cgi 执行 ss_proc_status.sh
-> 写 /tmp/ss_proc_status.log
-> Web 读取 /res/ss_proc_status.htm 或日志片段
```

```text
Main_Ss_Content.asp::get_udp_status()
-> apply.cgi 执行 ss_udp_status.sh
-> 写 /tmp/ss_udp_status.log
-> Web 读取 /res/ss_udp_status.htm 或日志片段
```

`ss_proc_status.sh` 会检查主进程、DNS 进程、iptables 链、规则版本、二进制版本。`ss_udp_status.sh` 只聚焦 UDP 加速链路。

### 7.11 负载均衡流程

入口：`Main_Ss_LoadBlance.asp`，后端：`ss_lb_config.sh`

```text
UI 选择多个节点，设置 ssconf_basic_use_lb_<n>=1
-> save() 写入 ss_lb_* 配置
-> ss_lb_config.sh 生成 /koolshare/configs/haproxy.cfg
-> start_haproxy 启动 haproxy
-> 主流程 ss_pre_start 检测 lb_enable
-> 当前 ss_basic_server/port 可指向 127.0.0.1:ss_lb_port
```

注意：UI 中对 Xray/koolgame 等节点存在限制，负载均衡主要面向 SS/SSR 类节点。

### 7.12 本地 Socks5 流程

入口：`Main_SsLocal_Content.asp`，后端：`ss_socks5.sh`

```text
UI 写 ss_local_* 配置
-> SystemCmd=ss_socks5.sh
-> ss_socks5.sh start 或 stop
-> start_socks5 生成 ss-local 参数
-> 支持 v2ray-plugin、obfs、ACL
```

该功能和主透明代理相对独立，但共用 `/koolshare/bin/ss-local`、`obfs-local`、`v2ray-plugin`。

### 7.13 规则更新流程

入口：`ss_rule_update.sh`

```text
读取本地 ss/rules/version
-> 从 https://raw.githubusercontent.com/qxzg/Actions/master/fancyss_rules 下载远端 version
-> 按开关更新 gfwlist、chnroute、cdn
-> 校验 md5
-> 替换 /koolshare/ss/rules/ 对应文件
-> 如果规则变化且插件已启用，则重启 ssconfig.sh restart
-> change_cru 写规则定时更新任务
```

### 7.14 插件包更新流程

入口：`ss_update.sh`

```text
读取本地 ss_basic_version_local
-> 下载远端 latest/version/md5
-> 下载 shadowsocks.tar.gz
-> 校验 md5
-> 解包到 /tmp/shadowsocks
-> 调用 install.sh 覆盖安装
```

远端路径指向 `https://raw.githubusercontent.com/cary-sas/v2ray_bin/main/380_armv5_packge`。

### 7.15 核心二进制更新流程

入口：`ss_v2ray_xray.sh`

```text
根据 ss_binary_update 选择 core_bin
-> get_bin_version 读取本地版本
-> get_latest_version 下载 latest.txt
-> update_now 下载二进制和 md5sum.txt
-> check_md5sum 校验
-> install_binary 替换 /koolshare/bin/<core_bin>
-> 如果当前进程在运行，start_v2ray 重启相关服务
```

通常映射：

| `ss_binary_update` | core |
| --- | --- |
| `2` | `xray` |
| `3` | `naive` |
| `4` | `hysteria` |

### 7.16 Xray 聚合 JSON 流程

入口：`Main_SsXray_Aggregate.asp`，运行期处理在 `ssconfig.sh::create_v2ray_json`

```text
UI 读取所有节点
-> 用户选择多个 Xray 兼容节点
-> buildOutboundsFromSelection() 为每个节点生成 outbound
-> 写入第一个 xagg_meta blackhole outbound，携带 strategy
-> gen_json() 输出自定义 JSON
-> 主页面保存到 ssconf_basic_v2ray_json_<n>
-> create_v2ray_json 检测 outbounds tag 是否以 xagg_ 开头
-> 移除 xagg_meta
-> 读取 xagg_meta.settings.strategy，默认 leastPing
-> 注入 routing.balancers 和 observatory
-> 生成 /koolshare/ss/v2ray.json
-> start_xray 启动 xray
```

`ss_webtest.sh` 也有类似处理，但测速侧默认使用 `leastPing`。

## 8. 函数索引

### 8.1 `shadowsocks/ss/ssconfig.sh`

| 函数 | 作用 |
| --- | --- |
| `get_lan_cidr` | 获取 LAN 网段 CIDR，用于 NAT 和绕行。 |
| `get_wan0_cidr` | 获取 WAN 网段 CIDR。 |
| `get_server_resolver` | 选择解析节点域名的 DNS。 |
| `set_lock` | 对主流程加锁，避免并发启动或停止。 |
| `unset_lock` | 释放主流程锁。 |
| `close_in_five` | 日志窗口倒计时关闭提示。 |
| `restore_conf` | 恢复被插件修改的配置和临时文件。 |
| `kill_process` | 杀掉代理、DNS、加速、haproxy、haveged 等相关进程。 |
| `ss_pre_start` | 启动前处理，主要包括负载均衡预处理。 |
| `resolv_server_ip` | 解析当前节点服务器域名，写入 `ss_basic_server_ip`。 |
| `ss_arg` | 生成 SS/SSR 命令参数片段。 |
| `create_ss_json` | 生成 SS/SSR 的 JSON 配置。 |
| `get_type_name` | 将协议类型编号转成人类可读名称。 |
| `get_dns_name` | 将 DNS 模式编号转成人类可读名称。 |
| `start_sslocal` | 启动 `ss-local` 或 `rss-local`，提供内部 Socks5。 |
| `start_dns` | 根据 DNS 模式启动 dns2socks、chinadns、cdns、smartdns、DoH、Xray DNS 等。 |
| `detect_domain` | 判断域名是否命中白名单或黑名单。 |
| `create_dnsmasq_conf` | 生成 dnsmasq 分流配置和黑白名单配置。 |
| `start_haveged` | 启动 haveged。 |
| `auto_start` | 向 `nat-start`、`wan-start` 注入自动启动命令。 |
| `start_kcp` | 启动 KCP 客户端。 |
| `start_speeder` | 启动 UDP speeder/udp2raw 加速链路。 |
| `start_ss_redir` | 启动 SS/SSR 透明代理 redir 进程。 |
| `start_koolgame` | 启动 koolgame 和相关 UDP 组件。 |
| `get_function_switch` | 读取 Xray/Trojan 相关开关字段。 |
| `get_ws_header` | 生成 WebSocket header。 |
| `get_h2_host` | 生成 HTTP/2 host 配置。 |
| `get_path` | 规范化 Xray path。 |
| `get_fingerprint` | 规范化 TLS/Reality fingerprint。 |
| `resolve_node_ip4json` | 对自定义 JSON 内节点域名解析 IP。 |
| `create_fragment_config` | 生成 Xray TLS fragment 配置。 |
| `create_v2ray_json` | 生成 Vmess/Vless/Xray JSON，处理自定义 JSON 和聚合 JSON。 |
| `create_trojan_json` | 生成 Trojan over Xray JSON。 |
| `create_trojango_json` | 生成 Trojan-Go JSON。 |
| `create_naive_json` | 生成 NaiveProxy JSON。 |
| `create_ss2022_json` | 生成 SS2022 over Xray JSON。 |
| `create_hy2_json` | 生成 Hysteria2 JSON。 |
| `start_xray_core` | 通用 Xray 启动封装。 |
| `start_xray` | 启动 Vmess/Vless/Xray。 |
| `start_trojan` | 启动 Trojan。 |
| `start_trojango` | 启动 Trojan-Go。 |
| `start_naiveproxy` | 启动 NaiveProxy。 |
| `start_hy2` | 启动 Hysteria2。 |
| `start_ss2022` | 启动 SS2022。 |
| `write_cron_job` | 写规则更新和节点更新定时任务。 |
| `kill_cron_job` | 删除规则更新和节点更新定时任务。 |
| `load_tproxy` | 加载 TPROXY 所需模块和策略路由。 |
| `flush_nat` | 清空插件创建的 iptables、ipset、策略路由和 mangle 链。 |
| `create_ipset` | 创建并加载 chnroute、gfwlist、白名单、黑名单 ipset。 |
| `add_white_black_ip` | 把用户黑白名单 IP 加入 ipset。 |
| `get_action_chain` | 将代理模式映射为 NAT 跳转链。 |
| `get_mode_name` | 将代理模式编号转成人类可读名称。 |
| `factor` | 生成日志中的对齐/分隔输出。 |
| `get_jump_mode` | 根据当前模式得出 iptables 跳转行为。 |
| `lan_acess_control` | 根据 ACL 对局域网客户端应用不同代理模式。 |
| `apply_nat_rules` | 创建并应用主 NAT/TPROXY 规则。 |
| `dns_hijack_control` | 开启 LAN DNS 劫持。 |
| `chromecast` | Chromecast 设备特殊 DNS/NAT 处理。 |
| `restart_dnsmasq` | 重启 dnsmasq 服务。 |
| `load_module` | 加载 iptables/ipset 所需内核模块。 |
| `write_numbers` | 写入运行统计或状态数值。 |
| `set_ulimit` | 设置进程文件句柄限制。 |
| `remove_ss_reboot_job` | 删除重启后恢复任务。 |
| `set_ss_reboot_job` | 添加重启后恢复任务。 |
| `remove_ss_trigger_job` | 删除网络触发任务。 |
| `set_ss_trigger_job` | 添加网络触发任务。 |
| `load_nat` | 加载透明代理 NAT 和 TPROXY 规则。 |
| `ss_post_start` | 启动后处理，更新状态和日志。 |
| `ss_pre_stop` | 停止前处理，常用于备份和状态标记。 |
| `detect` | 检测运行前环境、配置、二进制和模式。 |
| `mount_dnsmasq` | 准备 dnsmasq 配置挂载。 |
| `umount_dnsmasq` | 卸载 dnsmasq 配置挂载。 |
| `mount_dnsmasq_now` | 立即挂载或链接 dnsmasq 配置。 |
| `umount_dnsmasq_now` | 立即卸载 dnsmasq 配置。 |
| `disable_ss` | 完整停止插件并清理环境。 |
| `apply_ss` | 完整应用插件配置，是 restart 的核心流程。 |
| `get_status` | 输出当前运行状态。 |

### 8.2 `shadowsocks/scripts/ss_online_update.sh`

| 函数 | 作用 |
| --- | --- |
| `set_lock` | 订阅更新加锁。 |
| `unset_lock` | 释放订阅更新锁。 |
| `detect` | 检测固件和依赖。 |
| `prepare` | 收集本地节点、订阅节点和索引信息。 |
| `base64decode_link` | 对订阅链接内容进行 base64 补齐和解码。 |
| `urldecode` | URL 解码。 |
| `dbus_update_if_diff` | 仅在值变化时写 dbus，减少无意义写入。 |
| `add_ss_servers` | 新增 SS 节点。 |
| `get_ss_config` | 解析 `ss://` 链接。 |
| `update_ss_config` | 更新已有 SS 节点。 |
| `add_ssr_servers` | 新增 SSR 节点。 |
| `get_ssr_config` | 解析 `ssr://` 链接。 |
| `update_ssr_config` | 更新已有 SSR 节点。 |
| `get_vmess_config` | 解析 `vmess://` 链接。 |
| `add_vmess_servers` | 新增 Vmess 节点。 |
| `update_vmess_config` | 更新已有 Vmess 节点。 |
| `get_trojan_config` | 解析 `trojan://` 链接。 |
| `add_trojan_servers` | 新增 Trojan 节点。 |
| `update_trojan_config` | 更新已有 Trojan 节点。 |
| `get_hysteria2_config` | 解析 `hysteria2://` 链接。 |
| `add_hysteria2_servers` | 新增 Hysteria2 节点。 |
| `update_hysteria2_config` | 更新已有 Hysteria2 节点。 |
| `get_vless_config` | 解析 `vless://` 链接。 |
| `add_vless_servers` | 新增 Vless 节点。 |
| `update_vless_config` | 更新已有 Vless 节点。 |
| `get_trojan_go_config` | 解析 `trojan-go://` 链接。 |
| `add_trojan_go_servers` | 新增 Trojan-Go 节点。 |
| `update_trojan_go_config` | 更新已有 Trojan-Go 节点。 |
| `del_none_exist` | 删除订阅源已不存在的本地订阅节点。 |
| `remove_node_gap` | 压缩节点编号空洞。 |
| `open_socks_23456` | 订阅下载时临时打开内部 Socks5。 |
| `get_type_name` | 协议编号转名称。 |
| `get_oneline_rule_now` | 拉取或生成当前订阅的一行规则内容。 |
| `start_update` | 订阅更新主流程。 |
| `add` | 手动导入链接主流程。 |
| `remove_all` | 删除全部节点。 |
| `remove_online` | 删除订阅节点。 |
| `change_cru` | 写入或删除订阅定时任务。 |

### 8.3 `shadowsocks/scripts/ss_webtest.sh`

| 函数 | 作用 |
| --- | --- |
| `speed_test_curl` | 使用 curl/httping 测试代理连通和速度。 |
| `get_function_switch` | 读取节点功能开关。 |
| `get_ws_header` | 生成 WS header。 |
| `get_h2_host` | 生成 h2 host。 |
| `get_path` | 规范化 path。 |
| `get_fingerprint` | 规范化 Xray fingerprint。 |
| `get_tgfingerprint` | 规范化 Trojan-Go fingerprint。 |
| `create_v2ray_json` | 为测速生成临时 Xray JSON。 |
| `create_trojan_json` | 为测速生成临时 Trojan JSON。 |
| `create_trojango_json` | 为测速生成临时 Trojan-Go JSON。 |
| `create_naive_json` | 为测速生成临时 Naive JSON。 |
| `create_hy2_json` | 为测速生成临时 Hysteria2 JSON。 |
| `create_ss2022_json` | 为测速生成临时 SS2022 JSON。 |
| `start_webtest` | 按节点类型启动临时客户端并执行测速。 |

### 8.4 其他 Shell 脚本函数

| 文件 | 函数 | 作用 |
| --- | --- | --- |
| `scripts/ss_conf_restore.sh` | `remove_first` | 恢复配置时删除首个匹配项。 |
| `scripts/ss_lb_config.sh` | `write_haproxy_cfg` | 生成 haproxy 配置。 |
| `scripts/ss_lb_config.sh` | `start_haproxy` | 启动 haproxy 负载均衡。 |
| `scripts/ss_rule_update.sh` | `start_update` | 规则更新主流程。 |
| `scripts/ss_rule_update.sh` | `change_cru` | 规则更新定时任务维护。 |
| `scripts/ss_udp_status.sh` | `check_status` | 检查 UDP 加速进程和链路状态。 |
| `scripts/ss_reboot_job.sh` | `remove_ss_reboot_job` | 删除重启恢复任务。 |
| `scripts/ss_reboot_job.sh` | `set_ss_reboot_job` | 添加重启恢复任务。 |
| `scripts/ss_reboot_job.sh` | `remove_ss_trigger_job` | 删除网络触发任务。 |
| `scripts/ss_reboot_job.sh` | `set_ss_trigger_job` | 添加网络触发任务。 |
| `scripts/ss_reboot_job.sh` | `get_server_resolver` | 选择域名解析 DNS。 |
| `scripts/ss_reboot_job.sh` | `check_ip` | 检查节点 IP 变化并触发重启。 |
| `scripts/ss_v2ray_xray.sh` | `get_bin_version` | 读取本地核心版本。 |
| `scripts/ss_v2ray_xray.sh` | `get_latest_version` | 从主更新源读取最新版本。 |
| `scripts/ss_v2ray_xray.sh` | `get_latest_version_backup` | 从备用逻辑读取最新版本。 |
| `scripts/ss_v2ray_xray.sh` | `update_now` | 下载核心二进制和校验文件。 |
| `scripts/ss_v2ray_xray.sh` | `check_md5sum` | 校验下载文件 md5。 |
| `scripts/ss_v2ray_xray.sh` | `install_binary` | 安装新二进制。 |
| `scripts/ss_v2ray_xray.sh` | `move_binary` | 移动新二进制到目标路径。 |
| `scripts/ss_v2ray_xray.sh` | `start_v2ray` | 更新后重启相关核心。 |
| `scripts/ss_v2ray_xray.sh` | `close_in_five` | 日志窗口倒计时关闭提示。 |
| `scripts/ss_socks5.sh` | `kill_socks5` | 停止独立 Socks5。 |
| `scripts/ss_socks5.sh` | `start_socks5` | 启动独立 Socks5。 |
| `scripts/ss_proc_status.sh` | `get_mode_name` | 代理模式编号转名称。 |
| `scripts/ss_proc_status.sh` | `get_dns_name` | DNS 模式编号转名称。 |
| `scripts/ss_proc_status.sh` | `get_action_chain` | NAT 链编号转名称。 |
| `scripts/ss_proc_status.sh` | `echo_version` | 输出规则和二进制版本。 |
| `scripts/ss_proc_status.sh` | `check_status` | 检查进程、iptables、DNS 和版本状态。 |
| `scripts/ss_update.sh` | `install_ss` | 安装下载好的插件包。 |
| `scripts/ss_update.sh` | `update_ss` | 普通插件包更新流程。 |
| `scripts/ss_update.sh` | `update_ss2` | 强制或备用更新流程。 |
| `ss/postscripts/change_my_name.sh` | `start_v2ray` | postscript 示例：启动 xray。 |
| `ss/postscripts/change_my_name.sh` | `stop_v2ray` | postscript 示例：停止 xray。 |
| `ss/rules/dnsmasq.postconf` | `perpare` | dnsmasq postconf 准备逻辑。 |
| `ss/rules/dnsmasq.postconf` | `use_chn_plan` | 使用国内 DNS 分流方案。 |
| `ss/rules/dnsmasq.postconf` | `use_for_plan` | 使用国外 DNS 分流方案。 |

### 8.5 `webs/Main_Ss_Content.asp`

| 函数 | 作用 |
| --- | --- |
| `init` | 页面初始化。 |
| `hide_elem` | 初始隐藏不需要展示的 DOM。 |
| `detect` | 检测浏览器或运行环境。 |
| `hook_event` | 注册页面事件。 |
| `pop_111` | 弹出说明层。 |
| `pop_help` | 弹出帮助层。 |
| `pop_node_add` | 弹出节点添加层。 |
| `pop_tip` | 弹出提示层。 |
| `isJSON` | 判断字符串是否为 JSON。 |
| `save` | 收集主页面配置并提交后端应用。 |
| `push_data` | 将对象写入 `db_ss` 提交数组。 |
| `decode_show` | base64 解码后回显。 |
| `update_ss_ui` | 根据配置更新 UI 控件。 |
| `verifyFields` | 校验表单字段。 |
| `update_visibility` | 根据协议和模式显示或隐藏表单项。 |
| `generate_lan_list` | 生成 LAN 客户端列表。 |
| `ssconf_node2obj` | 将指定节点 dbus 字段转换成 JS 对象。 |
| `protocol_change_on` | 协议切换时启用相关字段。 |
| `protocol_change_off` | 协议切换时禁用相关字段。 |
| `trojan_change_off` | Trojan 类型切换时禁用不适用字段。 |
| `network_change_off` | 传输网络切换时禁用不适用字段。 |
| `flow_change_off` | XTLS flow 切换处理。 |
| `reality_change_off` | Reality 相关字段切换处理。 |
| `ss_node_sel` | 当前节点选择变化处理。 |
| `getAllConfigs` | 从后端读取全部 `ss` 配置。 |
| `loadBasicOptions` | 加载基础选项到 UI。 |
| `loadAllConfigs` | 加载所有配置和节点列表。 |
| `updateSs_node_listView` | 刷新节点列表视图。 |
| `Add_profile` | 打开新增节点面板。 |
| `cancel_add_rule` | 关闭新增节点面板。 |
| `tabclickhandler` | 节点类型 tab 切换。 |
| `add_ss_node_conf` | 新增节点配置。 |
| `refresh_table` | 重建节点表格。 |
| `refresh_html` | 生成节点表格 HTML。 |
| `apply_Running_node` | 应用当前正在选中的节点。 |
| `remove_running_node` | 删除当前运行节点相关状态。 |
| `apply_this_ss_node` | 将某个节点设为当前节点并应用。 |
| `remove_conf_table` | 删除节点。 |
| `edit_conf_table` | 打开节点编辑面板。 |
| `edit_ss_node_conf` | 保存编辑后的节点。 |
| `download_SS_node` | 导出节点备份。 |
| `upload_ss_backup` | 上传节点备份。 |
| `upload_ok` | 上传完成回调。 |
| `restore_ss_conf` | 恢复节点备份。 |
| `remove_SS_node` | 批量删除节点。 |
| `ping_test` | 发起 ping 测试。 |
| `remove_ping` | 清空 ping 结果。 |
| `web_test` | 发起 Web 测速。 |
| `remove_test` | 清空 Web 测速结果。 |
| `refresh_ss_node_list_ping` | 轮询并刷新 ping 结果。 |
| `refresh_ss_node_list_webtest` | 轮询并刷新 Web 测速结果。 |
| `updatelist` | 发起规则或列表更新。 |
| `version_show` | 展示版本信息。 |
| `get_ss_status_data` | 获取主状态数据。 |
| `get_udp_status` | 获取 UDP 状态。 |
| `write_udp_status` | 写入 UDP 状态展示。 |
| `update_ss` | 发起插件包更新。 |
| `toggle_func` | 开关类功能切换。 |
| `ss_node_info_return` | 节点信息弹窗返回处理。 |
| `get_log` | 获取日志。 |
| `get_realtime_log` | 实时轮询日志。 |
| `count_down_close` | 倒计时关闭日志窗口。 |
| `update_ping_method` | 更新 ping 测试方式。 |
| `reload_Soft_Center` | 刷新软件中心。 |
| `getACLConfigs` | 读取 ACL 配置。 |
| `addTr` | ACL 表格新增行。 |
| `delTr` | ACL 表格删除行。 |
| `refresh_acl_table` | 刷新 ACL 表格。 |
| `set_mode_1` | 设置第一类默认模式。 |
| `set_mode_2` | 设置第二类默认模式。 |
| `set_default_port` | 设置 ACL 默认端口。 |
| `refresh_acl_html` | 生成 ACL 表格 HTML。 |
| `setClientIP` | 从客户端列表回填 IP/MAC/name。 |
| `pullLANIPList` | 拉取 LAN 客户端列表。 |
| `hideClients_Block` | 隐藏客户端选择块。 |
| `get_proc_status` | 发起进程状态检查。 |
| `close_proc_status` | 关闭进程状态窗口。 |
| `now_get_status` | 立即刷新状态。 |
| `write_proc_status` | 写入状态展示。 |
| `get_online_nodes` | 订阅节点操作入口。 |
| `save_online_nodes` | 保存订阅配置并发起后端动作。 |
| `ss_binary_update` | 发起核心二进制更新。 |
| `status_onchange` | 订阅或状态开关变化处理。 |
| `inter_pre_onchange` | 界面前置选项变化处理。 |
| `set_cron` | 设置规则或订阅定时任务。 |

### 8.6 其他 Web/JS 函数

| 文件 | 函数 | 作用 |
| --- | --- | --- |
| `webs/Main_Ss_LoadBlance.asp` | `init` | 负载均衡页面初始化。 |
| `webs/Main_Ss_LoadBlance.asp` | `save` | 保存负载均衡配置。 |
| `webs/Main_Ss_LoadBlance.asp` | `push_data` | 写提交对象。 |
| `webs/Main_Ss_LoadBlance.asp` | `conf2obj` | dbus 配置转对象。 |
| `webs/Main_Ss_LoadBlance.asp` | `getAllConfigs` | 读取全部配置。 |
| `webs/Main_Ss_LoadBlance.asp` | `load_lb_node_nu` | 读取已选负载均衡节点。 |
| `webs/Main_Ss_LoadBlance.asp` | `loadBasicOptions` | 加载基础配置。 |
| `webs/Main_Ss_LoadBlance.asp` | `add_new_lb_node` | 添加负载均衡节点。 |
| `webs/Main_Ss_LoadBlance.asp` | `del_lb_node` | 删除负载均衡节点。 |
| `webs/Main_Ss_LoadBlance.asp` | `addTr` | 新增表格行。 |
| `webs/Main_Ss_LoadBlance.asp` | `delTr` | 删除表格行。 |
| `webs/Main_Ss_LoadBlance.asp` | `delTr_onstart` | 启动时清理表格行。 |
| `webs/Main_Ss_LoadBlance.asp` | `refresh_table` | 刷新表格数据。 |
| `webs/Main_Ss_LoadBlance.asp` | `refresh_html` | 生成表格 HTML。 |
| `webs/Main_Ss_LoadBlance.asp` | `loadAllConfigs` | 加载所有配置。 |
| `webs/Main_Ss_LoadBlance.asp` | `generate_link` | 生成负载均衡本地节点配置。 |
| `webs/Main_Ss_LoadBlance.asp` | `update_visibility` | 控制 UI 显隐。 |
| `webs/Main_Ss_LoadBlance.asp` | `get_realtime_log` | 轮询日志。 |
| `webs/Main_Ss_LoadBlance.asp` | `count_down_close` | 倒计时关闭日志窗口。 |
| `webs/Main_SsLocal_Content.asp` | `init` | Socks5 页面初始化。 |
| `webs/Main_SsLocal_Content.asp` | `save` | 保存 Socks5 配置。 |
| `webs/Main_SsLocal_Content.asp` | `push_data` | 写提交对象。 |
| `webs/Main_SsLocal_Content.asp` | `conf2obj` | dbus 配置转对象。 |
| `webs/Main_SsLocal_Content.asp` | `update_visibility` | 控制 UI 显隐。 |
| `webs/Main_SsLocal_Content.asp` | `get_realtime_log` | 轮询日志。 |
| `webs/Main_SsLocal_Content.asp` | `count_down_close` | 倒计时关闭日志窗口。 |
| `webs/Main_SsXray_Aggregate.asp` | `E` | DOM 获取辅助。 |
| `webs/Main_SsXray_Aggregate.asp` | `init` | 聚合页面初始化。 |
| `webs/Main_SsXray_Aggregate.asp` | `base64DecodeMaybe` | 尝试 base64 解码字段。 |
| `webs/Main_SsXray_Aggregate.asp` | `isDefined` | 判空辅助。 |
| `webs/Main_SsXray_Aggregate.asp` | `getAllConfigs` | 读取所有节点配置。 |
| `webs/Main_SsXray_Aggregate.asp` | `protoCell` | 生成协议单元格。 |
| `webs/Main_SsXray_Aggregate.asp` | `getSelectedNodes` | 获取选中节点。 |
| `webs/Main_SsXray_Aggregate.asp` | `refreshSelectedCount` | 刷新选中数量。 |
| `webs/Main_SsXray_Aggregate.asp` | `buildNodeTable` | 构建节点表格。 |
| `webs/Main_SsXray_Aggregate.asp` | `buildOutboundsFromSelection` | 从选中节点生成 Xray outbounds。 |
| `webs/Main_SsXray_Aggregate.asp` | `gen_json` | 生成聚合 JSON。 |
| `webs/Main_SsXray_Aggregate.asp` | `copy_json` | 复制 JSON。 |
| `webs/Main_SsXray_Aggregate.asp` | `select_all` | 全选或取消全选。 |
| `res/ss-menu.js` | `E` | DOM 获取辅助。 |
| `res/ss-menu.js` | `autoTextarea` | textarea 自动高度。 |
| `res/ss-menu.js` | `browser_compatibility1` | 浏览器兼容检测。 |
| `res/ss-menu.js` | `menu_hook` | 菜单挂载。 |
| `res/ss-menu.js` | `done_validating` | 校验完成回调。 |
| `res/ss-menu.js` | `showSSLoadingBar` | 显示加载条。 |
| `res/ss-menu.js` | `LoadingSSProgress` | 更新加载条进度。 |
| `res/ss-menu.js` | `hideSSLoadingBar` | 隐藏加载条。 |
| `res/ss-menu.js` | `openssHint` | 打开提示说明。 |
| `res/ss-menu.js` | `showDropdownClientList` | 显示 LAN 客户端下拉列表。 |
| `res/ss-menu.js` | `do_js_beautify`、`pack_js`、`js_beautify` | 内置 JS 格式化/压缩工具。 |

## 9. 重要生成文件

| 文件 | 生成者 | 作用 |
| --- | --- | --- |
| `/koolshare/ss/ss.json` | `create_ss_json` | SS/SSR 主配置。 |
| `/koolshare/ss/v2ray.json` | `create_v2ray_json`、`create_trojan_json`、`create_ss2022_json` | Xray 配置。 |
| `/koolshare/ss/trojan-go.json` | `create_trojango_json` | Trojan-Go 配置。 |
| `/koolshare/ss/naive.json` | `create_naive_json` | NaiveProxy 配置。 |
| `/koolshare/ss/hysteria.json` | `create_hy2_json` | Hysteria2 配置。 |
| `/koolshare/configs/haproxy.cfg` | `ss_lb_config.sh` | haproxy 负载均衡配置。 |
| `/tmp/custom.conf` | `create_dnsmasq_conf` | dnsmasq 主分流配置。 |
| `/tmp/wblist.conf` | `create_dnsmasq_conf` | 黑白名单域名配置。 |
| `/tmp/sscdn.conf` | `create_dnsmasq_conf` | CDN 域名配置。 |
| `/tmp/ss_proc_status.log` | `ss_proc_status.sh` | 进程状态。 |
| `/tmp/ss_udp_status.log` | `ss_udp_status.sh` | UDP 状态。 |
| `/tmp/upload/ss_log.txt` | 多个脚本 | Web 实时日志。 |
| `/tmp/ssr_subscribe_file.txt` | `ss_online_update.sh` | 下载后的订阅原始内容。 |
| `/tmp/all_localservers` | `ss_online_update.sh` | 本地节点索引。 |
| `/tmp/all_onlineservers` | `ss_online_update.sh` | 订阅节点索引。 |

## 10. 魔改优先入口

### 10.1 修改运行行为

优先看：

- `shadowsocks/ss/ssconfig.sh`
- `apply_ss`
- `disable_ss`
- `create_dnsmasq_conf`
- `start_dns`
- `apply_nat_rules`
- 各协议 `create_*_json` 和 `start_*`

典型改法：

- 新增协议：加 UI 字段、dbus 字段、订阅解析、`create_*_json`、`start_*`、状态检测、测速临时配置。
- 修改分流：改 `create_dnsmasq_conf`、`create_ipset`、`apply_nat_rules`、`lan_acess_control`。
- 修改 DNS：改 `start_dns` 和 `ss/rules/dnsmasq.postconf`。
- 修改启动顺序：改 `apply_ss`，但必须同时考虑 stop 清理。

### 10.2 修改 UI 和字段

优先看：

- `webs/Main_Ss_Content.asp`
- `save`
- `verifyFields`
- `update_visibility`
- `ssconf_node2obj`
- `add_ss_node_conf`
- `edit_ss_node_conf`
- `refresh_html`

注意：新增字段至少要同步四个方向：

```text
UI 控件
-> save() 写入 dbus
-> 节点 add/edit/import/restore 处理
-> ssconfig.sh eval dbus 后读取并使用
```

如果字段也来自订阅，还要改 `ss_online_update.sh` 的对应 `get_*_config`、`add_*_servers`、`update_*_config`。

### 10.3 修改订阅格式或节点解析

优先看：

- `scripts/ss_online_update.sh`
- `get_ss_config`
- `get_ssr_config`
- `get_vmess_config`
- `get_vless_config`
- `get_trojan_config`
- `get_trojan_go_config`
- `get_hysteria2_config`
- `add_*_servers`
- `update_*_config`
- `del_none_exist`
- `remove_node_gap`

节点匹配通常靠 server、port、password、protocol、group 等字段。改匹配逻辑要小心避免把同名不同配置误判成同一节点。

### 10.4 修改测速和状态

优先看：

- `scripts/ss_webtest.sh`
- `scripts/ss_ping.sh`
- `scripts/ss_proc_status.sh`
- `scripts/ss_udp_status.sh`
- `webs/Main_Ss_Content.asp` 中测速和状态函数

新协议如果不接入测速，UI 可能显示空白或失败；如果不接入状态脚本，Web 状态会误报未运行。

### 10.5 修改更新源

优先看：

- `scripts/ss_update.sh`
- `scripts/ss_v2ray_xray.sh`
- `scripts/ss_rule_update.sh`
- `ss/rules/version`
- `380_armv5/*/latest.txt`

更新脚本有代理下载逻辑，和 `ss_basic_online_links_goss` 相关。替换源时要保留 md5 校验格式或同步修改校验逻辑。

## 11. 代码风险和已见疑点

这些不是全部问题，只是阅读中比较值得优先核对的位置。

| 文件 | 疑点 |
| --- | --- |
| `scripts/ss_reboot_job.sh` | `check_ip` 内似乎使用了 `$get_server_resolver`，看起来像少了命令替换 `$(get_server_resolver)`。 |
| `ss/ssconfig.sh` | `kill_process` 的 pdu 分支设置了 `pdu_process`，但 kill 时变量名疑似使用 `$pdu`，可能无法杀掉目标进程。 |
| `webs/Main_Ss_LoadBlance.asp` | 多处 key 拼接疑似缺下划线，例如 `ssconf_basic_ss_v2ray_plugin" + cur_lb_node`。 |
| `webs/Main_Ss_Content.asp` | vmess import 分支中 `ssconf_basic_fragment" + node_sel` 疑似缺下划线。 |
| `scripts/ss_update.sh` | 非代理分支的 `curlxx` alias 后面似乎混入 `380_armv5/simple-obfs/curl` 字符串，需要实际运行前核对。 |
| `scripts/ss_webtest.sh` | 存在 `[ "$array17" == "xray" ]` 判断，但阅读片段中未见 `array17` 初始化，可能影响 v2ray 测试命令。 |
| `scripts/ss_proc_status.sh` | 有 `[ "$ss_dnschina" == "13" ]`，变量名疑似应为 `ss_dns_china`。 |
| 多个文件 | Web 页面和 Shell 都依赖 dbus key 名，任何字段重命名都必须全链路同步。 |
| 多个文件 | 脚本大量使用 BusyBox/Merlin 环境命令、`[[ ]]`、`let`、`local`、`source`、`pidof`、`cru`，移植到普通 Linux 需要兼容层。 |
| 多个文件 | 现有源码在 Windows PowerShell 中可能显示乱码，修改原文件时不要无意中改变编码。 |

## 12. 建议改造顺序

1. 先固定目标协议或目标行为，列出新增/修改的 dbus 字段。
2. 在 `Main_Ss_Content.asp` 完成 UI 字段的新增、校验、保存、编辑、回显。
3. 在 `ss_online_update.sh` 接入订阅解析和节点新增/更新。
4. 在 `ssconfig.sh` 接入配置生成、进程启动、进程清理、状态变量。
5. 在 `ss_webtest.sh` 接入临时测速客户端。
6. 在 `ss_proc_status.sh` 接入运行状态展示。
7. 如果影响透明代理，补 `apply_nat_rules`、`create_ipset`、`create_dnsmasq_conf`。
8. 如果影响更新，补 `ss_v2ray_xray.sh` 或 `ss_update.sh`。

对这个插件来说，“字段链路一致性”比单点代码正确更重要。一个新字段通常会穿过 Web、dbus、订阅、运行脚本、测速、状态、备份恢复多个层面。

## 13. iptables 状态和 Merlin 网络处理流程

本插件对 Merlin 网络栈的接管点主要有三个：

1. `iptables/ipset/ip rule`：透明代理、DNS 劫持、UDP TPROXY。
2. `dnsmasq`：域名分流、国内/国外 DNS 策略、gfwlist/cdn/custom 配置。
3. `/jffs/scripts/*`：Merlin 固件事件脚本，用于 WAN 启动、防火墙重建、dnsmasq postconf。

### 13.1 插件使用的 iptables 表

| 表 | 使用情况 | 主要作用 |
| --- | --- | --- |
| `nat` | 核心使用 | TCP 透明代理、路由器自身 TCP 代理、DNS 劫持 DNAT。 |
| `mangle` | 游戏模式、UDP 同步、TPROXY 时使用 | UDP 透明代理，配合 `fwmark 0x07` 和路由表 `310`。 |
| `filter` | 插件基本不直接改 | Merlin 防火墙自身使用，插件状态检查不以它为核心。 |
| `raw` | 未见核心改写 | 不参与当前插件主流程。 |

### 13.2 启动后应存在的 nat 表状态

启动成功后，`nat` 表通常会出现这些链和入口。

| 链 | 入口或规则 | 作用 |
| --- | --- | --- |
| `PREROUTING` | `-p tcp -j SHADOWSOCKS` | LAN 客户端 TCP 进入透明代理总链。 |
| `PREROUTING` | `-i brX -p udp --dport 53 -j SHADOWSOCKS_DNS_X` | 开启 DNS 劫持时，把 LAN DNS 请求导到路由器 dnsmasq。 |
| `OUTPUT` | `-p tcp -m set --match-set router dst -j REDIRECT --to-ports 3333` | 路由器自身访问指定目标时走本机透明代理。 |
| `OUTPUT` | `-p tcp -m mark --mark "$ip_prefix_hex" -j SHADOWSOCKS_EXT` | 配合 ACL mark，把路由器自身或特殊来源转入扩展链。 |
| `SHADOWSOCKS` | `white_list RETURN`，ACL，默认模式跳转 | LAN TCP 主分流链。 |
| `SHADOWSOCKS_EXT` | `white_list RETURN`，mark ACL，默认模式跳转 | 扩展链，多用于本机或 ACL 标记流量。 |
| `SHADOWSOCKS_GLO` | `REDIRECT --to-ports 3333` | 全局模式，所有 TCP 走代理。 |
| `SHADOWSOCKS_GFW` | `black_list`、`gfwlist` 命中后 REDIRECT | GFWList 模式。 |
| `SHADOWSOCKS_CHN` | `black_list` 命中或 `! chnroute` 后 REDIRECT | 大陆白名单模式，非中国 IP 走代理。 |
| `SHADOWSOCKS_GAM` | 类似 `CHN` | 游戏模式的 TCP 部分。 |
| `SHADOWSOCKS_HOM` | `black_list` 或 `chnroute` 命中后 REDIRECT | 回国模式，中国 IP 走代理。 |
| `SHADOWSOCKS_DNS_X` | `DNAT --to <brX_ip>:53` | 每个 bridge 一个 DNS 劫持链。 |

核心代码在 `ss/ssconfig.sh::apply_nat_rules`：

```sh
iptables -t nat -N SHADOWSOCKS
iptables -t nat -N SHADOWSOCKS_EXT
iptables -t nat -A SHADOWSOCKS -p tcp -m set --match-set white_list dst -j RETURN
iptables -t nat -N SHADOWSOCKS_GLO
iptables -t nat -A SHADOWSOCKS_GLO -p tcp -j REDIRECT --to-ports 3333
iptables -t nat -N SHADOWSOCKS_GFW
iptables -t nat -A SHADOWSOCKS_GFW -p tcp -m set --match-set black_list dst -j REDIRECT --to-ports 3333
iptables -t nat -A SHADOWSOCKS_GFW -p tcp -m set --match-set gfwlist dst -j REDIRECT --to-ports 3333
iptables -t nat -N SHADOWSOCKS_CHN
iptables -t nat -A SHADOWSOCKS_CHN -p tcp -m set ! --match-set chnroute dst -j REDIRECT --to-ports 3333
iptables -t nat -I PREROUTING "$INSET_NU" -p tcp -j SHADOWSOCKS
```

这里 `REDIRECT --to-ports 3333` 是透明代理关键点。无论后端是 SS、SSR、Xray、Trojan、Naive 还是 Hysteria，iptables 层只负责把流量导到本地透明代理端口，真正协议处理由前面启动的核心进程完成。

### 13.3 启动后应存在的 mangle/TPROXY 状态

只有满足 `mangle=1` 时才会建立 UDP 透明代理链。常见触发来源是游戏模式、UDP 同步或 UDP 加速相关设置。

| 对象 | 状态 | 作用 |
| --- | --- | --- |
| 内核模块 | `nf_tproxy_core`、`xt_TPROXY`、`xt_socket`、`xt_comment` | TPROXY 必需模块。 |
| `ip rule` | `fwmark 0x07 lookup 310` | 带 mark 的 UDP 包查表 `310`。 |
| `ip route` | `local 0.0.0.0/0 dev lo table 310` | 把 TPROXY 流量回送本机 lo，由本地代理接收。 |
| `mangle PREROUTING` | `-p udp -j SHADOWSOCKS` | LAN UDP 进入插件分流链。 |
| `mangle SHADOWSOCKS` | `white_list RETURN`、ACL、默认跳转 | UDP 主分流链。 |
| `mangle <mode-chain>` | `TPROXY --on-port 3333 --tproxy-mark 0x07` | 命中后交给本地透明代理端口。 |
| `mangle QOSO0` | `-m mark --mark "$ip_prefix_hex" -j RETURN` | QOS 开启时避免和插件 mark 冲突。 |

核心代码：

```sh
[ "$mangle" == "1" ] && load_tproxy
[ "$mangle" == "1" ] && ip rule add fwmark 0x07 table 310
[ "$mangle" == "1" ] && ip route add local 0.0.0.0/0 dev lo table 310
[ "$mangle" == "1" ] && iptables -t mangle -N SHADOWSOCKS
[ "$mangle" == "1" ] && iptables -t mangle -A SHADOWSOCKS -p udp -m set --match-set white_list dst -j RETURN
[ "$mangle" == "1" ] && iptables -t mangle -N $(get_action_chain $ss_basic_mode)
[ "$mangle" == "1" ] && iptables -t mangle -A $(get_action_chain $ss_basic_mode) -p udp -m set --match-set black_list dst -j TPROXY --on-port 3333 --tproxy-mark 0x07
[ "$mangle" == "1" ] && iptables -t mangle -A PREROUTING -p udp -j SHADOWSOCKS
```

TPROXY 和 TCP REDIRECT 的差异：

- TCP 用 `nat REDIRECT`，目标被改成本机 `3333`。
- UDP 用 `mangle TPROXY`，配合 `fwmark` 和本地路由表让包被本地 socket 接收，尽量保留原目标地址。

### 13.4 ipset 状态

`create_ipset` 会创建并刷新以下集合：

| ipset | 来源 | 作用 |
| --- | --- | --- |
| `chnroute` | `/koolshare/ss/rules/chnroute.txt` | 中国大陆 IP 段，用于大陆白名单、回国、游戏模式判断。 |
| `white_list` | 用户白名单、LAN、本地网段 | 命中后绕过代理。 |
| `black_list` | 用户黑名单、强制代理 IP/域名解析结果 | 命中后强制走代理。 |
| `gfwlist` | `gfwlist.conf` 通过 dnsmasq `ipset=` 动态灌入 | GFWList 域名解析结果，命中后走代理。 |
| `router` | 路由器自身需要代理的目标 | 用于 `nat OUTPUT`。 |

核心代码：

```sh
ipset -! create white_list nethash && ipset flush white_list
ipset -! create black_list nethash && ipset flush black_list
ipset -! create gfwlist nethash && ipset flush gfwlist
ipset -! create router nethash && ipset flush router
ipset -! create chnroute nethash && ipset flush chnroute
sed -e "s/^/add chnroute &/g" /koolshare/ss/rules/chnroute.txt | awk '{print $0} END{print "COMMIT"}' | ipset -R
```

域名类 ipset 不是一次性静态导入。`gfwlist.conf`、`cdn.conf`、`wblist.conf` 由 dnsmasq 在域名解析时把返回 IP 写入 ipset，所以 DNS 是否正常直接影响透明代理命中。

### 13.5 DNS 劫持状态

当 `ss_basic_dns_hijack=1` 时，插件按 `br0`、`br1` 等 bridge 创建独立 DNS 链：

```sh
iptables -t nat -N SHADOWSOCKS_DNS_${VLAN_INDEX}
iptables -t nat -F SHADOWSOCKS_DNS_${VLAN_INDEX}
iptables -t nat -A SHADOWSOCKS_DNS_${VLAN_INDEX} -p udp -j DNAT --to ${dest_ipaddr}:53
iptables -t nat -I PREROUTING "${INSET_NU_DNS}" -i br${VLAN_INDEX} -p udp -m udp --dport 53 -j SHADOWSOCKS_DNS_${VLAN_INDEX}
```

流量路径：

```text
LAN client DNS UDP/53
-> nat PREROUTING
-> SHADOWSOCKS_DNS_<bridge>
-> DNAT 到 brX 网关 IP:53
-> dnsmasq
-> 根据 dnsmasq.postconf 和 /jffs/configs/dnsmasq.d/*.conf 选择国内 DNS 或 127.0.0.1#7913
-> DNS 结果可能灌入 gfwlist/black_list/white_list/cdn 相关 ipset
```

### 13.6 flush/stop 后的清理状态

`flush_nat` 是清理 iptables/ipset 的核心函数。停止插件或重启前都会调用。

应被清理的内容：

| 对象 | 清理动作 |
| --- | --- |
| `nat PREROUTING` 中包含 `SHADOWSOCKS` 的规则 | 按行号倒序删除。 |
| `nat` 自定义链 | `SHADOWSOCKS`、`SHADOWSOCKS_EXT`、`SHADOWSOCKS_GFW`、`SHADOWSOCKS_CHN`、`SHADOWSOCKS_GAM`、`SHADOWSOCKS_GLO`、`SHADOWSOCKS_HOM`。 |
| `mangle PREROUTING` 中包含 `SHADOWSOCKS` 的规则 | 按行号倒序删除。 |
| `mangle` 自定义链 | `SHADOWSOCKS` 和当前模式链。 |
| `nat OUTPUT` | 删除 router set 到 `3333` 的规则，并执行 `iptables -t nat -F OUTPUT`。 |
| DNS 劫持链 | 删除 `SHADOWSOCKS_DNS_X` 入口，再 flush/delete 链。 |
| QOS 例外 | 删除 `QOSO0` 中插件 mark 的 RETURN。 |
| ipset | flush/delete `chnroute`、`white_list`、`black_list`、`gfwlist`、`router`。 |
| 策略路由 | 删除 `lookup 310` 的 `ip rule` 和 `table 310` 的 local route。 |

核心代码：

```sh
nat_indexs=`iptables -nvL PREROUTING -t nat |sed 1,2d | sed -n '/SHADOWSOCKS/='|sort -r`
iptables -t nat -F SHADOWSOCKS >/dev/null 2>&1 && iptables -t nat -X SHADOWSOCKS >/dev/null 2>&1
iptables -t mangle -F SHADOWSOCKS >/dev/null 2>&1 && iptables -t mangle -X SHADOWSOCKS >/dev/null 2>&1
ipset -F chnroute >/dev/null 2>&1 && ipset -X chnroute >/dev/null 2>&1
ipset -F white_list >/dev/null 2>&1 && ipset -X white_list >/dev/null 2>&1
ipset -F black_list >/dev/null 2>&1 && ipset -X black_list >/dev/null 2>&1
ipset -F gfwlist >/dev/null 2>&1 && ipset -X gfwlist >/dev/null 2>&1
ip route del local 0.0.0.0/0 dev lo table 310 >/dev/null 2>&1
```

注意：`flush_nat` 里有 `iptables -t nat -F OUTPUT`。这会清空整个 nat OUTPUT 链，不只是插件自己的规则。若后续魔改环境里还有其它插件也依赖 nat OUTPUT，需要重点评估冲突。

### 13.7 路由器上建议巡检命令

在 Merlin 路由器上排查时，优先看这些状态：

```sh
dbus get ss_basic_enable
dbus get ss_basic_mode
dbus get ss_acl_default_mode
nvram get jffs2_scripts
iptables -t nat -nvL PREROUTING --line-numbers
iptables -t nat -nvL OUTPUT --line-numbers
iptables -t nat -nvL SHADOWSOCKS --line-numbers
iptables -t nat -nvL SHADOWSOCKS_EXT --line-numbers
iptables -t mangle -nvL PREROUTING --line-numbers
iptables -t mangle -nvL SHADOWSOCKS --line-numbers
iptables -t nat -S | grep SHADOWSOCKS
iptables -t mangle -S | grep SHADOWSOCKS
ipset list chnroute | head
ipset list gfwlist | head
ipset list white_list
ipset list black_list
ip rule show | grep 310
ip route show table 310
ps | grep -E "ss-redir|rss-redir|xray|trojan-go|naive|hysteria|dns2socks|chinadns|smartdns|cdns" | grep -v grep
```

判断方式：

| 现象 | 含义 |
| --- | --- |
| `nat PREROUTING` 没有 `SHADOWSOCKS` | 透明代理入口未加载，重点看 `load_nat`、`apply_nat_rules`、`nat-start`。 |
| `nat SHADOWSOCKS` 存在但计数不涨 | LAN 流量没有进链，可能入口顺序、接口、上游防火墙或硬件加速影响。 |
| `gfwlist` ipset 为空 | DNS 解析没有把域名结果灌入 ipset，重点看 dnsmasq 配置和 gfwlist.conf。 |
| `mangle SHADOWSOCKS` 不存在 | 当前模式没有启用 TPROXY/UDP；如果预期启用，查 `mangle` 变量和 UDP 设置。 |
| `ip rule show` 没有 `lookup 310` | UDP TPROXY 不完整。 |
| `SHADOWSOCKS_DNS_X` 不存在 | DNS 劫持未启用或 bridge 未识别。 |
| 停止后仍有 `SHADOWSOCKS` 链 | `flush_nat` 没执行完或链被其它进程引用。 |

### 13.8 Merlin 固件网络事件流程

Merlin 网络生命周期中，插件关心以下事件：

```text
系统启动
-> Merlin 初始化 nvram、LAN bridge、WAN、dnsmasq、防火墙
-> WAN ready 后触发 /jffs/scripts/wan-start
-> 防火墙/NAT ready 或重建后触发 /jffs/scripts/nat-start
-> dnsmasq 重启时触发 /jffs/scripts/dnsmasq.postconf
```

插件通过 `auto_start` 注入：

```sh
mkdir -p /jffs/scripts

# nat-start：防火墙/NAT 重建后重新加载插件规则
if [ ! -f /jffs/scripts/nat-start ]; then
    # 创建 nat-start
fi
sed -i '2a sh /koolshare/ss/ssconfig.sh' /jffs/scripts/nat-start

# wan-start：WAN 启动后从 Web 配置入口启动插件
if [ ! -f /jffs/scripts/wan-start ]; then
    # 创建 wan-start
fi
sed -i '2a sh /koolshare/scripts/ss_config.sh' /jffs/scripts/wan-start
```

对应行为：

| Merlin 事件 | 插件入口 | 行为 |
| --- | --- | --- |
| Web UI 保存 | `/koolshare/scripts/ss_config.sh` | 根据 `ss_basic_enable` 调 `ssconfig.sh restart` 或 `stop`。 |
| WAN 启动 | `/jffs/scripts/wan-start` -> `ss_config.sh` | WAN ready 后按 dbus 配置启动插件。 |
| NAT/防火墙重建 | `/jffs/scripts/nat-start` -> `ssconfig.sh` | 默认 action 分支，如果已启用则执行完整 `apply_ss`。 |
| dnsmasq 重启 | `/jffs/scripts/dnsmasq.postconf` | 修改 `/etc/dnsmasq.conf` 的上游 DNS 和缓存策略。 |
| 插件停止 | `ssconfig.sh stop` | 停进程、清规则、清 dnsmasq 链接、恢复环境。 |

`ssconfig.sh` 底部的默认 action 很关键。`nat-start` 注入的是 `sh /koolshare/ss/ssconfig.sh`，没有显式参数，所以会走 `case $ACTION in *)`：

```sh
*)
    set_lock
    if [ "$ss_basic_enable" == "1" ];then
        set_ulimit
        apply_ss
        write_numbers
    fi
    unset_lock
    ;;
```

这意味着 Merlin 每次触发 `nat-start` 时，插件不是只补 iptables，而是走完整重启应用流程：停旧进程、清规则、重建 DNS、重启代理、重新加载 NAT。这能提高一致性，但也意味着防火墙频繁重建时会带来进程抖动。

### 13.9 Merlin dnsmasq 处理流程

插件对 dnsmasq 有两层处理：

1. `ssconfig.sh::create_dnsmasq_conf` 生成或链接 `/jffs/configs/dnsmasq.d/*.conf`。
2. `ss/rules/dnsmasq.postconf` 在 dnsmasq 服务重启时修改 `/etc/dnsmasq.conf`。

流程：

```text
create_dnsmasq_conf
-> 删除旧 /jffs/configs/dnsmasq.d/custom.conf、wblist.conf、cdn.conf、gfwlist.conf
-> 生成 /tmp/custom.conf、/tmp/wblist.conf、/tmp/sscdn.conf
-> ln -sf 到 /jffs/configs/dnsmasq.d/
-> ln -sf /koolshare/ss/rules/gfwlist.conf 到 /jffs/configs/dnsmasq.d/gfwlist.conf
-> ln -sf /koolshare/ss/rules/dnsmasq.postconf 到 /jffs/scripts/dnsmasq.postconf
-> service restart_dnsmasq
-> Merlin 调用 dnsmasq.postconf
-> postconf 根据当前模式选择国内优先或国外优先 DNS
```

`dnsmasq.postconf` 的核心分支：

```sh
if [ "$ss_basic_mode" == "1" -a -z "$chn_on" -a -z "$all_on" ] || [ "$ss_basic_mode" == "6" ];then
    perpare
    use_chn_plan
else
    perpare
    use_for_plan
fi
```

国内优先：

```sh
pc_insert "no-poll" "server=$CDN#53" "/etc/dnsmasq.conf"
pc_insert "no-poll" "no-resolv" "/etc/dnsmasq.conf"
```

国外优先：

```sh
pc_insert "no-poll" "server=127.0.0.1#7913" "/etc/dnsmasq.conf"
pc_insert "no-poll" "no-resolv" "/etc/dnsmasq.conf"
```

因此 DNS 的实际决策链是：

```text
客户端 DNS
-> dns_hijack_control 可强制导入路由器 dnsmasq
-> dnsmasq 读取 /etc/dnsmasq.conf 和 /jffs/configs/dnsmasq.d/*.conf
-> gfwlist/cdn/wblist/custom 规则决定域名走国内 DNS、国外 DNS 或写入 ipset
-> 国外 DNS 常落到 127.0.0.1:7913
-> 7913 后面由 dns2socks/chinadns/cdns/smartdns/https_dns_proxy/Xray DNS 等承接
```

### 13.10 Merlin 流量处理完整路径

#### LAN 客户端 TCP 访问外网

```text
client
-> br0/brX
-> Merlin nat PREROUTING
-> SHADOWSOCKS
-> white_list 命中则 RETURN
-> ACL 命中则按 ACL 模式跳转
-> 未命中则按 ss_acl_default_mode 跳转
-> SHADOWSOCKS_GFW/CHN/GAM/GLO/HOM
-> 命中代理条件则 REDIRECT 3333
-> 本机透明代理进程
-> 远端节点
```

#### LAN 客户端 UDP/game 流量

```text
client UDP
-> br0/brX
-> mangle PREROUTING
-> SHADOWSOCKS
-> white_list 或 ACL 判断
-> 模式链
-> TPROXY --on-port 3333 --tproxy-mark 0x07
-> ip rule fwmark 0x07 table 310
-> local route dev lo
-> 本机透明代理进程
```

#### LAN 客户端 DNS

```text
client DNS UDP/53
-> nat PREROUTING
-> SHADOWSOCKS_DNS_brX
-> DNAT brX_ip:53
-> dnsmasq
-> /jffs/configs/dnsmasq.d/gfwlist.conf、cdn.conf、wblist.conf、custom.conf
-> 国内 DNS 或国外 DNS helper
-> 解析结果写入 ipset
-> 后续 TCP/UDP 流量按 ipset 命中分流
```

#### 路由器自身访问外网

```text
router local process
-> nat OUTPUT
-> router ipset 命中则 REDIRECT 3333
-> mark 命中则 SHADOWSOCKS_EXT
-> 本机透明代理进程
```

### 13.11 Merlin 相关魔改风险点

| 风险 | 说明 |
| --- | --- |
| `nat-start` 会触发完整 `apply_ss` | 防火墙重建频繁时会导致代理进程和 DNS 进程反复重启。若只想补 NAT，需要拆一个轻量 reload_nat 分支。 |
| `iptables -t nat -F OUTPUT` 清空面大 | 可能影响其它依赖 nat OUTPUT 的插件。建议魔改时改成只删除插件插入的规则。 |
| `dnsmasq.postconf` 依赖 JFFS custom scripts | `nvram get jffs2_scripts` 必须为 `1`，否则 DNS postconf 和自启都会异常。 |
| ipset 依赖 DNS 解析侧写入 | 只看 iptables 链存在不代表分流生效，必须同时看 dnsmasq 和 ipset 是否有数据。 |
| TPROXY 依赖内核模块和策略路由 | 缺 `xt_TPROXY`、`xt_socket` 或 table `310` 会导致 UDP 透明代理失败。 |
| 硬件加速可能绕过软件链 | Merlin/Asus NAT acceleration 在某些场景会让流量不经过预期软件路径，排查时要留意计数器是否增长。 |
| 多 bridge 场景要看 `brX` | 访客网络、VLAN、多 LAN bridge 会生成多个 `SHADOWSOCKS_DNS_X`，ACL 和 DNS 劫持都要按 bridge 验证。 |

## 14. 第二轮深审补充

这一轮补充的目标是弥补前文偏“主流程”的问题。前文已经覆盖 `ssconfig.sh`、DNS、NAT、订阅、测速、状态等主线，但对以下内容不够细：

- 短脚本入口和 `case/action` 分支没有完整拉平。
- Web UI 到 `SystemCmd` 的调用矩阵不够明确。
- 配置备份、恢复、删除、迁移、打包这些维护链路写得太少。
- 二进制依赖和运行时文件生命周期没有独立梳理。
- 代码风险更多集中在主控，外围脚本的明显问题没有完全列出。
- 分析边界没有说清楚：本仓库包含预编译二进制，当前文档没有反编译这些二进制。

### 14.1 文件规模和重点权重

脚本和 UI 的行数能反映维护权重：

| 文件 | 行数 | 维护权重 |
| --- | ---: | --- |
| `webs/Main_Ss_Content.asp` | 5848 | 最高。所有主页面交互、节点编辑、订阅、状态、更新入口都在这里。 |
| `res/ss-menu.js` | 3263 | 高。UI 公共组件、加载条、Base64、beautify、客户端列表。 |
| `ss/ssconfig.sh` | 3093 | 最高。运行期核心。 |
| `scripts/ss_online_update.sh` | 2003 | 高。订阅解析和节点数据库维护。 |
| `scripts/ss_webtest.sh` | 789 | 中高。协议临时配置生成，和主运行配置高度重复。 |
| `webs/Main_Ss_LoadBlance.asp` | 663 | 中。haproxy 负载均衡 UI。 |
| `webs/Main_SsXray_Aggregate.asp` | 493 | 中。Xray 聚合 JSON 生成。 |
| `scripts/ss_proc_status.sh` | 337 | 中。状态巡检和版本展示。 |
| `webs/Main_SsLocal_Content.asp` | 308 | 中。独立 Socks5 UI。 |
| `scripts/ss_v2ray_xray.sh` | 223 | 中。核心二进制更新。 |
| `scripts/ss_lb_config.sh` | 212 | 中。haproxy 配置生成。 |
| `scripts/ss_rule_update.sh` | 202 | 中。规则更新。 |
| `scripts/ss_reboot_job.sh` | 151 | 中。定时重启和节点 IP 变更触发。 |
| `scripts/ss_update.sh` | 81 | 中。插件包更新。 |
| `scripts/ss_fix_conf.sh` | 67 | 中。旧版配置迁移。 |
| `scripts/ss_socks5.sh` | 67 | 中。独立 Socks5 服务。 |
| `scripts/ss_pack.sh` | 43 | 低。打包脚本。 |
| `scripts/ss_conf_restore.sh` | 32 | 中。配置恢复。 |
| `scripts/ss_conf_remove.sh` | 20 | 中。配置删除。 |

当前仓库文件类型大致为：

| 类型 | 数量 | 说明 |
| --- | ---: | --- |
| 无扩展名 | 141 | 主要是预编译二进制和历史二进制。 |
| `.txt` | 96 | 版本、md5、规则、latest 信息。 |
| `.sh` | 26 | 运行和维护脚本。 |
| `.asp` | 4 | 软件中心页面。 |
| `.js` | 3 | UI 公共 JS 和 layer。 |
| `.htm` | 2 | 状态片段。 |
| `.acl` | 2 | SS-libev ACL。 |
| `.conf` | 2 | dnsmasq/smartdns 模板。 |

### 14.2 Web UI 到后端脚本调用矩阵

Koolshare 软件中心的基本调用方式是：

```text
Web JS 组装 dbus object
-> 设置 SystemCmd、action_mode、current_page
-> POST /applydb.cgi?p=<prefix>
-> 后端执行 /koolshare/scripts/<SystemCmd>
-> 脚本通过 dbus export 读取刚写入的 key
```

主页面入口：

| Web 函数 | `SystemCmd` | 写入前缀 | 后端动作 |
| --- | --- | --- | --- |
| `save()` | `ss_config.sh` | `ss`、`ssconf_basic`、`ss_acl` | 主配置保存后启动/停止插件。 |
| `restore_ss_conf()` | `ss_conf_restore.sh` | `ss` | 从 `/tmp/ss_conf_backup.txt` 恢复配置。 |
| `remove_SS_node()` | `ss_conf_remove.sh` | `ss` | 删除大部分 `ss*` 配置并停止插件。 |
| `ping_test()` | `ss_ping.sh` | `ss` | 写 `ssconf_basic_ping_<n>`。 |
| `remove_ping()` | `ss_ping_remove.sh` | `ss` | 删除 ping 结果。 |
| `web_test()` | `ss_webtest.sh` | `ss` | 写 `ssconf_basic_webtest_<n>`。 |
| `remove_test()` | `ss_webtest_remove.sh` | `ss` | 删除 Web 测速结果。 |
| `updatelist(action)` | `ss_rule_update.sh` | `ss` | 规则更新或保存规则更新计划。 |
| `get_udp_status()` | `ss_udp_status.sh` | `apply.cgi` query | 写 `/tmp/ss_udp_status.log`。 |
| `now_get_status()` | `ss_proc_status.sh` | `apply.cgi` query | 写 `/tmp/ss_proc_status.log`。 |
| `update_ss()` | `ss_update.sh` | `ss` | 在线更新整个插件包。 |
| `save_online_nodes(action)` | `ss_online_update.sh` | `ss` | 保存订阅设置、订阅、导入或删除节点。 |
| `ss_binary_update(2/3/4)` | `ss_v2ray_xray.sh` | `ss` | 更新 `xray`、`naive`、`hysteria`。 |
| `set_cron(action)` | `ss_reboot_job.sh` | `ss` | 写定时重启或 IP 变更触发任务。 |

子页面入口：

| 页面 | `SystemCmd` | 作用 |
| --- | --- | --- |
| `Main_Ss_LoadBlance.asp` | `ss_lb_config.sh` | 保存 `ss_lb_*` 并生成/启动 haproxy。 |
| `Main_SsLocal_Content.asp` | `ss_socks5.sh` | 保存 `ss_local_*` 并启动/停止独立 Socks5。 |
| `Main_SsXray_Aggregate.asp` | 无直接应用脚本 | 读取配置生成 Xray 聚合 JSON，主要供复制回主页面自定义 JSON。 |

### 14.3 后端脚本 action/case 总表

| 脚本 | action 来源 | 分支 | 行为 |
| --- | --- | --- | --- |
| `ss/ssconfig.sh` | `$ACTION` 或无参数 | `start` | 如果 `ss_basic_enable=1`，执行 `apply_ss`。 |
| `ss/ssconfig.sh` | `$ACTION` | `stop` | 执行 `disable_ss`。 |
| `ss/ssconfig.sh` | `$ACTION` | `restart` | 强制 `apply_ss`。 |
| `ss/ssconfig.sh` | `$ACTION` | `flush_nat` | 只清 iptables/ipset/策略路由。 |
| `ss/ssconfig.sh` | 默认 | `*` | 无参数时，如果启用则完整 `apply_ss`，这正是 `nat-start` 触发路径。 |
| `ss_online_update.sh` | `ss_online_action` | `0` | 删除所有节点。 |
| `ss_online_update.sh` | `ss_online_action` | `1` | 删除所有订阅节点并压缩编号。 |
| `ss_online_update.sh` | `ss_online_action` | `2` | 只保存订阅设置并维护 `cru`。 |
| `ss_online_update.sh` | `ss_online_action` | `3` | 下载订阅并更新节点。 |
| `ss_online_update.sh` | `ss_online_action` | `4` | 从手工链接导入节点。 |
| `ss_rule_update.sh` | `ss_basic_update_action` | `1` | 只保存规则更新计划。 |
| `ss_rule_update.sh` | `ss_basic_update_action` | `2` | 强制更新 gfwlist/chnroute/cdn，并维护计划。 |
| `ss_rule_update.sh` | 默认 | `*` | 自动更新入口。 |
| `ss_reboot_job.sh` | `$1` | `check_ip` | 检查节点 IP 变化，必要时重启 dnsmasq 或插件。 |
| `ss_reboot_job.sh` | `ss_basic_reboot_action` | `1` | 设置定时重启。 |
| `ss_reboot_job.sh` | `ss_basic_reboot_action` | `2` | 设置节点 IP 触发重启。 |
| `ss_socks5.sh` | `$1` | `start` | init.d 启动入口，启用时启动独立 Socks5。 |
| `ss_socks5.sh` | 默认 | `*` | Web 保存入口，按 `ss_local_enable` 启停。 |
| `ss_v2ray_xray.sh` | `ss_binary_update` | `2` | `core_bin=xray`。 |
| `ss_v2ray_xray.sh` | `ss_binary_update` | `3` | `core_bin=naive`。 |
| `ss_v2ray_xray.sh` | `ss_binary_update` | `4` | `core_bin=hysteria`。 |

### 14.4 短脚本维护链路

这些脚本虽然短，但对迁移、备份、卸载和后续魔改很关键。

| 脚本 | 细节 |
| --- | --- |
| `ss_config.sh` | Web 主保存后的最短入口。只判断 `ss_basic_enable`，然后调 `ssconfig.sh restart/stop`。 |
| `ss_conf_remove.sh` | `dbus list ss` 后删除大多数 `ss*` key，保留 webtest、ping、ssid、ssserver、state 等少数 key；随后写默认版本并停止插件。 |
| `ss_conf_restore.sh` | 把 `/tmp/ss_conf_backup.txt` 中以 `ss` 开头的行转换成临时 shell 脚本 `/tmp/ss_conf_backup_tmp.sh`，再执行 `dbus set` 恢复。 |
| `ss_fix_conf.sh` | 旧版配置迁移脚本，把 `use_rss`、koolgame、SS、SSR 旧字段迁移成新 `ssconf_basic_type_*` 风格。 |
| `ss_pack.sh` | 从 `/koolshare` 当前运行目录重新打包 `/tmp/shadowsocks.tar.gz`，会复制当前 bin、scripts、webs、res、ss 目录，并删除打包中的 `ss/*.json`。 |
| `ss_ping_remove.sh` | 删除 `ssconf_basic_ping*`。 |
| `ss_webtest_remove.sh` | 删除 `ssconf_basic_webtest*`。 |
| `ss_udp_status.sh` | 只输出 UDP 加速状态到 `/tmp/ss_udp_status.log`，以 `XU6J03M6` 作为 UI 轮询结束标记。 |
| `ss_proc_status.sh` | 输出版本、进程状态、DNS 状态、iptables 状态到 `/tmp/ss_proc_status.log`，同样用 `XU6J03M6` 作为完成标记。 |

配置恢复风险尤其高：`ss_conf_restore.sh` 会把备份内容拼成 shell 脚本执行。如果备份值中含特殊引号、反引号或命令替换字符，恢复脚本没有做严格转义。

### 14.5 安装、卸载、打包链路细节

安装 `install.sh`：

```text
检查 uname -m 必须为 armv7l
-> 检查 Merlin extendno 版本
-> 如果插件启用，先 stop
-> 备份 /koolshare/ss/postscripts/P*.sh
-> 如果 dnsmasq-fastlookup bind mount 存在，先 umount /usr/sbin/dnsmasq
-> 删除旧 /koolshare/ss、/koolshare/scripts/ss_*、Main_Ss*、res、bin
-> 从 /tmp/shadowsocks 复制 bin、ss、scripts、webs、res
-> chmod
-> 恢复 postscripts
-> 创建 rss-tunnel、base64、shuf、netstat、base64_decode、S99socks5.sh 软链
-> 写默认 dbus 和 softcenter metadata
-> 如果安装前启用则 restart
```

卸载 `uninstall.sh`：

```text
ssconfig.sh stop
-> ss_conf_remove.sh
-> 恢复 dnsmasq-fastlookup mount
-> 删除 /koolshare 里的插件文件和二进制
-> 删除启动脚本注入
-> 删除 softcenter metadata 和少量 ss_basic 版本 key
```

打包 `ss_pack.sh`：

```text
从当前 /koolshare 运行环境回收文件
-> 复制 scripts、webs、res、bin、ss
-> 删除打包内运行生成的 ss/*.json
-> 输出 /tmp/shadowsocks.tar.gz
```

这意味着仓库里的 `shadowsocks/` 是发布包源形态，`ss_pack.sh` 则反向从路由器运行环境生成发布包。魔改时如果在路由器上直接改了 `/koolshare`，要用 `ss_pack.sh` 回收；如果在仓库里改，走安装包覆盖。

### 14.6 二进制依赖矩阵

当前 `shadowsocks/bin` 包含：

```text
base64_encode, cdns, chinadns, chinadns1, chinadns-ng,
client_linux_arm5, dns2socks, dnsmasq, haproxy, haveged,
httping, https_dns_proxy, hysteria, jq, koolbox, koolgame,
naive, obfs-local, pdu, resolveip, rss-local, rss-redir,
smartdns, speederv1, speederv2, ss-local, ss-redir, ss-tunnel,
trojan-go, udp2raw, xray
```

按功能分组：

| 类别 | 二进制 |
| --- | --- |
| SS/SSR | `ss-redir`、`ss-local`、`ss-tunnel`、`rss-redir`、`rss-local`、`rss-tunnel` 软链。 |
| Xray/Trojan/Naive/Hysteria | `xray`、`trojan-go`、`naive`、`hysteria`。 |
| DNS | `cdns`、`chinadns`、`chinadns1`、`chinadns-ng`、`dns2socks`、`https_dns_proxy`、`smartdns`、`dnsmasq`。 |
| 加速/游戏 | `client_linux_arm5`、`speederv1`、`speederv2`、`udp2raw`、`koolgame`、`pdu`。 |
| 负载均衡 | `haproxy`。 |
| 工具 | `jq`、`koolbox`、`base64_encode`、`resolveip`、`httping`、`haveged`、`obfs-local`。 |

本仓库没有这些二进制的源码，当前分析只覆盖脚本如何调用它们，没有覆盖二进制内部行为。

### 14.7 模式和 DNS 映射的精确表

代理模式来自 `get_action_chain` / `get_mode_name`：

| mode | 名称 | NAT 链 |
| --- | --- | --- |
| `0` | 不通过 SS | `RETURN` |
| `1` | gfwlist 模式 | `SHADOWSOCKS_GFW` |
| `2` | 大陆白名单模式 | `SHADOWSOCKS_CHN` |
| `3` | 游戏模式 | `SHADOWSOCKS_GAM` |
| `5` | 全局模式 | `SHADOWSOCKS_GLO` |
| `6` | 回国模式 | `SHADOWSOCKS_HOM` |

国外 DNS 来自 `get_dns_name` / `start_dns`：

| `ss_foreign_dns` | 名称 | 进程/行为 |
| --- | --- | --- |
| `1` | `cdns` | `cdns -c /koolshare/ss/rules/cdns.json`。 |
| `2` | `chinadns2` | `chinadns`，带 chnroute 和 EDNS 相关参数。 |
| `3` 或空 | `dns2socks` | 启动 `ss-local/rss-local/xray socks` 后 `dns2socks 127.0.0.1:23456`。 |
| `4` | `ss-tunnel` / `ssr-tunnel` | SS/SSR 可用；Xray/Trojan 会被改回 `3`。 |
| `5` | `chinadns1` | `dns2socks` 作为上游，再启动 `chinadns1`。 |
| `6` | `https_dns_proxy` | DoH 到 `7913`。 |
| `7` | `v2ray dns` | 仅 Xray 类型下保留，否则改回 `3`。 |
| `8` | direct / koolgame 内置 | 回国模式允许；非回国模式会改回 `3`。 |
| `9` | SmartDNS | 由 `smartdns_template.conf` 生成 `/tmp/smartdns.conf`。 |
| `10` | ChinaDNS-NG | `dns2socks` + `chinadns-ng`，临时生成 `/tmp/gfwlist.txt`。 |

注意：代码里 `get_dns_name` 对 `8` 输出“koolgame内置”，但 `start_dns` 中 `8` 实际承担 direct/回国模式 DNS 语义。这是历史命名残留，魔改 UI 文案时要统一。

### 14.8 运行时文件生命周期

| 路径 | 生成/删除点 | 生命周期 |
| --- | --- | --- |
| `/tmp/syslog.log` | 多个 `SystemCmd` 追加或重定向 | Web 日志窗口读取。 |
| `/tmp/upload/ss_log.txt` | Web 上传/恢复相关 | 上传和恢复配置时使用。 |
| `/tmp/ss_conf_backup.txt` | Web 备份上传路径 | `ss_conf_restore.sh` 输入。 |
| `/tmp/ss_conf_backup_tmp.sh` | `ss_conf_restore.sh` | 临时可执行恢复脚本，恢复后删除。 |
| `/tmp/ssr_subscribe_file*.txt` | `ss_online_update.sh` | 订阅下载/解码/过滤临时文件。 |
| `/tmp/all_localservers` | `ss_online_update.sh` | 本地订阅节点索引。 |
| `/tmp/all_onlineservers` | `ss_online_update.sh` | 当前订阅远端节点索引。 |
| `/tmp/group_info.txt` | `ss_online_update.sh` | 本次订阅来源分组。 |
| `/tmp/v2ray_tmp.json` | `create_v2ray_json` | 自定义 JSON 聚合/改写中间文件。 |
| `/tmp/v2ray_log.log` | Xray JSON log 字段 | Xray 错误日志。 |
| `/tmp/trojan-go_log.log` | Trojan-Go JSON log 字段 | Trojan-Go 日志。 |
| `/tmp/smartdns.conf` | `start_dns` | 从模板按 DNS 模式生成。 |
| `/tmp/gfwlist.txt` | `chinadns-ng` 模式 | 从 `gfwlist.conf` 去掉 dnsmasq 语法后生成。 |
| `/tmp/custom.conf` | `create_dnsmasq_conf` | 自定义 dnsmasq 规则。 |
| `/tmp/wblist.conf` | `create_dnsmasq_conf` | 黑白名单域名和 router 自用域名。 |
| `/tmp/sscdn.conf` | `create_dnsmasq_conf` | CDN 国内域名规则。 |
| `/tmp/ss_proc_status.log` | `ss_proc_status.sh` | UI 状态窗口。 |
| `/tmp/ss_udp_status.log` | `ss_udp_status.sh` | UI UDP 状态。 |
| `/var/lock/koolss.lock` | `ssconfig.sh` | 主流程锁。 |
| `/tmp/online_update.lock` | `ss_online_update.sh` | 订阅流程锁。 |
| `/koolshare/ss/*.json` | 各 `create_*_json` | 实际代理核心配置。 |
| `/koolshare/configs/haproxy.cfg` | `ss_lb_config.sh` | haproxy 配置。 |

### 14.9 订阅解析深水区

`ss_online_update.sh` 的订阅解析是最容易被低估的部分。它支持：

```text
ss://
ssr://
vmess://
trojan://
vless://
trojan-go://
hysteria2://
```

主过程：

```text
ss_online_links base64 decode
-> 每行订阅 URL 可附带 ~~ 后缀作为自定义过滤条件
-> get_oneline_rule_now 下载订阅
-> base64decode_link + urldecode
-> 支持订阅内容内 MAX=<n>，随机抽取 n 个节点
-> grep 节点协议行
-> NODE_FORMAT="${line%%://*}"，把 '-' 替换成 '_'
-> 动态调用 get_${NODE_FORMAT}_config
-> 动态调用 update_${NODE_FORMAT}_config
-> 新节点走 add_${format}_servers
-> del_none_exist 删除远端已消失节点
-> remove_node_gap 压缩编号
```

这里有两个魔改重点：

- 动态函数调用意味着新增协议必须严格符合 `get_xxx_config`、`update_xxx_config`、`add_xxx_servers` 的命名模式。
- 订阅失败时 `DEL_SUBSCRIBE=1`，脚本不会删除“本次没出现”的订阅节点，避免网络异常误伤节点。这是一个保护逻辑，不要轻易删除。

### 14.10 负载均衡深水区

`ss_lb_config.sh` 不是简单选择多个节点，它会把节点写成 haproxy TCP upstream：

```text
listen shadowscoks_balance_load
    bind 0.0.0.0:$ss_lb_port
    mode tcp
    balance roundrobin
```

节点来源：

```text
dbus list ssconf_basic_use_lb_
-> 对每个 node 读取 server、port、weight、lbmode、use_kcp
-> use_kcp=1 时 upstream 指向 127.0.0.1:1091
-> heartbeat=1 时加 rise/fall/check/inter
-> lbmode=2 主用，lbmode=3 backup，其它 roundrobin
```

`ssconfig.sh::ss_pre_start` 会检测负载均衡是否启用。如果当前节点指向 `127.0.0.1:ss_lb_port`，会先启动 haproxy，再让主代理指向这个本地端口。

魔改风险：

- haproxy 配置里 `listen admin_status` 绑定 `0.0.0.0:1188`，认证使用路由器 Web 用户名和 `ss_lb_passwd`。
- 域名解析失败会拖慢 haproxy 启动，所以脚本里有“等待过久可能服务器域名解析失败”的提示。
- KCP 节点被特殊映射到 `127.0.0.1:1091`，不是远端端口。

### 14.11 独立 Socks5 深水区

`ss_socks5.sh` 和主透明代理不是一条链：

```text
ss_local_* dbus
-> ss_socks5.sh
-> kill 非 23456 的 ss-local
-> 按 ss_local_proxyport 启动 ss-local -b 0.0.0.0
```

它支持：

- `ss_local_v2ray_plugin=1` -> `--plugin v2ray-plugin`
- `ss_local_v2ray_plugin=2` 理应 -> `--plugin obfs-local`
- `ss_local_acl=1` -> `gfwlist.acl`
- `ss_local_acl=2` -> `chn.acl`

风险点：`start_socks5` 的 obfs 分支判断写的是 `ss_basic_ss_v2ray_plugin`，不是 `ss_local_v2ray_plugin`，这会让独立 Socks5 的插件选择受主配置污染。

### 14.12 更完整的风险清单

上一版风险点偏主控，这里补外围脚本。

| 文件 | 风险/疑点 |
| --- | --- |
| `uninstall.sh` | `auto_start` 写入的是 `/jffs/scripts/wan-start` 和 `/jffs/scripts/nat-start`，但卸载脚本删除的是 `/koolshare/scripts/wan-start`、`/koolshare/scripts/nat-start`，路径不一致，可能卸载后残留启动注入。 |
| `uninstall.sh` | 安装创建 `/koolshare/init.d/S99socks5.sh`，卸载只删除 `S89Socks5.sh`，可能残留 S99 软链。 |
| `install.sh` | 默认写的是 `ss_dns_foreign=1`，主运行脚本实际使用 `ss_foreign_dns`。这是历史字段残留或拼写错误，可能导致首次安装默认国外 DNS 不生效。 |
| `install.sh` | `chmod 755 /koolshare/bin/*` 会影响 `/koolshare/bin` 下所有文件，不只插件文件。 |
| `install.sh` / `uninstall.sh` | 删除资源里包含 `gfwlist.png`，仓库实际是 `gfw.png`，可能是历史残留。 |
| `ss_update.sh` | 常规网络分支的 `curlxx='curl --connect-timeout 8 -k 380_armv5/simple-obfs/curl'` 明显混入路径字符串，可能导致 curl 命令异常。 |
| `ss_fix_conf.sh` | `use_node` 分支里读取当前节点后却继续用循环变量 `$node`，应核对是否应为 `$use_node`。 |
| `ss_fix_conf.sh` | 最后一行把 `ssconf_basic_use_kcp_$node` 写进 `ss_basic_koolgame_udp`，字段目标疑似错误。 |
| `ss_socks5.sh` | obfs 分支判断 `ss_basic_ss_v2ray_plugin` 而非 `ss_local_v2ray_plugin`，独立 Socks5 配置可能受主节点影响。 |
| `ss_udp_status.sh` | 检查了 `ss_basic_udp2_boost_enable`，主字段应为 `ss_basic_udp2raw_boost_enable`。 |
| `ss_proc_status.sh` | `source helper.sh` 使用相对路径，取决于 apply.cgi 执行时 cwd；更稳应使用绝对路径。 |
| `ss_proc_status.sh` | `get_mode_name` 没有覆盖 `0` 和 `6`，状态展示可能空。 |
| `ss_proc_status.sh` | 使用 `ss_dnschina`，疑似应为 `ss_dns_china`。 |
| `ss_conf_restore.sh` | 把备份文件转成 shell 脚本执行，未对值做严格 shell escaping。 |
| `ss_online_update.sh` | 动态调用 `get_${NODE_FORMAT}_config`，如果协议名过滤不严，会放大维护风险；当前协议来自 grep 白名单，后续魔改不能放宽太多。 |
| `Main_Ss_Content.asp` | `ssconf_basic_fragment" + node_sel` 缺下划线，导致 vmess import 分支写错 key。 |
| `Main_Ss_Content.asp` | `params_input` 里有 `"$ss_basic_kcp_lserver"`，字段名前多了 `$`。 |
| `Main_SsXray_Aggregate.asp` | form hidden `current_page` 写成 `Main_Xray_Aggregate.asp`，和文件名 `Main_SsXray_Aggregate.asp` 不一致。 |
| `Main_Ss_LoadBlance.asp` | 多个 dbus key 拼接缺下划线，例如 `ssconf_basic_ss_v2ray_plugin" + cur_lb_node`。 |
| `ssconfig.sh` | `flush_nat` 清空整个 nat `OUTPUT` 链，可能误伤其它插件。 |
| `ssconfig.sh` | `kill_process` 的 `pdu` 变量名不一致，可能杀不掉 `pdu`。 |

### 14.13 当前分析边界

这份文档目前覆盖：

- Shell 脚本静态流程。
- ASP/JS UI 到 dbus 和后端脚本的调用链。
- dnsmasq、iptables、ipset、cru、Merlin 事件脚本的接入方式。
- 预编译二进制的调用参数、配置文件和端口。

这份文档没有覆盖：

- `bin/*` 预编译二进制内部逻辑，没有反编译或动态跟踪。
- 真实路由器上的运行输出，没有在 Merlin 设备上执行 `iptables`、`dbus`、`cru`、`service restart_dnsmasq`。
- 订阅解析所有边界样本，没有用真实订阅链接做回归集。
- Web UI 的浏览器实际点击流程，没有用浏览器自动化跑完整保存/订阅/测速。
- 历史 `380_armv5/*` 每个版本二进制的差异，只识别了它们作为更新源/归档。

如果后续要做“可改造级”的第三轮审计，建议按这四个方向继续：

1. 在真实 Merlin 或模拟环境里跑 `ssconfig.sh restart`，保存 `iptables-save`、`ipset save`、`ps`、`cru l`。
2. 用一组固定节点样本覆盖 `ss://`、`ssr://`、`vmess://`、`vless://`、`trojan://`、`trojan-go://`、`hysteria2://`，验证 `ss_online_update.sh` 写入的 dbus key。
3. 对每类协议运行 `ss_webtest.sh`，比对临时 JSON 和主 JSON 是否一致。
4. 在 UI 层跑新增/编辑/删除/应用/订阅/恢复/负载均衡/Socks5 的端到端操作，记录实际写入 key。
