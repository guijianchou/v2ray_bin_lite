# v2ray_bin-main 完整代码知识库 (Knowledge Codex)

## 项目概述

本项目是 koolshare 梅林 ARM380 固件平台的科学上网插件（fancyss_arm380 的增强版），运行于 armv7l 架构路由器。支持 SS/SSR/V2Ray(Xray)/Trojan/Trojan-Go/NaiveProxy/Hysteria2/SS2022 等多种代理协议，提供透明代理、DNS防污染、访问控制等功能。

### 支持平台
- 华硕: RT-AC56U, RT-AC68U, RT-AC66U-B1, RT-AC1900P, RT-AC87U, RT-AC88U, RT-AC3100, RT-AC3200, RT-AC5300
- 网件: R6300V2, R6400, R6900, R7000, R8000, R8500
- Linksys EA: EA6200, EA6400, EA6500v2, EA6700, EA6900
- 华为: ws880

### 核心特性（相比原版新增）
- Xray 完全替代 V2Ray（支持 vmess/vless/trojan/ss2022）
- VLESS + XTLS Vision + Reality
- 多节点 Xray 聚合负载均衡（xagg 策略）
- NaiveProxy / Hysteria2
- 混合节点订阅（ss:// vless:// trojan:// trojan-go:// hysteria2://）
- SmartDNS / ChinaDNS-NG
- TLS Fragment + Noise 反审查

---

## 目录结构

```
v2ray_bin-main/
├── .github/workflows/          # CI: hysteria 自动更新
├── 380_armv5/                  # 预编译二进制仓库（按版本存放）
│   ├── curl/                   # curl 二进制
│   ├── hysteria/               # Hysteria2 各版本
│   ├── naive/                  # NaiveProxy 各版本
│   ├── shadowsocks-libev/      # ss-libev 各版本
│   ├── simple-obfs/            # obfs-local/obfs-server
│   ├── trojan-go/              # Trojan-Go 各版本
│   ├── v2ray/                  # V2Ray 各版本（已停更）
│   ├── xray/                   # Xray 各版本（主力）
│   ├── v2ray-plugin            # v2ray-plugin 二进制
│   └── upx-ucl/                # UPX 压缩工具
├── shadowsocks/                # ★ 插件主体（安装包内容）
│   ├── bin/                    # 所有运行时二进制
│   ├── res/                    # Web UI 资源（CSS/JS/图片）
│   ├── scripts/                # 辅助脚本
│   ├── ss/                     # 核心配置与规则
│   ├── webs/                   # ASP 页面（路由器 Web UI）
│   ├── install.sh              # 安装脚本
│   └── uninstall.sh            # 卸载脚本
└── README.md
```

---

## 核心文件详解

### 1. `shadowsocks/ss/ssconfig.sh` — 主控脚本（3093行）

这是整个插件的核心引擎，负责启动/停止/重启所有代理服务。

#### 全局变量定义（行1-36）

| 变量 | 用途 |
|------|------|
| `CONFIG_FILE` | SS/SSR/koolgame 的 JSON 配置 `/koolshare/ss/ss.json` |
| `V2RAY_CONFIG_FILE` | Xray 最终配置 `/koolshare/ss/v2ray.json` |
| `V2RAY_CONFIG_FILE_TMP` | Xray 临时配置 `/tmp/v2ray_tmp.json` |
| `TROJANGO_CONFIG_FILE` | Trojan-Go NAT 配置 `/koolshare/ss/trojango.json` |
| `TROJANGO2_CONFIG_FILE` | Trojan-Go SOCKS5 配置 `/koolshare/ss/trojango2.json` |
| `NAIVE_CONFIG_FILE` | NaiveProxy NAT 配置 `/koolshare/ss/naive.json` |
| `NAIVE2_CONFIG_FILE` | NaiveProxy SOCKS5 配置 `/koolshare/ss/naive2.json` |
| `HY2_CONFIG_FILE` | Hysteria2 配置 `/koolshare/ss/hysteria.json` |
| `DNSF_PORT=7913` | 国外DNS解析端口 |
| `DNSC_PORT=53` | 国内DNS端口（SmartDNS时为5335） |
| `ss_basic_type` | 节点类型: 0=SS, 1=SSR, 2=koolgame, 3=V2Ray/Xray, 4=Trojan系, 5=Naive |
| `ss_basic_mode` | 代理模式: 1=gfwlist, 2=大陆白名单, 3=游戏, 5=全局, 6=回国 |
| `mangle` | 是否需要 UDP 转发（游戏模式/UDP同步时为1） |

#### 节点类型判断逻辑（行38-61）
- `ss_basic_method` 为 2022-blake3-* 或 none → SS2022 模式，强制 `ss_basic_type=3`
- 兼容旧版本：通过检测 `ss_basic_rss_protocol`/`ss_basic_koolgame_udp`/`ss_basic_v2ray_use_json` 推断类型

---

#### 函数清单与调用关系

##### 基础工具函数

| 函数 | 行号 | 功能 |
|------|------|------|
| `get_lan_cidr()` | 64 | 计算 LAN CIDR（如 192.168.1.0/24） |
| `get_wan0_cidr()` | 73 | 计算 WAN CIDR |
| `get_server_resolver()` | 88 | 根据用户选择返回DNS解析服务器IP |
| `set_lock()` | 113 | 获取文件锁（防止并发） |
| `unset_lock()` | 118 | 释放文件锁 |
| `close_in_five()` | 123 | 5秒倒计时后关闭插件（错误处理） |
| `detect_domain()` | 715 | 检测字符串是否为合法域名格式 |
| `get_type_name()` | 437 | 类型ID→名称映射 |
| `get_dns_name()` | 460 | DNS方案ID→名称映射 |
| `get_function_switch()` | 1233 | 1→"true", 其他→"false" |
| `get_ws_header()` | 1244 | 生成 WebSocket Host header JSON |
| `get_h2_host()` | 1252 | 生成 H2 host 数组 JSON |
| `get_path()` | 1260 | 包装路径为 JSON 字符串 |
| `get_fingerprint()` | 1268 | 包装 fingerprint 为 JSON 字符串 |
| `get_action_chain()` | 2458 | 模式ID→iptables链名映射 |
| `get_mode_name()` | 2481 | 模式ID→中文名映射 |
| `get_jump_mode()` | 2512 | 模式0用-j(RETURN)，其他用-g(goto) |
| `factor()` | 2504 | 条件参数拼接辅助 |

##### 停止/清理函数

| 函数 | 行号 | 功能 |
|------|------|------|
| `restore_conf()` | 146 | 删除所有 dnsmasq 相关配置文件 |
| `kill_process()` | 163 | 杀死所有代理相关进程（xray/trojan-go/ss-redir/naive/hysteria/rss-redir/ss-local/rss-local/ss-tunnel/chinadns/cdns/dns2socks/smartdns/koolgame/pdu/kcptun/haproxy/speeder/udp2raw/https_dns_proxy/haveged） |
| `flush_nat()` | 2340 | 清除所有 iptables 规则和 ipset |
| `kill_cron_job()` | 2299 | 删除定时更新任务 |
| `disable_ss()` | 2929 | 完整关闭流程：kill→restore→umount→restart_dnsmasq→flush_nat |

##### 启动前准备函数

| 函数 | 行号 | 功能 |
|------|------|------|
| `ss_pre_start()` | 303 | 检测负载均衡配置，必要时启动 haproxy |
| `resolv_server_ip()` | 324 | 解析服务器域名为IP（nslookup→resolveip fallback） |
| `detect()` | 2840 | 检测 jffs2_scripts 是否开启、清理自定义DNS |
| `load_module()` | 2706 | 加载 xt_set 内核模块 |
| `set_ulimit()` | 2725 | 设置 ulimit -n 16384 和 overcommit_memory |

##### 配置生成函数

| 函数 | 行号 | 功能 |
|------|------|------|
| `ss_arg()` | 367 | 构建 v2ray-plugin/obfs-local 参数 |
| `create_ss_json()` | 378 | 生成 SS/SSR/koolgame 的 JSON 配置 |
| `create_v2ray_json()` | 1387 | 生成 Xray 配置（vmess/vless，支持 tcp/kcp/ws/h2/grpc + tls/reality） |
| `create_fragment_config()` | 1348 | 生成 TLS Fragment + Noise 反审查出站配置 |
| `create_trojan_json()` | 1858 | 生成 Trojan（via Xray）配置 |
| `create_trojango_json()` | 1943 | 生成 Trojan-Go 配置（NAT + SOCKS5 双配置） |
| `create_naive_json()` | 2024 | 生成 NaiveProxy 配置（redir + socks 双配置） |
| `create_ss2022_json()` | 2051 | 生成 SS2022（via Xray shadowsocks 协议）配置 |
| `create_hy2_json()` | 2127 | 生成 Hysteria2 配置 |
| `resolve_node_ip4json()` | 1276 | 从用户自定义 JSON 中提取并解析服务器地址 |

##### 进程启动函数

| 函数 | 行号 | 功能 |
|------|------|------|
| `start_haveged()` | 949 | 启动 haveged 提供系统熵 |
| `start_sslocal()` | 499 | 启动 ss-local/rss-local/trojan-go/naive 提供 SOCKS5:23456 |
| `start_ss_redir()` | 1098 | 启动 ss-redir/rss-redir 透明代理（含 KCP/UDPspeeder 联动） |
| `start_koolgame()` | 1205 | 启动 koolgame + pdu |
| `start_xray_core()` | 2157 | 路由到 start_xray/start_trojan/start_ss2022 |
| `start_xray()` | 2167 | 启动 xray 进程 |
| `start_trojan()` | 2186 | 启动 trojan（实际用 xray） |
| `start_trojango()` | 2205 | 启动 trojan-go 进程 |
| `start_naiveproxy()` | 2223 | 启动 naive 进程 |
| `start_hy2()` | 2241 | 启动 hysteria 进程 |
| `start_ss2022()` | 2260 | 启动 SS2022（实际用 xray） |
| `start_kcp()` | 991 | 启动 kcptun (client_linux_arm5) |
| `start_speeder()` | 1024 | 启动 UDPspeeder + UDP2raw（支持串联） |
| `start_dns()` | 519 | 启动 DNS 解析方案（见下方DNS章节） |

##### DNS 相关函数

| 函数 | 行号 | 功能 |
|------|------|------|
| `start_dns()` | 519 | DNS方案总调度（根据 ss_foreign_dns 选择） |
| `create_dnsmasq_conf()` | 725 | 生成 dnsmasq 配置（cdn.conf/gfwlist.conf/wblist.conf） |
| `restart_dnsmasq()` | 2700 | 重启 dnsmasq 服务 |
| `mount_dnsmasq()` | 2862 | 用 dnsmasq-fastlookup 替换原版 |
| `umount_dnsmasq()` | 2868 | 恢复原版 dnsmasq |
| `mount_dnsmasq_now()` | 2874 | 根据策略决定是否替换 dnsmasq |
| `umount_dnsmasq_now()` | 2909 | 关闭时的 dnsmasq 恢复策略 |

##### NAT/iptables 函数

| 函数 | 行号 | 功能 |
|------|------|------|
| `load_tproxy()` | 2310 | 加载 TPROXY 内核模块（UDP转发） |
| `create_ipset()` | 2409 | 创建 ipset 集合（white_list/black_list/gfwlist/router/chnroute） |
| `add_white_black_ip()` | 2419 | 填充黑白名单 IP |
| `lan_acess_control()` | 2523 | 应用局域网访问控制规则（ACL） |
| `apply_nat_rules()` | 2574 | 写入完整 iptables 规则 |
| `dns_hijack_control()` | 2662 | DNS 劫持规则（防 DNS 泄露） |
| `chromecast()` | 2676 | Chromecast DNS 劫持 |
| `load_nat()` | 2792 | NAT 加载总入口（等待 nat ready → create_ipset → apply_nat → chromecast） |

##### 定时任务函数

| 函数 | 行号 | 功能 |
|------|------|------|
| `write_cron_job()` | 2279 | 添加规则更新 + 节点订阅定时任务 |
| `auto_start()` | 954 | 写入 nat-start/wan-start 自启动脚本 |
| `set_ss_reboot_job()` | 2738 | 设置插件定时重启 |
| `remove_ss_reboot_job()` | 2730 | 删除插件定时重启 |
| `set_ss_trigger_job()` | 2778 | 设置 IP 变化触发重启 |
| `remove_ss_trigger_job()` | 2770 | 删除触发重启任务 |
| `write_numbers()` | 2716 | 写入规则版本号到 nvram |

##### 钩子函数

| 函数 | 行号 | 功能 |
|------|------|------|
| `ss_pre_stop()` | 2826 | 关闭前执行 postscripts/P*.sh stop |
| `ss_post_start()` | 2812 | 启动后执行 postscripts/P*.sh start |

##### 主流程函数

| 函数 | 行号 | 功能 |
|------|------|------|
| `apply_ss()` | 2948 | ★ 完整启动流程（见下方流程图） |
| `disable_ss()` | 2929 | ★ 完整关闭流程 |
| `get_status()` | 3008 | 调试：打印进程和 iptables 状态 |

---

### 2. `apply_ss()` 完整启动流程（行2948-3005）

```
apply_ss()
├── ss_pre_stop()                    # 执行关闭前钩子
├── kill_process()                   # 杀死所有旧进程
├── restore_conf()                   # 清理旧配置
├── restart_dnsmasq()                # 重启 dnsmasq（清理状态）
├── flush_nat()                      # 清除旧 iptables 规则
├── kill_cron_job()                  # 清除旧定时任务
├── ss_pre_start()                   # 负载均衡检测
├── detect()                         # 环境检测
├── resolv_server_ip()               # 解析服务器IP
├── load_module()                    # 加载内核模块
├── create_ipset()                   # 创建 ipset
├── create_dnsmasq_conf()            # 生成 dnsmasq 配置
├── [create_*_json()]                # 根据类型生成配置文件
│   ├── type=0/1: create_ss_json()
│   ├── type=3 & !SS2022: create_v2ray_json()
│   ├── type=3 & SS2022: create_ss2022_json()
│   ├── type=4 & Trojan: create_trojan_json()
│   ├── type=4 & Trojan-Go: create_trojango_json()
│   ├── type=4 & Hysteria2: create_hy2_json()
│   └── type=5: create_naive_json()
├── [start_*()]                      # 根据类型启动进程
│   ├── type=0/1: start_ss_redir()
│   ├── type=2: start_koolgame()
│   ├── type=3/4(Trojan): start_xray_core()
│   ├── type=4(Trojan-Go): start_trojango()
│   ├── type=4(Hysteria2): start_hy2()
│   └── type=5: start_naiveproxy()
├── start_kcp()                      # KCP 加速（非 koolgame）
├── start_dns()                      # DNS 解析方案
├── load_nat()                       # 加载 NAT 规则
│   ├── add_white_black_ip()
│   ├── apply_nat_rules()
│   └── chromecast()
├── mount_dnsmasq_now()              # dnsmasq-fastlookup 替换
├── restart_dnsmasq()                # 最终重启 dnsmasq
├── auto_start()                     # 写入自启动
├── write_cron_job()                 # 定时任务
├── set_ss_reboot_job()              # 定时重启
├── set_ss_trigger_job()             # IP变化触发
└── ss_post_start()                  # 启动后钩子
```

---

### 3. 入口点（行3040-3093）

```bash
case $ACTION in
  start)    # wan-start/nat-start 触发
    set_lock → set_ulimit → apply_ss → write_numbers → unset_lock
  stop)     # 手动关闭
    set_lock → ss_pre_stop → disable_ss → unset_lock
  restart)  # 手动重启/定时重启
    set_lock → set_ulimit → apply_ss → write_numbers → unset_lock
  flush_nat)
    set_lock → flush_nat → unset_lock
  *)        # 默认（nat-start 无参数调用）
    set_lock → set_ulimit → apply_ss → write_numbers → unset_lock
esac
```

---
<!-- PLACEHOLDER_SECTION_3 -->

## DNS 解析方案详解

`start_dns()` 根据 `ss_foreign_dns` 变量选择国外DNS方案：

| ss_foreign_dns | 方案 | 实现 |
|---|---|---|
| 1 | cdns | cdns 进程，EDNS方式获取无污染DNS |
| 2 | chinadns2 | chinadns 进程，国内外DNS分流过滤 |
| 3 | dns2socks（默认） | ss-local:23456 + dns2socks 转发 |
| 4 | ss-tunnel/rss-tunnel | 直接通过SS隧道转发DNS |
| 5 | chinadns1 + dns2socks | chinadns1 + dns2socks 上游 |
| 6 | https_dns_proxy | DoH 方式解析 |
| 7 | v2ray/xray 内置 DNS | dokodemo-door 入站 + xray DNS |
| 8 | 直连（回国模式专用） | 不经代理直连国外DNS |
| 9 | SmartDNS | smartdns 进程 |
| 10 | ChinaDNS-NG | chinadns-ng + dns2socks 上游 |

### DNS 策略逻辑（国内优先 vs 国外优先）

- **国内优先**（gfwlist模式）：dnsmasq 全局用中国DNS，仅 gfwlist 域名走国外DNS → 不需要 cdn.conf
- **国外优先**（大陆白名单/游戏/全局模式）：dnsmasq 全局用国外DNS，需要 cdn.conf 保证国内网站解析效果
- chinadns1/chinadns2/ChinaDNS-NG 自带国内CDN分流，不需要额外 cdn.conf

### 国内DNS选择（`ss_dns_china`）

| 值 | DNS服务器 |
|---|---|
| 1 | ISP DNS（运营商） |
| 2 | 223.5.5.5（阿里） |
| 3 | 223.6.6.6（阿里） |
| 4 | 114.114.114.114 |
| 5 | 114.114.115.115 |
| 6 | 1.2.4.8（CNNIC） |
| 7 | 210.2.4.8（CNNIC） |
| 8 | 117.50.11.11（OneDNS） |
| 9 | 117.50.22.22（OneDNS） |
| 10 | 180.76.76.76（百度） |
| 11 | 119.29.29.29（DNSPod） |
| 12 | 自定义 |
| 13 | SmartDNS (127.0.0.1:5335) |

---

## NAT/iptables 规则架构

### iptables 链结构（nat 表）

```
PREROUTING
└── SHADOWSOCKS (主链)
    ├── white_list dst → RETURN (白名单不走代理)
    ├── [ACL规则: 按IP/端口分流到不同模式链]
    └── 剩余流量 → 对应模式链
        ├── SHADOWSOCKS_GFW   (gfwlist: black_list+gfwlist → REDIRECT:3333)
        ├── SHADOWSOCKS_CHN   (大陆白名单: black_list+!chnroute → REDIRECT:3333)
        ├── SHADOWSOCKS_GAM   (游戏: 同CHN)
        ├── SHADOWSOCKS_GLO   (全局: 全部 → REDIRECT:3333)
        └── SHADOWSOCKS_HOM   (回国: black_list+chnroute → REDIRECT:3333)

OUTPUT
├── router ipset → REDIRECT:3333 (路由器自身流量)
└── SHADOWSOCKS_EXT (KoolProxy 扩展)
```

### iptables 链结构（mangle 表，游戏模式 UDP）

```
PREROUTING
└── SHADOWSOCKS (mangle)
    ├── white_list dst → RETURN
    ├── [ACL: 游戏模式主机 → SHADOWSOCKS_GAM]
    └── SHADOWSOCKS_GAM
        ├── black_list → TPROXY:3333 mark 0x07
        └── !chnroute → TPROXY:3333 mark 0x07
```

### ipset 集合

| 名称 | 类型 | 用途 |
|---|---|---|
| `chnroute` | nethash | 中国IP段（从 chnroute.txt 加载） |
| `white_list` | nethash | 白名单IP（保留地址+ISP DNS+服务器IP+用户自定义） |
| `black_list` | nethash | 黑名单IP（Telegram段+用户自定义） |
| `gfwlist` | nethash | GFW域名解析后的IP（由 dnsmasq ipset 动态填充） |
| `router` | nethash | 路由器自身需走代理的IP（github/google等） |

---

## 辅助脚本详解

### `scripts/ss_config.sh`（12行）
入口包装器：enable=1 时 restart，否则 stop。由 Web UI 提交时调用。

### `scripts/ss_online_update.sh`（2003行）
节点订阅更新脚本，支持解析多种订阅格式：

**核心函数：**
- `prepare()` — 下载订阅链接，base64解码
- `get_ss_config()` / `add_ss_servers()` — 解析 SS 节点
- `get_ssr_config()` / `add_ssr_servers()` — 解析 SSR 节点
- `get_vmess_config()` / `add_vmess_servers()` — 解析 VMess 节点
- `get_trojan_config()` / `add_trojan_servers()` — 解析 Trojan 节点
- `get_vless_config()` / `add_vless_servers()` — 解析 VLESS 节点
- `get_trojan_go_config()` / `add_trojan_go_servers()` — 解析 Trojan-Go 节点
- `del_none_exist()` — 删除订阅中已不存在的节点
- `remove_node_gap()` — 整理节点编号间隙
- `get_oneline_rule_now()` — 解析单行 URI（ss:// vmess:// vless:// trojan:// hysteria2://）
- `start_update()` — 更新主流程
- `remove_all()` / `remove_online()` — 删除节点

### `scripts/ss_v2ray_xray.sh`（222行）
二进制更新脚本，支持更新 xray/naive/hysteria：
- 从 GitHub raw 下载 latest.txt 获取最新版本
- 下载二进制 + md5sum 校验
- 替换并重启进程
- 支持通过 SOCKS5:23456 代理下载

### `scripts/ss_lb_config.sh`（212行）
HAProxy 负载均衡配置生成：
- 生成 haproxy.cfg（TCP模式，roundrobin）
- 支持心跳检测（故障转移）
- 管理界面绑定 0.0.0.0:1188

### `scripts/ss_proc_status.sh`（337行）
进程状态检测脚本，供 Web UI AJAX 调用：
- 检测各进程运行状态
- 显示版本信息
- 显示 iptables 规则状态
- 显示 DNS 解析方案状态

### `scripts/ss_rule_update.sh`（201行）
规则文件更新：
- 更新 chnroute.txt（中国IP段）
- 更新 gfwlist.conf（GFW域名列表）
- 更新 cdn.txt（国内CDN域名）
- 从 GitHub 下载，支持代理

### `scripts/ss_reboot_job.sh`（150行）
定时重启与IP变化检测：
- `check_ip()` — 对比 /tmp/ss_host.conf 中的旧IP与新解析IP
- IP变化时根据策略重启插件或仅重启 dnsmasq
- `set_ss_reboot_job()` — 支持每天/每周/每月/间隔/自定义时间重启

### `scripts/ss_webtest.sh`（789行）
网络连通性测试脚本，供 Web UI 调用。

### `scripts/ss_socks5.sh`（67行）
独立 SOCKS5 代理服务（开机自启 S99socks5.sh）。

### `scripts/ss_ping.sh`（73行）
节点延迟测试（httping）。

### `scripts/ss_fix_conf.sh`（66行）
配置修复脚本。

### `scripts/ss_pack.sh`（42行）
打包脚本（生成安装包 tar.gz）。

---

## Xray 聚合节点（xagg）机制

当用户 JSON 中存在 `xagg_` 前缀的 outbound tag 时，触发聚合逻辑：

1. 检测 `xagg_meta` outbound 获取策略（默认 leastPing）
2. 剔除 `xagg_meta`，保留真实节点 outbound
3. 生成 routing balancer + observatory 配置
4. observatory 每30秒探测 `https://www.gstatic.com/generate_204`
5. 支持策略：leastPing / random / leastLoad

---

## Web UI 页面

| 文件 | 功能 |
|---|---|
| `Main_Ss_Content.asp` (5848行) | 主设置页面（节点配置/DNS/访问控制/定时任务） |
| `Main_SsLocal_Content.asp` (308行) | 本地 SOCKS5 代理设置 |
| `Main_Ss_LoadBlance.asp` (663行) | 负载均衡设置 |
| `Main_SsXray_Aggregate.asp` (493行) | Xray 聚合节点设置 |

---

## 二进制文件清单（bin/）

| 文件 | 用途 |
|---|---|
| `xray` | Xray 核心（vmess/vless/trojan/ss2022） |
| `ss-local` | SS 本地 SOCKS5 代理 |
| `ss-redir` | SS 透明代理 |
| `ss-tunnel` | SS DNS 隧道 |
| `rss-local` | SSR 本地代理 |
| `rss-redir` | SSR 透明代理 |
| `trojan-go` | Trojan-Go 客户端 |
| `naive` | NaiveProxy 客户端 |
| `hysteria` | Hysteria2 客户端 |
| `obfs-local` | simple-obfs 混淆插件 |
| `chinadns` | ChinaDNS2 |
| `chinadns1` | ChinaDNS1 |
| `chinadns-ng` | ChinaDNS-NG |
| `cdns` | EDNS DNS 解析 |
| `dns2socks` | DNS over SOCKS5 转发 |
| `smartdns` | SmartDNS |
| `https_dns_proxy` | DoH 代理 |
| `dnsmasq` | dnsmasq-fastlookup 替代版 |
| `client_linux_arm5` | kcptun 客户端 |
| `speederv1` / `speederv2` | UDPspeeder v1/v2 |
| `udp2raw` | UDP2raw 伪装 |
| `haproxy` | HAProxy 负载均衡 |
| `koolgame` | koolgame 游戏加速 |
| `pdu` | MTU 优化 |
| `haveged` | 系统熵源 |
| `httping` | HTTP 延迟测试 |
| `jq` | JSON 处理 |
| `base64_encode` | Base64 编解码 |
| `koolbox` | 多功能工具（base64/shuf/netstat） |
| `resolveip` | 域名解析工具 |

---

## 规则文件（ss/rules/）

| 文件 | 用途 |
|---|---|
| `chnroute.txt` | 中国IP段列表（ipset 加载） |
| `gfwlist.conf` | GFW域名 dnsmasq 配置（server + ipset） |
| `gfwlist.acl` | GFW ACL 文件 |
| `cdn.txt` | 国内CDN域名列表 |
| `chn.acl` | 中国域名 ACL |
| `cdns.json` | cdns 配置模板 |
| `smartdns_template.conf` | SmartDNS 配置模板 |
| `dnsmasq.postconf` | dnsmasq 后置配置脚本 |
| `version` | 规则版本号 |

---

## 安装/卸载流程

### install.sh 流程
1. 检测平台（armv7l）和固件版本（≥X7.2）
2. 如果插件运行中，先 stop
3. 备份 postscripts
4. 恢复 dnsmasq（如果被替换）
5. 清理旧文件（bin/ss/scripts/webs/res）
6. 复制新文件
7. 设置权限
8. 恢复 postscripts
9. 创建软链接（rss-tunnel/base64/shuf/netstat/base64_decode/S99socks5.sh）
10. 设置默认值
11. 写入版本号到 dbus
12. 如果之前运行中，restart

### uninstall.sh 流程
- stop 插件 → 清理所有文件 → 清理 dbus 数据 → 清理 nvram → 清理 cron

---

## 数据存储机制

插件使用 `dbus`（skipd）作为键值存储：
- `ss_basic_*` — 基本设置
- `ss_acl_*` — 访问控制
- `ssconf_basic_*` — 节点配置（按编号）
- `ss_lb_*` — 负载均衡
- `ss_foreign_dns` — 国外DNS方案
- `ss_dns_china` — 国内DNS选择

`nvram` 用于存储少量状态：
- `ss_mode` — 当前模式
- `update_ipset` / `update_chnroute` / `update_cdn` — 规则版本
- `ss_china_state` / `ss_foreign_state` — 连通性状态

---

## 端口分配

| 端口 | 用途 |
|---|---|
| 3333 | 透明代理入口（ss-redir/xray/trojan-go/naive/hysteria） |
| 23456 | SOCKS5 代理（ss-local/xray/trojan-go/naive/hysteria） |
| 7913 | 国外DNS解析端口（DNSF_PORT） |
| 5335 | SmartDNS 监听端口 |
| 1055 | chinadns1 上游 dns2socks 端口 |
| 1091 | kcptun 本地监听 |
| 1092 | UDPspeeder 本地监听 |
| 1093 | UDP2raw 本地监听 |
| 1188 | HAProxy 管理界面 |

---

## 关键流程图：数据包路径

### TCP 流量路径
```
LAN设备 → iptables PREROUTING (nat)
  → SHADOWSOCKS 链
    → 匹配 ACL / 模式链
      → REDIRECT :3333
        → ss-redir / xray / trojan-go / naive / hysteria
          → [可选: kcptun :1091]
            → 远程服务器
```

### UDP 流量路径（游戏模式）
```
LAN设备 → iptables PREROUTING (mangle)
  → SHADOWSOCKS 链
    → SHADOWSOCKS_GAM
      → TPROXY :3333 (mark 0x07)
        → xray / ss-redir -U
          → [可选: UDPspeeder :1092 → UDP2raw :1093]
            → 远程服务器
```

### DNS 解析路径（以 dns2socks 为例）
```
LAN设备 DNS请求
  → dnsmasq (:53)
    ├── gfwlist.conf 匹配 → 127.0.0.1:7913
    │     → dns2socks → ss-local:23456 → 远程DNS(8.8.8.8)
    ├── cdn.conf 匹配 → 国内DNS(如 119.29.29.29)
    └── 其他 → 默认上游DNS
```

---

## 魔改要点提示

如果你计划对 shadowsocks 目录进行魔改，以下是关键修改点：

1. **添加新协议**：在 `ssconfig.sh` 中添加 `create_xxx_json()` + `start_xxx()` 函数，并在 `apply_ss()` 中加入条件分支
2. **修改DNS方案**：在 `start_dns()` 中添加新的 `ss_foreign_dns` 分支
3. **修改NAT规则**：在 `apply_nat_rules()` 中修改 iptables 链
4. **添加新二进制**：放入 bin/ 目录，install.sh 中添加到 TARGET_BIN 列表
5. **Web UI 修改**：修改 `Main_Ss_Content.asp`，通过 dbus 传递参数
6. **订阅格式**：在 `ss_online_update.sh` 中添加 `get_xxx_config()` + `add_xxx_servers()`

---

## 深入：iptables 表状态与完整规则链

### 插件运行时 iptables 完整状态快照

#### nat 表 - PREROUTING 链

```
Chain PREROUTING (policy ACCEPT)
 num  target              prot  source    destination
 1    SHADOWSOCKS_DNS_0   udp   anywhere  anywhere     udp dpt:53  (DNS劫持,仅br0)
 2    SHADOWSOCKS         tcp   anywhere  anywhere     (主入口,所有TCP)
 ...  [KOOLPROXY等其他插件规则]
```

> 插入位置：SHADOWSOCKS 在 KOOLPROXY 之后（`INSET_NU = KP_NU + 1`），确保与广告过滤插件兼容。

#### nat 表 - SHADOWSOCKS 链（主分流链）

```
Chain SHADOWSOCKS (1 references)
 num  target              prot  source       destination
 1    RETURN              tcp   anywhere     match-set white_list dst  (白名单直连)
 2    SHADOWSOCKS_GFW     tcp   192.168.1.100  anywhere  (ACL: 指定主机走gfwlist)
 3    SHADOWSOCKS_CHN     tcp   192.168.1.101  anywhere  (ACL: 指定主机走大陆白名单)
 4    RETURN              tcp   192.168.1.102  anywhere  (ACL: 指定主机不走代理)
 ...  [更多ACL规则]
 N    SHADOWSOCKS_CHN     tcp   anywhere     anywhere  multiport dports [端口] (剩余流量→默认模式)
```

#### nat 表 - 各模式子链

```
Chain SHADOWSOCKS_GFW (gfwlist模式)
 1    REDIRECT :3333    tcp   anywhere   match-set black_list dst   (黑名单强制走代理)
 2    REDIRECT :3333    tcp   anywhere   match-set gfwlist dst      (gfwlist匹配走代理)
 [不匹配则隐式RETURN=直连]

Chain SHADOWSOCKS_CHN (大陆白名单模式)
 1    REDIRECT :3333    tcp   anywhere   match-set black_list dst   (黑名单强制走代理)
 2    REDIRECT :3333    tcp   anywhere   ! match-set chnroute dst   (非中国IP走代理)
 [中国IP则隐式RETURN=直连]

Chain SHADOWSOCKS_GAM (游戏模式) - TCP规则同CHN
 1    REDIRECT :3333    tcp   anywhere   match-set black_list dst
 2    REDIRECT :3333    tcp   anywhere   ! match-set chnroute dst

Chain SHADOWSOCKS_GLO (全局模式)
 1    REDIRECT :3333    tcp   anywhere   anywhere                   (所有流量走代理)

Chain SHADOWSOCKS_HOM (回国模式)
 1    REDIRECT :3333    tcp   anywhere   match-set black_list dst   (黑名单走代理)
 2    REDIRECT :3333    tcp   anywhere   match-set chnroute dst     (中国IP走代理! 与CHN相反)
 [非中国IP则隐式RETURN=直连]
```

#### nat 表 - OUTPUT 链（路由器自身流量）

```
Chain OUTPUT (policy ACCEPT)
 1    REDIRECT :3333    tcp   anywhere   match-set router dst       (路由器自身需代理的目标)
 2    SHADOWSOCKS_EXT   tcp   anywhere   anywhere  mark match $ip_prefix_hex (KP标记流量)
```

#### nat 表 - SHADOWSOCKS_EXT 链（KoolProxy扩展）

```
Chain SHADOWSOCKS_EXT
 1    RETURN            tcp   anywhere   match-set white_list dst   (白名单直连)
 ...  [ACL规则,按mark匹配主机]
 N    SHADOWSOCKS_CHN   tcp   anywhere   anywhere                  (剩余→默认模式)
```

#### nat 表 - DNS 劫持链（每个br接口一条）

```
Chain SHADOWSOCKS_DNS_0 (br0接口)
 1    DNAT to 192.168.1.1:53   udp   anywhere   anywhere           (强制DNS请求到路由器)
```

---

#### mangle 表 - PREROUTING 链（UDP/游戏模式）

```
Chain PREROUTING (policy ACCEPT)
 ...
 N    SHADOWSOCKS       udp   anywhere   anywhere                  (UDP主入口)
```

#### mangle 表 - SHADOWSOCKS 链

```
Chain SHADOWSOCKS (mangle)
 1    RETURN            udp   anywhere   match-set white_list dst   (白名单直连)
 2    SHADOWSOCKS_GAM   udp   192.168.1.100  anywhere              (ACL: 游戏模式主机)
 3    RETURN            udp   192.168.1.101  anywhere              (ACL: 非游戏主机不走UDP代理)
 N    SHADOWSOCKS_GAM   udp   anywhere   anywhere                  (剩余UDP→游戏模式链)
```

#### mangle 表 - SHADOWSOCKS_GAM 链（UDP TPROXY）

```
Chain SHADOWSOCKS_GAM (mangle)
 1    TPROXY redirect :3333 mark 0x07   udp   anywhere   match-set black_list dst
 2    TPROXY redirect :3333 mark 0x07   udp   anywhere   ! match-set chnroute dst
```

---

### TPROXY UDP 转发机制（核心代码 ssconfig.sh 行2310-2337, 2618-2630）

```bash
# 1. 加载内核模块（行2310-2337）
load_tproxy(){
    MODULES="nf_tproxy_core xt_TPROXY xt_socket xt_comment"
    OS=$(uname -r)
    for MODULE in $MODULES; do
        insmod /lib/modules/${OS}/kernel/net/netfilter/${MODULE}.ko
    done
}

# 2. 策略路由配置（行2619-2620）
# 被标记 0x07 的包走路由表310，表310将所有流量送到本地回环
ip rule add fwmark 0x07 table 310
ip route add local 0.0.0.0/0 dev lo table 310

# 3. mangle TPROXY 规则（行2628-2630）
# 匹配后打标记 + 透明代理到本地3333端口
iptables -t mangle -A SHADOWSOCKS_GAM -p udp \
    -m set --match-set black_list dst \
    -j TPROXY --on-port 3333 --tproxy-mark 0x07
iptables -t mangle -A SHADOWSOCKS_GAM -p udp \
    -m set ! --match-set chnroute dst \
    -j TPROXY --on-port 3333 --tproxy-mark 0x07
```

**TPROXY原理**：与 nat REDIRECT 不同，TPROXY 不修改数据包的目标地址。通过策略路由将标记包送到本地 lo 接口，由监听 0.0.0.0:3333 的 xray（需开启 `followRedirect: true`）以透明代理方式处理 UDP 包，保留原始目标地址信息。

---

### QoS 兼容处理（核心代码 行2654-2659）

```bash
QOSO=$(iptables -t mangle -S | grep -o QOSO | wc -l)
RRULE=$(iptables -t mangle -S | grep "A QOSO" | head -n1 | grep RETURN)
if [ "$QOSO" -gt "1" ] && [ -z "$RRULE" ]; then
    # 在 QoS 链(QOSO0)头部插入 RETURN，防止代理流量被 QoS 重新标记导致异常
    iptables -t mangle -I QOSO0 -m mark --mark "$ip_prefix_hex" -j RETURN
fi
```

`ip_prefix_hex` = LAN网段十六进制（如 `0xc0a80100/0xffffff00` = 192.168.1.0/24）

---

### flush_nat() 完整清理顺序（核心代码 行2340-2406）

```bash
flush_nat(){
    # === 第一步：从 PREROUTING 中删除跳转规则（倒序删除防止索引偏移）===
    nat_indexs=$(iptables -nvL PREROUTING -t nat | sed 1,2d | sed -n '/SHADOWSOCKS/=' | sort -r)
    for nat_index in $nat_indexs; do
        iptables -t nat -D PREROUTING $nat_index
    done

    # === 第二步：清空并删除所有自定义链 ===
    iptables -t nat -F SHADOWSOCKS && iptables -t nat -X SHADOWSOCKS
    iptables -t nat -F SHADOWSOCKS_EXT
    iptables -t nat -F SHADOWSOCKS_GFW && iptables -t nat -X SHADOWSOCKS_GFW
    iptables -t nat -F SHADOWSOCKS_CHN && iptables -t nat -X SHADOWSOCKS_CHN
    iptables -t nat -F SHADOWSOCKS_GAM && iptables -t nat -X SHADOWSOCKS_GAM
    iptables -t nat -F SHADOWSOCKS_GLO && iptables -t nat -X SHADOWSOCKS_GLO
    iptables -t nat -F SHADOWSOCKS_HOM && iptables -t nat -X SHADOWSOCKS_HOM

    # === 第三步：清理 mangle 表 ===
    mangle_indexs=$(iptables -nvL PREROUTING -t mangle | sed 1,2d | sed -n '/SHADOWSOCKS/=' | sort -r)
    for mangle_index in $mangle_indexs; do
        iptables -t mangle -D PREROUTING $mangle_index
    done
    iptables -t mangle -F SHADOWSOCKS && iptables -t mangle -X SHADOWSOCKS
    iptables -t mangle -F SHADOWSOCKS_GAM && iptables -t mangle -X SHADOWSOCKS_GAM

    # === 第四步：清理 OUTPUT 链 ===
    iptables -t nat -D OUTPUT -p tcp -m set --match-set router dst -j REDIRECT --to-ports 3333
    iptables -t nat -F OUTPUT
    iptables -t nat -X SHADOWSOCKS_EXT

    # === 第五步：清理 DNS 劫持链（按 VLAN 接口遍历）===
    VLAN_INDEXS=$(ifconfig | grep -E "^br" | awk '{print $1}' | sed 's/^br//g')
    for VLAN_INDEX in $VLAN_INDEXS; do
        iptables -t nat -F SHADOWSOCKS_DNS_${VLAN_INDEX} && iptables -t nat -X SHADOWSOCKS_DNS_${VLAN_INDEX}
    done

    # === 第六步：清理 QoS 兼容规则 ===
    iptables -t mangle -D QOSO0 -m mark --mark "$ip_prefix_hex" -j RETURN

    # === 第七步：销毁所有 ipset ===
    ipset -F chnroute && ipset -X chnroute
    ipset -F white_list && ipset -X white_list
    ipset -F black_list && ipset -X black_list
    ipset -F gfwlist && ipset -X gfwlist
    ipset -F router && ipset -X router

    # === 第八步：清理策略路由 ===
    # 循环删除所有 lookup 310 的 ip rule（可能有重复）
    ip_rule_exist=$(ip rule show | grep "lookup 310" | grep -c 310)
    until [ "$ip_rule_exist" = 0 ]; do
        IP_ARG=$(ip rule show | grep "lookup 310" | head -n 1 | cut -d " " -f3,4,5,6)
        ip rule del $IP_ARG
        ip_rule_exist=$(expr $ip_rule_exist - 1)
    done
    ip route del local 0.0.0.0/0 dev lo table 310
}
```

---
## Merlin 固件网络处理流程与插件集成

### Merlin 固件启动时序与插件触发点

```
路由器上电
  → 内核启动 → init → 各系统服务启动
    → WAN 接口获取IP (DHCP/PPPoE)
      → 触发 /jffs/scripts/wan-start        ← 插件注入点①
        → sh /koolshare/scripts/ss_config.sh
          → ssconfig.sh start (完整启动流程)
    → NAT 表初始化完成
      → 触发 /jffs/scripts/nat-start        ← 插件注入点②
        → sh /koolshare/ss/ssconfig.sh (加载NAT规则)
    → dnsmasq 启动/重启
      → 触发 /jffs/scripts/dnsmasq.postconf  ← 插件注入点③
        → 修改 dnsmasq 配置（DNS上游/缓存）
```

### 三个关键 Merlin 钩子脚本

#### 1. `/jffs/scripts/wan-start`（WAN连接建立后）

```bash
#!/bin/sh
/usr/bin/onwanstart.sh          # Merlin 原生处理
sh /koolshare/scripts/ss_config.sh   # ← 插件注入（行986）
```

**触发时机**：WAN口获得IP后（开机/断线重连/PPPoE重拨）
**作用**：启动所有代理进程（xray/ss-redir等）+ DNS + 定时任务

#### 2. `/jffs/scripts/nat-start`（NAT表就绪后）

```bash
#!/bin/sh
/usr/bin/onnatstart.sh          # Merlin 原生处理
sh /koolshare/ss/ssconfig.sh    # ← 插件注入（行969）
```

**触发时机**：iptables nat 表初始化完成后（开机/防火墙重载）
**作用**：重新加载 iptables 规则（因为防火墙重载会清空自定义规则）
**注意**：此处调用 ssconfig.sh 无参数，走 `*)` 分支 = 完整 apply_ss

#### 3. `/jffs/scripts/dnsmasq.postconf`（dnsmasq配置后处理）

```bash
#!/bin/sh
# 软链接到 /koolshare/ss/rules/dnsmasq.postconf
# 参数 $1 = /etc/dnsmasq.conf 路径

# 根据模式修改 dnsmasq 全局 DNS 上游：
# - 国内优先模式：server=国内DNS#53 + no-resolv
# - 国外优先模式：server=127.0.0.1#7913 + no-resolv
# 同时设置 cache-size=9999
```

**触发时机**：每次 dnsmasq 重启前（`service restart_dnsmasq`）
**作用**：动态修改 `/etc/dnsmasq.conf`，设置 DNS 上游服务器
**核心函数**：`pc_replace` / `pc_insert`（来自 Merlin helper.sh）

### auto_start() 注入逻辑（核心代码 行954-989）

```bash
auto_start(){
    # === 注入 nat-start ===
    # 如果文件不存在则创建
    if [ ! -f /jffs/scripts/nat-start ]; then
        cat > /jffs/scripts/nat-start <<-EOF
            #!/bin/sh
            /usr/bin/onnatstart.sh
        EOF
    fi
    # 检查是否已注入，未注入则在第2行插入
    writenat=$(cat /jffs/scripts/nat-start | grep "ssconfig")
    if [ -z "$writenat" ]; then
        sed -i '2a sh /koolshare/ss/ssconfig.sh' /jffs/scripts/nat-start
        chmod +x /jffs/scripts/nat-start
    fi

    # === 注入 wan-start ===
    if [ ! -f /jffs/scripts/wan-start ]; then
        cat > /jffs/scripts/wan-start <<-EOF
            #!/bin/sh
            /usr/bin/onwanstart.sh
        EOF
    fi
    startss=$(cat /jffs/scripts/wan-start | grep "/koolshare/scripts/ss_config.sh")
    if [ -z "$startss" ]; then
        sed -i '2a sh /koolshare/scripts/ss_config.sh' /jffs/scripts/wan-start
    fi
    chmod +x /jffs/scripts/wan-start
}
```

---

### Merlin 固件网络栈与插件交互全景

```
                    ┌─────────────────────────────────────────────────┐
                    │              Merlin 固件网络栈                    │
                    └─────────────────────────────────────────────────┘

  [LAN设备] ──TCP/UDP──→ [br0 网桥接口]
                              │
                    ┌─────────▼──────────┐
                    │  netfilter PREROUTING │
                    │  (raw → mangle → nat) │
                    └─────────┬──────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
     ┌────────▼────────┐     │      ┌────────▼────────┐
     │ mangle表:        │     │      │ nat表:           │
     │ SHADOWSOCKS链    │     │      │ SHADOWSOCKS链    │
     │ (UDP TPROXY)    │     │      │ (TCP REDIRECT)   │
     └────────┬────────┘     │      └────────┬────────┘
              │               │               │
              │ mark 0x07     │               │ REDIRECT :3333
              │               │               │
     ┌────────▼────────┐     │      ┌────────▼────────┐
     │ ip rule:         │     │      │ 本地进程:         │
     │ fwmark 0x07      │     │      │ xray/ss-redir    │
     │ → table 310      │     │      │ 监听 :3333       │
     │ → local loopback │     │      │ (TCP透明代理)     │
     └────────┬────────┘     │      └────────┬────────┘
              │               │               │
     ┌────────▼────────┐     │               │
     │ 本地进程:         │     │               │
     │ xray :3333       │     │               │
     │ (UDP TPROXY)    │     │               │
     └────────┬────────┘     │               │
              │               │               │
              └───────────────┼───────────────┘
                              │
                    ┌─────────▼──────────┐
                    │  路由决策 (FORWARD)   │
                    │  或本地处理           │
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │  netfilter OUTPUT    │  ← 路由器自身流量
                    │  (router ipset匹配)  │
                    │  REDIRECT :3333     │
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │  WAN 接口出站        │
                    │  → 远程代理服务器     │
                    └─────────────────────┘
```

---

### DNS 请求在 Merlin 中的完整路径

```
[LAN设备] ──DNS(udp:53)──→ [br0]
        │
        ▼
┌─────────────────────────────────────────────────────────┐
│ iptables nat PREROUTING:                                 │
│   SHADOWSOCKS_DNS_0: -p udp --dport 53 -j DNAT → 路由器IP:53 │
│   (DNS劫持：强制所有DNS请求到路由器dnsmasq)                    │
└────────────────────────┬────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────┐
│ dnsmasq (:53)                                            │
│                                                          │
│ 配置来源：                                                │
│   /etc/dnsmasq.conf        ← dnsmasq.postconf 修改       │
│   /jffs/configs/dnsmasq.d/ ← 软链接目录                   │
│     ├── gfwlist.conf → /koolshare/ss/rules/gfwlist.conf  │
│     ├── cdn.conf → /tmp/sscdn.conf                       │
│     ├── wblist.conf → /tmp/wblist.conf                   │
│     ├── custom.conf → /tmp/custom.conf                   │
│     └── ss_server.conf (服务器域名解析)                    │
│                                                          │
│ 解析逻辑：                                                │
│   1. wblist.conf 白名单域名 → 国内DNS直连                  │
│   2. wblist.conf 黑名单域名 → 127.0.0.1:7913(国外DNS)     │
│   3. gfwlist.conf 匹配 → 127.0.0.1:7913 + ipset gfwlist  │
│   4. cdn.conf 匹配 → 国内DNS(如119.29.29.29)              │
│   5. 默认上游 → 取决于 dnsmasq.postconf 设置               │
│      国内优先: server=国内DNS#53                           │
│      国外优先: server=127.0.0.1#7913                      │
└────────────────────────┬────────────────────────────────┘
                         │
          ┌──────────────┼──────────────┐
          ▼                             ▼
┌──────────────────┐          ┌──────────────────┐
│ 国内DNS直连       │          │ 127.0.0.1:7913   │
│ (114/阿里/DNSPod) │          │ (防污染DNS端口)    │
│                  │          │                  │
│ 返回国内CDN IP    │          │ 实现方式(择一):    │
└──────────────────┘          │  dns2socks       │
                              │  cdns            │
                              │  chinadns        │
                              │  ss-tunnel       │
                              │  xray内置DNS     │
                              │  smartdns        │
                              │  https_dns_proxy │
                              └────────┬─────────┘
                                       ▼
                              ┌──────────────────┐
                              │ 通过代理隧道查询   │
                              │ 远程DNS(8.8.8.8)  │
                              │ 返回真实IP         │
                              │ + 写入ipset gfwlist│
                              └──────────────────┘
```

---

### dnsmasq 与 ipset 联动机制

gfwlist.conf 中每条规则格式：
```
server=/.google.com/127.0.0.1#7913
ipset=/.google.com/gfwlist
```

**工作原理**：
1. 当 LAN 设备请求 `www.google.com` 时，dnsmasq 匹配 gfwlist.conf
2. DNS 查询转发到 `127.0.0.1:7913`（防污染DNS）获得真实IP
3. 同时将解析结果IP自动加入 ipset `gfwlist` 集合
4. 后续该设备访问此IP时，iptables 匹配 `match-set gfwlist dst` → REDIRECT 到代理

这实现了**域名级别的动态分流**：只有 gfwlist 中的域名对应的IP才走代理。

---

### Merlin 固件特有机制与插件适配

#### nvram 与 dbus(skipd) 双存储

| 存储 | 用途 | 持久性 |
|------|------|--------|
| nvram | 固件原生设置（wan0_dns, lan_ipaddr等） | 写入闪存，重启保留 |
| dbus (skipd) | 插件设置（ss_basic_*等） | /tmp/skipd 内存数据库，通过 jffs 持久化 |

```bash
# 读取固件设置
ISP_DNS1=$(nvram get wan0_dns | sed 's/ /\n/g' | sed -n 1p)
lan_ipaddr=$(nvram get lan_ipaddr)

# 读写插件设置
eval $(dbus export ss)              # 导出所有 ss_ 开头的变量
dbus set ss_basic_enable="1"        # 写入
dbus get ss_basic_server            # 读取
dbus list ss_acl_mode_              # 列出前缀匹配的所有键
dbus remove ss_basic_server_ip      # 删除
```

#### jffs2_scripts 依赖

插件依赖 Merlin 的 `Enable JFFS custom scripts and configs` 选项：
- `/jffs/scripts/` — 自定义脚本目录（wan-start, nat-start 等）
- `/jffs/configs/dnsmasq.d/` — dnsmasq 额外配置目录（自动加载）
- `/jffs/configs/dnsmasq.conf.add` — dnsmasq 追加配置

#### helper.sh 工具函数

Merlin 提供的 `/usr/sbin/helper.sh`（或 `/koolshare/scripts/base.sh`）：
```bash
source /koolshare/scripts/base.sh   # 加载基础环境
source helper.sh                     # Merlin helper

# 常用函数：
pc_replace "old" "new" $CONFIG      # 替换 dnsmasq.conf 中的配置
pc_insert "after_line" "new_line" "/etc/dnsmasq.conf"  # 在指定行后插入
base64_decode                        # Base64 解码（管道使用）
```

#### Merlin cru 定时任务

```bash
# cru = Merlin 封装的 crontab 管理工具
cru a ssupdate "15 4 * * * /bin/sh /koolshare/scripts/ss_rule_update.sh"
cru a ssnodeupdate "2 3 * * 1 /koolshare/scripts/ss_online_update.sh 3"
cru a ss_reboot "0 4 * * * /koolshare/ss/ssconfig.sh restart"
cru a ss_tri_check "*/10 * * * * /koolshare/scripts/ss_reboot_job.sh check_ip"
cru d ssupdate    # 删除任务
cru l             # 列出所有任务
```

#### service 命令

```bash
service restart_dnsmasq    # 重启 dnsmasq（触发 dnsmasq.postconf）
service restart_firewall   # 重启防火墙（触发 nat-start）
```

---

### 插件与 Merlin 网络栈的生命周期交互

```
┌─────────────────────────────────────────────────────────────────┐
│                    完整生命周期状态机                              │
└─────────────────────────────────────────────────────────────────┘

[路由器开机] ──→ [WAN就绪] ──wan-start──→ [ss_config.sh]
                                              │
                                    ┌─────────▼─────────┐
                                    │  ssconfig.sh start │
                                    │  (enable==1时)     │
                                    └─────────┬─────────┘
                                              │
                              ┌────────────────┼────────────────┐
                              ▼                ▼                ▼
                    [启动代理进程]     [配置DNS]        [等待NAT就绪]
                    xray/naive/hy2    dnsmasq配置       load_nat()
                              │                │         最多等120秒
                              │                │                │
                              └────────────────┼────────────────┘
                                              │
                                    ┌─────────▼─────────┐
                                    │  apply_nat_rules() │
                                    │  写入iptables      │
                                    └─────────┬─────────┘
                                              │
                                    ┌─────────▼─────────┐
                                    │  运行中 (RUNNING)   │
                                    └─────────┬─────────┘
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    │                         │                         │
          [防火墙重载]              [WAN断线重连]              [用户操作/定时重启]
          nat-start触发             wan-start触发              Web UI / cron
                    │                         │                         │
                    ▼                         ▼                         ▼
          ssconfig.sh (无参数)      ss_config.sh              ssconfig.sh restart
          = 完整 apply_ss          → ssconfig.sh restart      = 完整 apply_ss
          (先stop再start)          (先stop再start)            (先stop再start)
                    │                         │                         │
                    └─────────────────────────┼─────────────────────────┘
                                              │
                                    ┌─────────▼─────────┐
                                    │  运行中 (RUNNING)   │
                                    └─────────┬─────────┘
                                              │
                                    [用户关闭 / 卸载]
                                              │
                                    ┌─────────▼─────────┐
                                    │  ssconfig.sh stop  │
                                    │  disable_ss()      │
                                    └─────────┬─────────┘
                                              │
                              ┌────────────────┼────────────────┐
                              ▼                ▼                ▼
                    [kill所有进程]    [清理iptables]    [恢复dnsmasq]
                    kill_process()   flush_nat()      restore_conf()
                                                     restart_dnsmasq()
                              │                │                │
                              └────────────────┼────────────────┘
                                              │
                                    ┌─────────▼─────────┐
                                    │  已停止 (STOPPED)   │
                                    └─────────────────────┘
```

---

### load_nat() 等待机制（核心代码 行2792-2810）

```bash
load_nat(){
    # 等待 NAT 表就绪（最多120秒）
    # 原因：wan-start 触发时 NAT 可能尚未完全初始化
    nat_ready=$(iptables -t nat -L PREROUTING -v -n --line-numbers | grep -v PREROUTING | grep -v destination)
    i=120
    until [ -n "$nat_ready" ]; do
        i=$(($i-1))
        if [ "$i" -lt 1 ]; then
            echo_date "错误：不能正确加载nat规则!"
            close_in_five
        fi
        sleep 1
        nat_ready=$(iptables -t nat -L PREROUTING -v -n --line-numbers | grep -v PREROUTING | grep -v destination)
    done
    echo_date "加载nat规则!"
    add_white_black_ip    # 填充 ipset 黑白名单
    apply_nat_rules       # 写入 iptables 规则
    chromecast            # DNS 劫持规则
}
```

---

### 文件锁机制（防止并发冲突）

```bash
LOCK_FILE=/var/lock/koolss.lock

set_lock(){
    exec 1000>"$LOCK_FILE"    # 打开文件描述符1000
    flock -x 1000             # 获取排他锁（阻塞等待）
}

unset_lock(){
    flock -u 1000             # 释放锁
    rm -rf "$LOCK_FILE"       # 删除锁文件
}
```

**场景**：防止 nat-start 和 wan-start 同时触发导致规则写入冲突。

---

### Merlin 固件 dnsmasq 替换机制

插件可选用 `dnsmasq-fastlookup` 替换原版 dnsmasq（处理4万+条 cdn.conf 时性能更好）：

```bash
mount_dnsmasq(){
    killall dnsmasq
    mount --bind /koolshare/bin/dnsmasq /usr/sbin/dnsmasq   # bind mount 覆盖
}

umount_dnsmasq(){
    killall dnsmasq
    umount /usr/sbin/dnsmasq    # 恢复原版
}
```

**策略**（`ss_basic_dnsmasq_fastlookup`）：
- 0 = 始终用原版
- 1 = 始终用 fastlookup
- 2 = 自动（有 cdn.conf 时用 fastlookup）
- 3 = 始终用 fastlookup 且关闭插件后保持

---

### KoolProxy 兼容（广告过滤插件）

```bash
# 检测 KOOLPROXY 在 PREROUTING 中的位置
KP_NU=$(iptables -nvL PREROUTING -t nat | sed 1,2d | sed -n '/KOOLPROXY/=' | head -n1)
[ "$KP_NU" == "" ] && KP_NU=0
INSET_NU=$(expr "$KP_NU" + 1)

# 在 KOOLPROXY 之后插入 SHADOWSOCKS（确保广告过滤先执行）
iptables -t nat -I PREROUTING "$INSET_NU" -p tcp -j SHADOWSOCKS
```

**原因**：KOOLPROXY 需要先处理 HTTP 流量进行广告过滤，然后再由 SHADOWSOCKS 决定是否走代理。

---

### SHADOWSOCKS_EXT 链的作用（OUTPUT + KoolProxy 联动）

```bash
# OUTPUT 链中：路由器自身流量被 KoolProxy 标记后进入 SHADOWSOCKS_EXT
iptables -t nat -A OUTPUT -p tcp -m mark --mark "$ip_prefix_hex" -j SHADOWSOCKS_EXT
```

`ip_prefix_hex` 是 LAN 网段的十六进制 mark。KoolProxy 会对需要代理的流量打上此 mark，然后 SHADOWSOCKS_EXT 链按照与 SHADOWSOCKS 相同的逻辑进行分流。

---

### 访问控制（ACL）核心代码（行2523-2572）

```bash
lan_acess_control(){
    acl_nu=$(dbus list ss_acl_mode_ | cut -d "=" -f 1 | cut -d "_" -f 4 | sort -n)
    for acl in $acl_nu; do
        ipaddr=$(dbus get ss_acl_ip_$acl)
        ipaddr_hex=$(dbus get ss_acl_ip_$acl | awk -F "." '{printf ("0x%02x%02x%02x%02x\n", $1,$2,$3,$4)}')
        ports=$(dbus get ss_acl_port_$acl)
        proxy_mode=$(dbus get ss_acl_mode_$acl)

        # nat 表：按源IP分流到不同模式链
        iptables -t nat -A SHADOWSOCKS -s $ipaddr -p tcp \
            [-m multiport --dport $ports] \
            -$(get_jump_mode $proxy_mode) $(get_action_chain $proxy_mode)

        # OUTPUT 表（KP扩展）：按 mark 匹配
        iptables -t nat -A SHADOWSOCKS_EXT -p tcp \
            [-m multiport --dport $ports] \
            -m mark --mark "$ipaddr_hex" \
            -$(get_jump_mode $proxy_mode) $(get_action_chain $proxy_mode)

        # mangle 表：游戏模式主机走 TPROXY，其他主机 RETURN
        if [ "$proxy_mode" == "3" ]; then
            iptables -t mangle -A SHADOWSOCKS -s $ipaddr -p udp \
                [-m multiport --dport $ports] \
                -g SHADOWSOCKS_GAM
        else
            [ "$mangle" == "1" ] && \
            iptables -t mangle -A SHADOWSOCKS -s $ipaddr -p udp -j RETURN
        fi
    done

    # 剩余主机走默认模式
    iptables -t nat -A SHADOWSOCKS -p tcp \
        $(factor $ss_acl_default_port "-m multiport --dport") \
        -j $(get_action_chain $ss_acl_default_mode)
}
```

**ACL 数据结构**（dbus 存储）：
- `ss_acl_ip_1` = "192.168.1.100"
- `ss_acl_mode_1` = "1" (gfwlist)
- `ss_acl_port_1` = "all" 或 "80,443"
- `ss_acl_name_1` = "我的电脑"

---

### 完整 iptables 规则写入顺序总结

```
apply_nat_rules() 执行顺序：
│
├── 1. 创建链：SHADOWSOCKS, SHADOWSOCKS_EXT
├── 2. 白名单规则：white_list → RETURN（两条链都加）
├── 3. 创建模式链：GLO, GFW, CHN, GAM, HOM
├── 4. 填充模式链规则（各自的匹配逻辑）
├── 5. [条件] 加载 TPROXY 模块 + 策略路由
├── 6. [条件] 创建 mangle SHADOWSOCKS + GAM 链
├── 7. lan_acess_control()：写入 ACL 规则到三张表
├── 8. OUTPUT 链：router ipset + SHADOWSOCKS_EXT
├── 9. 默认规则：剩余流量 → 默认模式链
├── 10. [条件] mangle 剩余 UDP → GAM 链
├── 11. 挂载到 PREROUTING（nat: INSERT, mangle: APPEND）
└── 12. QoS 兼容处理
```

---

## 深入：iptables 表状态与完整规则链

### 插件运行时 iptables 完整状态快照

#### nat 表 - PREROUTING 链

```
Chain PREROUTING (policy ACCEPT)
 num  target              prot  source    destination
 1    SHADOWSOCKS_DNS_0   udp   anywhere  anywhere     udp dpt:53  (DNS劫持,仅br0)
 2    SHADOWSOCKS         tcp   anywhere  anywhere     (主入口,所有TCP)
 ...  [KOOLPROXY等其他插件规则]
```

> 插入位置：SHADOWSOCKS 在 KOOLPROXY 之后（INSET_NU = KP_NU + 1），确保与广告过滤插件兼容。

#### nat 表 - SHADOWSOCKS 链（主分流链）

```
Chain SHADOWSOCKS (1 references)
 num  target              prot  source       destination
 1    RETURN              tcp   anywhere     match-set white_list dst  (白名单直连)
 2    SHADOWSOCKS_GFW     tcp   192.168.1.100  anywhere  (ACL: 指定主机走gfwlist)
 3    SHADOWSOCKS_CHN     tcp   192.168.1.101  anywhere  (ACL: 指定主机走大陆白名单)
 4    RETURN              tcp   192.168.1.102  anywhere  (ACL: 指定主机不走代理)
 ...  [更多ACL规则]
 N    SHADOWSOCKS_CHN     tcp   anywhere     anywhere  multiport dports [端口] (剩余流量->默认模式)
```

#### nat 表 - 各模式子链

```
Chain SHADOWSOCKS_GFW (gfwlist模式)
 1    REDIRECT :3333    tcp   anywhere   match-set black_list dst   (黑名单强制走代理)
 2    REDIRECT :3333    tcp   anywhere   match-set gfwlist dst      (gfwlist匹配走代理)
 [不匹配则隐式RETURN=直连]

Chain SHADOWSOCKS_CHN (大陆白名单模式)
 1    REDIRECT :3333    tcp   anywhere   match-set black_list dst   (黑名单强制走代理)
 2    REDIRECT :3333    tcp   anywhere   ! match-set chnroute dst   (非中国IP走代理)
 [中国IP则隐式RETURN=直连]

Chain SHADOWSOCKS_GAM (游戏模式) - TCP规则同CHN
 1    REDIRECT :3333    tcp   anywhere   match-set black_list dst
 2    REDIRECT :3333    tcp   anywhere   ! match-set chnroute dst

Chain SHADOWSOCKS_GLO (全局模式)
 1    REDIRECT :3333    tcp   anywhere   anywhere                   (所有流量走代理)

Chain SHADOWSOCKS_HOM (回国模式)
 1    REDIRECT :3333    tcp   anywhere   match-set black_list dst   (黑名单走代理)
 2    REDIRECT :3333    tcp   anywhere   match-set chnroute dst     (中国IP走代理! 与CHN相反)
 [非中国IP则隐式RETURN=直连]
```

#### nat 表 - OUTPUT 链（路由器自身流量）

```
Chain OUTPUT (policy ACCEPT)
 1    REDIRECT :3333    tcp   anywhere   match-set router dst       (路由器自身需代理的目标)
 2    SHADOWSOCKS_EXT   tcp   anywhere   anywhere  mark match $ip_prefix_hex (KP标记流量)
```

#### nat 表 - DNS 劫持链（每个br接口一条）

```
Chain SHADOWSOCKS_DNS_0 (br0接口)
 1    DNAT to 192.168.1.1:53   udp   anywhere   anywhere           (强制DNS请求到路由器)
```

#### mangle 表 - SHADOWSOCKS 链（UDP游戏模式）

```
Chain SHADOWSOCKS (mangle, PREROUTING)
 1    RETURN            udp   anywhere   match-set white_list dst   (白名单直连)
 2    SHADOWSOCKS_GAM   udp   192.168.1.100  anywhere              (ACL: 游戏模式主机)
 3    RETURN            udp   192.168.1.101  anywhere              (ACL: 非游戏主机不走UDP代理)
 N    SHADOWSOCKS_GAM   udp   anywhere   anywhere                  (剩余UDP->游戏模式链)

Chain SHADOWSOCKS_GAM (mangle)
 1    TPROXY redirect :3333 mark 0x07   udp   anywhere   match-set black_list dst
 2    TPROXY redirect :3333 mark 0x07   udp   anywhere   ! match-set chnroute dst
```


---

### TPROXY UDP 转发机制（核心代码 ssconfig.sh 行2310-2337, 2618-2630）

```bash
# 1. 加载内核模块（行2310-2337）
load_tproxy(){
    MODULES="nf_tproxy_core xt_TPROXY xt_socket xt_comment"
    OS=$(uname -r)
    for MODULE in $MODULES; do
        insmod /lib/modules/${OS}/kernel/net/netfilter/${MODULE}.ko
    done
}

# 2. 策略路由配置（行2619-2620）
# 被标记 0x07 的包走路由表310，表310将所有流量送到本地回环
ip rule add fwmark 0x07 table 310
ip route add local 0.0.0.0/0 dev lo table 310

# 3. mangle TPROXY 规则（行2628-2630）
iptables -t mangle -A SHADOWSOCKS_GAM -p udp \
    -m set --match-set black_list dst \
    -j TPROXY --on-port 3333 --tproxy-mark 0x07
iptables -t mangle -A SHADOWSOCKS_GAM -p udp \
    -m set ! --match-set chnroute dst \
    -j TPROXY --on-port 3333 --tproxy-mark 0x07
```

**TPROXY原理**：与 nat REDIRECT 不同，TPROXY 不修改数据包的目标地址。通过策略路由将标记包送到本地 lo 接口，由监听 0.0.0.0:3333 的 xray（需开启 followRedirect: true）以透明代理方式处理 UDP 包，保留原始目标地址信息。

---

### QoS 兼容处理（核心代码 行2654-2659）

```bash
QOSO=$(iptables -t mangle -S | grep -o QOSO | wc -l)
RRULE=$(iptables -t mangle -S | grep "A QOSO" | head -n1 | grep RETURN)
if [ "$QOSO" -gt "1" ] && [ -z "$RRULE" ]; then
    # 在 QoS 链(QOSO0)头部插入 RETURN，防止代理流量被 QoS 重新标记
    iptables -t mangle -I QOSO0 -m mark --mark "$ip_prefix_hex" -j RETURN
fi
```

ip_prefix_hex = LAN网段十六进制（如 0xc0a80100/0xffffff00 = 192.168.1.0/24）

---

### flush_nat() 完整清理顺序（核心代码 行2340-2406）

```bash
flush_nat(){
    # === 第一步：从 PREROUTING 中删除跳转规则（倒序删除防止索引偏移）===
    nat_indexs=$(iptables -nvL PREROUTING -t nat | sed 1,2d | sed -n '/SHADOWSOCKS/=' | sort -r)
    for nat_index in $nat_indexs; do
        iptables -t nat -D PREROUTING $nat_index
    done

    # === 第二步：清空并删除所有自定义链 ===
    iptables -t nat -F SHADOWSOCKS && iptables -t nat -X SHADOWSOCKS
    iptables -t nat -F SHADOWSOCKS_EXT
    iptables -t nat -F SHADOWSOCKS_GFW && iptables -t nat -X SHADOWSOCKS_GFW
    iptables -t nat -F SHADOWSOCKS_CHN && iptables -t nat -X SHADOWSOCKS_CHN
    iptables -t nat -F SHADOWSOCKS_GAM && iptables -t nat -X SHADOWSOCKS_GAM
    iptables -t nat -F SHADOWSOCKS_GLO && iptables -t nat -X SHADOWSOCKS_GLO
    iptables -t nat -F SHADOWSOCKS_HOM && iptables -t nat -X SHADOWSOCKS_HOM

    # === 第三步：清理 mangle 表 ===
    mangle_indexs=$(iptables -nvL PREROUTING -t mangle | sed 1,2d | sed -n '/SHADOWSOCKS/=' | sort -r)
    for mangle_index in $mangle_indexs; do
        iptables -t mangle -D PREROUTING $mangle_index
    done
    iptables -t mangle -F SHADOWSOCKS && iptables -t mangle -X SHADOWSOCKS
    iptables -t mangle -F SHADOWSOCKS_GAM && iptables -t mangle -X SHADOWSOCKS_GAM

    # === 第四步：清理 OUTPUT 链 ===
    iptables -t nat -D OUTPUT -p tcp -m set --match-set router dst -j REDIRECT --to-ports 3333
    iptables -t nat -F OUTPUT
    iptables -t nat -X SHADOWSOCKS_EXT

    # === 第五步：清理 DNS 劫持链（按 VLAN 接口遍历）===
    VLAN_INDEXS=$(ifconfig | grep -E "^br" | awk '{print $1}' | sed 's/^br//g')
    for VLAN_INDEX in $VLAN_INDEXS; do
        iptables -t nat -F SHADOWSOCKS_DNS_${VLAN_INDEX} && iptables -t nat -X SHADOWSOCKS_DNS_${VLAN_INDEX}
    done

    # === 第六步：清理 QoS 兼容规则 ===
    iptables -t mangle -D QOSO0 -m mark --mark "$ip_prefix_hex" -j RETURN

    # === 第七步：销毁所有 ipset ===
    ipset -F chnroute && ipset -X chnroute
    ipset -F white_list && ipset -X white_list
    ipset -F black_list && ipset -X black_list
    ipset -F gfwlist && ipset -X gfwlist
    ipset -F router && ipset -X router

    # === 第八步：清理策略路由 ===
    ip_rule_exist=$(ip rule show | grep "lookup 310" | grep -c 310)
    until [ "$ip_rule_exist" = 0 ]; do
        IP_ARG=$(ip rule show | grep "lookup 310" | head -n 1 | cut -d " " -f3,4,5,6)
        ip rule del $IP_ARG
        ip_rule_exist=$(expr $ip_rule_exist - 1)
    done
    ip route del local 0.0.0.0/0 dev lo table 310
}
```


## Merlin 固件网络处理流程与插件集成

### Merlin 固件启动时序与插件触发点

```
路由器上电
  -> 内核启动 -> init -> 各系统服务启动
    -> WAN 接口获取IP (DHCP/PPPoE)
      -> 触发 /jffs/scripts/wan-start        <- 插件注入点1
        -> sh /koolshare/scripts/ss_config.sh
          -> ssconfig.sh start (完整启动流程)
    -> NAT 表初始化完成
      -> 触发 /jffs/scripts/nat-start        <- 插件注入点2
        -> sh /koolshare/ss/ssconfig.sh (加载NAT规则)
    -> dnsmasq 启动/重启
      -> 触发 /jffs/scripts/dnsmasq.postconf  <- 插件注入点3
        -> 修改 dnsmasq 配置(DNS上游/缓存)
```

### 三个关键 Merlin 钩子脚本

#### 1. `/jffs/scripts/wan-start`(WAN连接建立后)

```bash
#!/bin/sh
/usr/bin/onwanstart.sh          # Merlin 原生处理
sh /koolshare/scripts/ss_config.sh   # <- 插件注入(行986)
```

**触发时机**: WAN口获得IP后(开机/断线重连/PPPoE重拨)
**作用**: 启动所有代理进程(xray/ss-redir等) + DNS + 定时任务

#### 2. `/jffs/scripts/nat-start`(NAT表就绪后)

```bash
#!/bin/sh
/usr/bin/onnatstart.sh          # Merlin 原生处理
sh /koolshare/ss/ssconfig.sh    # <- 插件注入(行969)
```

**触发时机**: iptables nat 表初始化完成后(开机/防火墙重载)
**作用**: 重新加载 iptables 规则(因为防火墙重载会清空自定义规则)
**注意**: 此处调用 ssconfig.sh 无参数，走 `*)` 分支 = 完整 apply_ss

#### 3. `/jffs/scripts/dnsmasq.postconf`(dnsmasq配置后处理)

```bash
#!/bin/sh
# 软链接到 /koolshare/ss/rules/dnsmasq.postconf
# 参数 $1 = /etc/dnsmasq.conf 路径

# 根据模式修改 dnsmasq 全局 DNS 上游:
# - 国内优先模式: server=国内DNS#53 + no-resolv
# - 国外优先模式: server=127.0.0.1#7913 + no-resolv
# 同时设置 cache-size=9999
```

**触发时机**: 每次 dnsmasq 重启前(service restart_dnsmasq)
**作用**: 动态修改 /etc/dnsmasq.conf，设置 DNS 上游服务器
**核心函数**: pc_replace / pc_insert (来自 Merlin helper.sh)

---

### auto_start() 注入逻辑(核心代码 行954-989)

```bash
auto_start(){
    # === 注入 nat-start ===
    if [ ! -f /jffs/scripts/nat-start ]; then
        cat > /jffs/scripts/nat-start <<-EOF
            #!/bin/sh
            /usr/bin/onnatstart.sh
        EOF
    fi
    # 检查是否已注入，未注入则在第2行插入
    writenat=$(cat /jffs/scripts/nat-start | grep "ssconfig")
    if [ -z "$writenat" ]; then
        sed -i '2a sh /koolshare/ss/ssconfig.sh' /jffs/scripts/nat-start
        chmod +x /jffs/scripts/nat-start
    fi

    # === 注入 wan-start ===
    if [ ! -f /jffs/scripts/wan-start ]; then
        cat > /jffs/scripts/wan-start <<-EOF
            #!/bin/sh
            /usr/bin/onwanstart.sh
        EOF
    fi
    startss=$(cat /jffs/scripts/wan-start | grep "/koolshare/scripts/ss_config.sh")
    if [ -z "$startss" ]; then
        sed -i '2a sh /koolshare/scripts/ss_config.sh' /jffs/scripts/wan-start
    fi
    chmod +x /jffs/scripts/wan-start
}
```

---

### Merlin 固件网络栈与插件交互全景

```
                    +---------------------------------------------------+
                    |              Merlin 固件网络栈                      |
                    +---------------------------------------------------+

  [LAN设备] --TCP/UDP--> [br0 网桥接口]
                              |
                    +---------v------------+
                    |  netfilter PREROUTING |
                    |  (raw -> mangle -> nat)|
                    +---------+------------+
                              |
              +---------------+---------------+
              |                               |
     +--------v--------+            +--------v--------+
     | mangle表:        |            | nat表:           |
     | SHADOWSOCKS链    |            | SHADOWSOCKS链    |
     | (UDP TPROXY)    |            | (TCP REDIRECT)   |
     +--------+--------+            +--------+--------+
              |                               |
              | mark 0x07                      | REDIRECT :3333
              |                               |
     +--------v--------+            +--------v--------+
     | ip rule:         |            | 本地进程:         |
     | fwmark 0x07      |            | xray/ss-redir    |
     | -> table 310     |            | 监听 :3333       |
     | -> local loopback|            | (TCP透明代理)     |
     +--------+--------+            +--------+--------+
              |                               |
     +--------v--------+                      |
     | 本地进程:         |                      |
     | xray :3333       |                      |
     | (UDP TPROXY)    |                      |
     +--------+--------+                      |
              |                               |
              +---------------+---------------+
                              |
                    +---------v----------+
                    |  路由决策 (FORWARD)  |
                    |  或本地处理          |
                    +---------+----------+
                              |
                    +---------v----------+
                    |  netfilter OUTPUT   |  <- 路由器自身流量
                    |  (router ipset匹配) |
                    |  REDIRECT :3333    |
                    +---------+----------+
                              |
                    +---------v----------+
                    |  WAN 接口出站       |
                    |  -> 远程代理服务器   |
                    +--------------------+
```


---

### DNS 请求在 Merlin 中的完整路径

```
[LAN设备] --DNS(udp:53)--> [br0]
        |
        v
+-----------------------------------------------------------+
| iptables nat PREROUTING:                                   |
|   SHADOWSOCKS_DNS_0: -p udp --dport 53 -j DNAT -> 路由器IP:53 |
|   (DNS劫持: 强制所有DNS请求到路由器dnsmasq)                    |
+----------------------------+------------------------------+
                             v
+-----------------------------------------------------------+
| dnsmasq (:53)                                              |
|                                                            |
| 配置来源:                                                   |
|   /etc/dnsmasq.conf        <- dnsmasq.postconf 修改         |
|   /jffs/configs/dnsmasq.d/ <- 软链接目录                     |
|     +-- gfwlist.conf -> /koolshare/ss/rules/gfwlist.conf   |
|     +-- cdn.conf -> /tmp/sscdn.conf                        |
|     +-- wblist.conf -> /tmp/wblist.conf                    |
|     +-- custom.conf -> /tmp/custom.conf                    |
|     +-- ss_server.conf (服务器域名解析)                      |
|                                                            |
| 解析逻辑:                                                   |
|   1. wblist.conf 白名单域名 -> 国内DNS直连                    |
|   2. wblist.conf 黑名单域名 -> 127.0.0.1:7913(国外DNS)       |
|   3. gfwlist.conf 匹配 -> 127.0.0.1:7913 + ipset gfwlist   |
|   4. cdn.conf 匹配 -> 国内DNS(如119.29.29.29)               |
|   5. 默认上游 -> 取决于 dnsmasq.postconf 设置                 |
|      国内优先: server=国内DNS#53                              |
|      国外优先: server=127.0.0.1#7913                         |
+----------------------------+------------------------------+
                             |
          +------------------+------------------+
          v                                     v
+--------------------+              +--------------------+
| 国内DNS直连         |              | 127.0.0.1:7913     |
| (114/阿里/DNSPod)  |              | (防污染DNS端口)      |
|                    |              |                    |
| 返回国内CDN IP      |              | 实现方式(择一):      |
+--------------------+              |  dns2socks         |
                                    |  cdns              |
                                    |  chinadns          |
                                    |  ss-tunnel         |
                                    |  xray内置DNS       |
                                    |  smartdns          |
                                    |  https_dns_proxy   |
                                    +---------+----------+
                                              v
                                    +--------------------+
                                    | 通过代理隧道查询     |
                                    | 远程DNS(8.8.8.8)   |
                                    | 返回真实IP          |
                                    | + 写入ipset gfwlist |
                                    +--------------------+
```

---

### dnsmasq 与 ipset 联动机制

gfwlist.conf 中每条规则格式:
```
server=/.google.com/127.0.0.1#7913
ipset=/.google.com/gfwlist
```

**工作原理**:
1. 当 LAN 设备请求 www.google.com 时，dnsmasq 匹配 gfwlist.conf
2. DNS 查询转发到 127.0.0.1:7913 (防污染DNS) 获得真实IP
3. 同时将解析结果IP自动加入 ipset `gfwlist` 集合
4. 后续该设备访问此IP时，iptables 匹配 `match-set gfwlist dst` -> REDIRECT 到代理

这实现了**域名级别的动态分流**: 只有 gfwlist 中的域名对应的IP才走代理。

---

### Merlin 固件特有机制与插件适配

#### nvram 与 dbus(skipd) 双存储

| 存储 | 用途 | 持久性 |
|------|------|--------|
| nvram | 固件原生设置(wan0_dns, lan_ipaddr等) | 写入闪存，重启保留 |
| dbus (skipd) | 插件设置(ss_basic_*等) | /tmp/skipd 内存数据库，通过 jffs 持久化 |

```bash
# 读取固件设置
ISP_DNS1=$(nvram get wan0_dns | sed 's/ /\n/g' | sed -n 1p)
lan_ipaddr=$(nvram get lan_ipaddr)

# 读写插件设置
eval $(dbus export ss)              # 导出所有 ss_ 开头的变量
dbus set ss_basic_enable="1"        # 写入
dbus get ss_basic_server            # 读取
dbus list ss_acl_mode_              # 列出前缀匹配的所有键
dbus remove ss_basic_server_ip      # 删除
```

#### jffs2_scripts 依赖

插件依赖 Merlin 的 `Enable JFFS custom scripts and configs` 选项:
- `/jffs/scripts/` -- 自定义脚本目录(wan-start, nat-start 等)
- `/jffs/configs/dnsmasq.d/` -- dnsmasq 额外配置目录(自动加载)
- `/jffs/configs/dnsmasq.conf.add` -- dnsmasq 追加配置

#### helper.sh 工具函数

Merlin 提供的 `/usr/sbin/helper.sh` (或 `/koolshare/scripts/base.sh`):
```bash
source /koolshare/scripts/base.sh   # 加载基础环境
source helper.sh                     # Merlin helper

# 常用函数:
pc_replace "old" "new" $CONFIG      # 替换 dnsmasq.conf 中的配置
pc_insert "after_line" "new_line" "/etc/dnsmasq.conf"  # 在指定行后插入
base64_decode                        # Base64 解码(管道使用)
```

#### Merlin cru 定时任务

```bash
# cru = Merlin 封装的 crontab 管理工具
cru a ssupdate "15 4 * * * /bin/sh /koolshare/scripts/ss_rule_update.sh"
cru a ssnodeupdate "2 3 * * 1 /koolshare/scripts/ss_online_update.sh 3"
cru a ss_reboot "0 4 * * * /koolshare/ss/ssconfig.sh restart"
cru a ss_tri_check "*/10 * * * * /koolshare/scripts/ss_reboot_job.sh check_ip"
cru d ssupdate    # 删除任务
cru l             # 列出所有任务
```

#### service 命令

```bash
service restart_dnsmasq    # 重启 dnsmasq (触发 dnsmasq.postconf)
service restart_firewall   # 重启防火墙 (触发 nat-start)
```

---

### 插件与 Merlin 网络栈的生命周期交互

```
+-------------------------------------------------------------------+
|                    完整生命周期状态机                                |
+-------------------------------------------------------------------+

[路由器开机] --> [WAN就绪] --wan-start--> [ss_config.sh]
                                              |
                                    +---------v---------+
                                    |  ssconfig.sh start |
                                    |  (enable==1时)     |
                                    +---------+---------+
                                              |
                              +---------------+---------------+
                              v               v               v
                    [启动代理进程]     [配置DNS]        [等待NAT就绪]
                    xray/naive/hy2    dnsmasq配置       load_nat()
                              |               |         最多等120秒
                              |               |               |
                              +---------------+---------------+
                                              |
                                    +---------v---------+
                                    |  apply_nat_rules() |
                                    |  写入iptables      |
                                    +---------+---------+
                                              |
                                    +---------v---------+
                                    |  运行中 (RUNNING)   |
                                    +---------+---------+
                                              |
                    +-------------------------+-------------------------+
                    |                         |                         |
          [防火墙重载]              [WAN断线重连]              [用户操作/定时重启]
          nat-start触发             wan-start触发              Web UI / cron
                    |                         |                         |
                    v                         v                         v
          ssconfig.sh (无参数)      ss_config.sh              ssconfig.sh restart
          = 完整 apply_ss          -> ssconfig.sh restart     = 完整 apply_ss
          (先stop再start)          (先stop再start)            (先stop再start)
                    |                         |                         |
                    +-------------------------+-------------------------+
                                              |
                                    +---------v---------+
                                    |  运行中 (RUNNING)   |
                                    +---------+---------+
                                              |
                                    [用户关闭 / 卸载]
                                              |
                                    +---------v---------+
                                    |  ssconfig.sh stop  |
                                    |  disable_ss()      |
                                    +---------+---------+
                                              |
                              +---------------+---------------+
                              v               v               v
                    [kill所有进程]    [清理iptables]    [恢复dnsmasq]
                    kill_process()   flush_nat()      restore_conf()
                                                     restart_dnsmasq()
                              |               |               |
                              +---------------+---------------+
                                              |
                                    +---------v---------+
                                    |  已停止 (STOPPED)   |
                                    +-------------------+
```

---

### load_nat() 等待机制(核心代码 行2792-2810)

```bash
load_nat(){
    # 等待 NAT 表就绪(最多120秒)
    # 原因: wan-start 触发时 NAT 可能尚未完全初始化
    nat_ready=$(iptables -t nat -L PREROUTING -v -n --line-numbers | grep -v PREROUTING | grep -v destination)
    i=120
    until [ -n "$nat_ready" ]; do
        i=$(($i-1))
        if [ "$i" -lt 1 ]; then
            echo_date "错误：不能正确加载nat规则!"
            close_in_five
        fi
        sleep 1
        nat_ready=$(iptables -t nat -L PREROUTING -v -n --line-numbers | grep -v PREROUTING | grep -v destination)
    done
    echo_date "加载nat规则!"
    add_white_black_ip    # 填充 ipset 黑白名单
    apply_nat_rules       # 写入 iptables 规则
    chromecast            # DNS 劫持规则
}
```

---

### 文件锁机制(防止并发冲突)

```bash
LOCK_FILE=/var/lock/koolss.lock

set_lock(){
    exec 1000>"$LOCK_FILE"    # 打开文件描述符1000
    flock -x 1000             # 获取排他锁(阻塞等待)
}

unset_lock(){
    flock -u 1000             # 释放锁
    rm -rf "$LOCK_FILE"       # 删除锁文件
}
```

**场景**: 防止 nat-start 和 wan-start 同时触发导致规则写入冲突。

---

### Merlin 固件 dnsmasq 替换机制

插件可选用 dnsmasq-fastlookup 替换原版 dnsmasq (处理4万+条 cdn.conf 时性能更好):

```bash
mount_dnsmasq(){
    killall dnsmasq
    mount --bind /koolshare/bin/dnsmasq /usr/sbin/dnsmasq   # bind mount 覆盖
}

umount_dnsmasq(){
    killall dnsmasq
    umount /usr/sbin/dnsmasq    # 恢复原版
}
```

**策略** (ss_basic_dnsmasq_fastlookup):
- 0 = 始终用原版
- 1 = 始终用 fastlookup
- 2 = 自动(有 cdn.conf 时用 fastlookup)
- 3 = 始终用 fastlookup 且关闭插件后保持

---

### KoolProxy 兼容(广告过滤插件)

```bash
# 检测 KOOLPROXY 在 PREROUTING 中的位置
KP_NU=$(iptables -nvL PREROUTING -t nat | sed 1,2d | sed -n '/KOOLPROXY/=' | head -n1)
[ "$KP_NU" == "" ] && KP_NU=0
INSET_NU=$(expr "$KP_NU" + 1)

# 在 KOOLPROXY 之后插入 SHADOWSOCKS (确保广告过滤先执行)
iptables -t nat -I PREROUTING "$INSET_NU" -p tcp -j SHADOWSOCKS
```

**原因**: KOOLPROXY 需要先处理 HTTP 流量进行广告过滤，然后再由 SHADOWSOCKS 决定是否走代理。

---

### 访问控制(ACL)核心代码(行2523-2572)

```bash
lan_acess_control(){
    acl_nu=$(dbus list ss_acl_mode_ | cut -d "=" -f 1 | cut -d "_" -f 4 | sort -n)
    for acl in $acl_nu; do
        ipaddr=$(dbus get ss_acl_ip_$acl)
        ipaddr_hex=$(dbus get ss_acl_ip_$acl | awk -F "." \
            '{printf ("0x%02x%02x%02x%02x\n", $1,$2,$3,$4)}')
        ports=$(dbus get ss_acl_port_$acl)
        proxy_mode=$(dbus get ss_acl_mode_$acl)

        # nat 表: 按源IP分流到不同模式链
        iptables -t nat -A SHADOWSOCKS -s $ipaddr -p tcp \
            [-m multiport --dport $ports] \
            -$(get_jump_mode $proxy_mode) $(get_action_chain $proxy_mode)

        # OUTPUT 表(KP扩展): 按 mark 匹配
        iptables -t nat -A SHADOWSOCKS_EXT -p tcp \
            [-m multiport --dport $ports] \
            -m mark --mark "$ipaddr_hex" \
            -$(get_jump_mode $proxy_mode) $(get_action_chain $proxy_mode)

        # mangle 表: 游戏模式主机走 TPROXY，其他主机 RETURN
        if [ "$proxy_mode" == "3" ]; then
            iptables -t mangle -A SHADOWSOCKS -s $ipaddr -p udp \
                [-m multiport --dport $ports] -g SHADOWSOCKS_GAM
        else
            [ "$mangle" == "1" ] && \
            iptables -t mangle -A SHADOWSOCKS -s $ipaddr -p udp -j RETURN
        fi
    done

    # 剩余主机走默认模式
    iptables -t nat -A SHADOWSOCKS -p tcp \
        $(factor $ss_acl_default_port "-m multiport --dport") \
        -j $(get_action_chain $ss_acl_default_mode)
}
```

**ACL 数据结构** (dbus 存储):
- `ss_acl_ip_1` = "192.168.1.100"
- `ss_acl_mode_1` = "1" (gfwlist)
- `ss_acl_port_1` = "all" 或 "80,443"
- `ss_acl_name_1` = "我的电脑"

---

### 完整 iptables 规则写入顺序总结

```
apply_nat_rules() 执行顺序:
|
+-- 1. 创建链: SHADOWSOCKS, SHADOWSOCKS_EXT
+-- 2. 白名单规则: white_list -> RETURN (两条链都加)
+-- 3. 创建模式链: GLO, GFW, CHN, GAM, HOM
+-- 4. 填充模式链规则(各自的匹配逻辑)
+-- 5. [条件] 加载 TPROXY 模块 + 策略路由
+-- 6. [条件] 创建 mangle SHADOWSOCKS + GAM 链
+-- 7. lan_acess_control(): 写入 ACL 规则到三张表
+-- 8. OUTPUT 链: router ipset + SHADOWSOCKS_EXT
+-- 9. 默认规则: 剩余流量 -> 默认模式链
+-- 10. [条件] mangle 剩余 UDP -> GAM 链
+-- 11. 挂载到 PREROUTING (nat: INSERT, mangle: APPEND)
+-- 12. QoS 兼容处理
```
