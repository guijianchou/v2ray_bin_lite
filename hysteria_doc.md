# Hysteria2 ARMv7 客户端能力参考 (Merlin 插件专用)

更新日期：2026-05-16

本文只面向 Merlin/Koolshare ARM380 路由器 (Linux ARMv7/armv7l 内核 2.6.36.4)，用于确认 Hysteria2 官方客户端在该平台上支持哪些参数。不讨论 x86/macOS/Windows/Android/ARMv5。

官方文档：
- Full Client Config: https://v2.hysteria.network/docs/advanced/Full-Client-Config/
- Getting Started Client: https://v2.hysteria.network/docs/getting-started/Client/
- URI Scheme: https://hysteria.network/docs/developers/URI-Scheme/

---

## 1. ARMv7 二进制

官方 Release 中 Linux ARMv7 对应文件：

```
hysteria-linux-armv7
```

下载地址（以 v2.8.2 为例）：
```
https://github.com/apernet/hysteria/releases/download/app%2Fv2.8.2/hysteria-linux-armv7
```

或使用官方 CDN：
```
https://download.hysteria.network/app/latest/hysteria-linux-armv7
```

> **重要**：当前仓库 `380_armv5/hysteria/` 目录下存放的是 `hysteria-linux-arm`（ARMv5/通用ARM），在 ARMv7 路由器上可以运行但非最优。如果官方提供了 `hysteria-linux-armv7` 则应优先使用，性能更好。

验证命令：
```bash
file /koolshare/bin/hysteria        # 应显示 ARM, EABI5 或 ELF 32-bit LSB
/koolshare/bin/hysteria version     # 确认版本号
uname -m                            # 应为 armv7l
```

启动环境变量（Merlin 2.6.36 内核兼容性）：
```bash
export QUIC_GO_DISABLE_ECN=true     # 禁用 ECN，老内核不支持
```

---

## 2. 配置格式

Hysteria2 支持 YAML / JSON / TOML 三种格式。当前插件使用 JSON，完全可行。

启动命令：
```bash
# 官方标准写法
hysteria client -c /koolshare/ss/hysteria.json

# 当前插件写法（等效，旧版兼容）
hysteria -c /koolshare/ss/hysteria.json -l error --disable-update-check
```

---

## 3. 完整客户端参数矩阵 (ARMv7 适用)

以下基于官方 Full Client Config 整理，标注对 Merlin 透明代理插件的实用性。

### 3.1 顶层参数

| 参数 | 类型 | 说明 | 插件状态 | 优先级 |
|------|------|------|----------|--------|
| `server` | string | 服务器地址 `host:port` 或 `host:port1,port2,port3-port5`(端口跳跃) | 已支持 | 必须 |
| `auth` | string | 鉴权密码/token | 已支持 | 必须 |
| `tls` | object | TLS 设置 | 部分支持 | 必须 |
| `obfs` | object | 协议混淆 | **未支持** | 高 |
| `bandwidth` | object | 带宽声明(决定拥塞控制) | **未支持** | 高 |
| `transport` | object | 传输层(端口跳跃间隔) | 未支持 | 中 |
| `quic` | object | QUIC 参数 | 未支持 | 低 |
| `fastOpen` | bool | QUIC 0-RTT | 已支持(固定true) | 可选 |
| `lazy` | bool | 延迟建连 | 已支持(固定true) | 可选 |
| `socks5` | object | SOCKS5 入站 | 已支持 | 必须 |
| `http` | object | HTTP 代理入站 | 不需要 | 低 |
| `tcpRedirect` | object | TCP REDIRECT 透明代理 | 已支持 | 必须 |
| `udpTProxy` | object | UDP TPROXY 透明代理 | **未支持** | 高 |
| `tcpTProxy` | object | TCP TPROXY | 不需要 | 低 |
| `tun` | object | TUN 模式 | 不需要 | 低 |
| `tcpForwarding` | list | TCP 端口转发 | 不需要 | 低 |
| `udpForwarding` | list | UDP 端口转发 | 不需要 | 低 |

### 3.2 TLS 参数 (`tls.*`)

| 参数 | 类型 | 说明 | 插件状态 | 优先级 |
|------|------|------|----------|--------|
| `sni` | string | TLS ServerName | 已支持 (`ss_basic_trojan_sni`) | 必须 |
| `insecure` | bool | 跳过证书验证 | 已支持 (`ss_basic_allowinsecure`) | 必须 |
| `pinSHA256` | string | 证书指纹 pin (SHA-256) | 未支持 | 高 |
| `ca` | string | 自定义 CA 证书路径 | 未支持 | 低 |
| `clientCertificate` | string | 客户端证书 | 未支持 | 低 |
| `clientKey` | string | 客户端私钥 | 未支持 | 低 |

### 3.3 Obfs 参数 (`obfs.*`)

当前唯一支持的混淆类型是 `salamander`。

| 参数 | 类型 | 说明 | 优先级 |
|------|------|------|--------|
| `obfs.type` | string | 混淆类型，目前只有 `salamander` | 高 |
| `obfs.salamander.password` | string | Salamander 混淆密码 | 高 |

JSON 示例：
```json
"obfs": {
  "type": "salamander",
  "salamander": {
    "password": "your-obfs-password"
  }
}
```

生成规则：`type` 为空或不存在时，整个 `obfs` 块不写入。

### 3.4 Bandwidth 参数 (`bandwidth.*`)

控制拥塞算法选择：有 bandwidth 则用 Brutal CC，无则用 BBR。

| 参数 | 类型 | 说明 | 优先级 |
|------|------|------|--------|
| `bandwidth.up` | string | 上行带宽，格式 `"数字 mbps"` | 高 |
| `bandwidth.down` | string | 下行带宽，格式 `"数字 mbps"` | 高 |

JSON 示例：
```json
"bandwidth": {
  "up": "20 mbps",
  "down": "100 mbps"
}
```

> 如果不设置 bandwidth，Hysteria 会使用 BBR 拥塞控制（不需要声明带宽）。对于不确定带宽的用户，不写此字段即可。

### 3.5 Transport 参数 (`transport.*`)

主要用于端口跳跃场景。

| 参数 | 类型 | 说明 | 优先级 |
|------|------|------|--------|
| `transport.type` | string | 传输类型（默认 udp） | 低 |
| `transport.udp.hopInterval` | string | 端口跳跃间隔，如 `"30s"` | 中 |

> 端口跳跃需要 `server` 字段包含多端口：`server: "example.com:5000,6000,7000-8000"`

### 3.6 QUIC 参数 (`quic.*`)

| 参数 | 类型 | 说明 | 优先级 |
|------|------|------|--------|
| `quic.initStreamReceiveWindow` | int | 初始流接收窗口 | 低 |
| `quic.maxStreamReceiveWindow` | int | 最大流接收窗口 | 低 |
| `quic.initConnReceiveWindow` | int | 初始连接接收窗口 | 低 |
| `quic.maxConnReceiveWindow` | int | 最大连接接收窗口 | 低 |
| `quic.maxIdleTimeout` | string | 最大空闲超时 | 可选 |
| `quic.keepAlivePeriod` | string | KeepAlive 周期 | 可选 |
| `quic.disablePathMTUDiscovery` | bool | 禁用 PMTUD | 可选 |

> ARMv7 路由器建议：一般不需要调整。如遇连接不稳定可尝试 `disablePathMTUDiscovery: true`。

### 3.7 本地入站参数

#### SOCKS5 (`socks5.*`)

| 参数 | 类型 | 当前值 |
|------|------|--------|
| `socks5.listen` | string | `"127.0.0.1:23456"` |
| `socks5.username` | string | 不使用 |
| `socks5.password` | string | 不使用 |
| `socks5.disableUDP` | bool | 默认 false |

#### TCP REDIRECT (`tcpRedirect.*`)

| 参数 | 类型 | 当前值 |
|------|------|--------|
| `tcpRedirect.listen` | string | `"0.0.0.0:3333"` |

#### UDP TPROXY (`udpTProxy.*`) — 当前缺失

| 参数 | 类型 | 建议值 |
|------|------|--------|
| `udpTProxy.listen` | string | `"0.0.0.0:3333"` |
| `udpTProxy.timeout` | string | `"60s"` (可选) |

> **关键缺口**：当前插件 iptables mangle 表已经有 TPROXY 规则将 UDP 送到 :3333，但 Hysteria 配置中没有 `udpTProxy` 监听，导致游戏模式/UDP同步下 UDP 流量无法被 Hysteria 处理。

---

## 4. URI Scheme (订阅/导入)

官方支持两种前缀（等效）：
```
hysteria2://auth@host:port?key=value#name
hy2://auth@host:port?key=value#name
```

### URI 可表达的参数

| URI 参数 | 对应配置字段 | 说明 |
|----------|-------------|------|
| userinfo (auth) | `auth` | @前面的部分 |
| host | `server` 的 host | 域名或IP |
| port | `server` 的 port | 端口号 |
| `sni` | `tls.sni` | TLS ServerName |
| `insecure` | `tls.insecure` | 值为 `1` 时跳过验证 |
| `pinSHA256` | `tls.pinSHA256` | 证书 pin |
| `obfs` | `obfs.type` | 混淆类型 |
| `obfs-password` | `obfs.salamander.password` | 混淆密码 |
| fragment `#name` | 节点名称 | URL fragment |

### URI 不能表达的参数（需插件默认值补齐）

- `bandwidth` (up/down)
- `socks5` / `tcpRedirect` / `udpTProxy` (本地入站)
- `fastOpen` / `lazy`
- `transport` / `quic` 高级参数

当前插件只识别 `hysteria2://`，建议同时支持 `hy2://`。

---

## 5. 当前插件 vs 官方能力差异

| 能力 | 官方 | 插件现状 | 动作 |
|------|------|----------|------|
| ARMv7 二进制 | `hysteria-linux-armv7` | 使用通用 arm 版 | 可升级为 armv7 专用 |
| `obfs` (salamander) | 支持 | 不支持 | **需新增** |
| `bandwidth` (up/down) | 支持 | 不支持 | **需新增** |
| `udpTProxy` | 支持 | 不支持 | **需新增**(游戏模式关键) |
| `tls.pinSHA256` | 支持 | 不支持 | 建议新增 |
| `transport.hopInterval` | 支持 | 不支持 | 端口跳跃时需要 |
| `hy2://` URI | 支持 | 不支持 | 建议新增 |
| `fastOpen`/`lazy` 可配置 | 支持 | 固定 true | 可改为可配置 |
| `quic.*` 高级参数 | 支持 | 不支持 | 低优先级 |

---

## 6. 推荐 JSON 模板

### 最小配置（当前插件基线）

```json
{
  "server": "example.com:443",
  "auth": "your-password",
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

### 完整配置（目标状态）

```json
{
  "server": "example.com:443",
  "auth": "your-password",
  "tls": {
    "sni": "example.com",
    "insecure": false,
    "pinSHA256": "BA:AB:CD:..."
  },
  "obfs": {
    "type": "salamander",
    "salamander": {
      "password": "obfs-pass"
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

### 生成逻辑（伪代码）

```bash
create_hy2_json(){
  # 基础字段（必须）
  server="$(dbus get ss_basic_server):$ss_basic_port"
  auth="$ss_basic_password"
  sni="${ss_basic_hy2_sni:-$ss_basic_trojan_sni}"
  insecure=$(get_function_switch ${ss_basic_hy2_insecure:-$ss_basic_allowinsecure})

  # obfs（有值才写）
  if [ -n "$ss_basic_hy2_obfs_type" ] && [ "$ss_basic_hy2_obfs_type" != "none" ]; then
    obfs_block='"obfs":{"type":"'$ss_basic_hy2_obfs_type'","salamander":{"password":"'$ss_basic_hy2_obfs_password'"}}'
  fi

  # bandwidth（有值才写）
  if [ -n "$ss_basic_hy2_up_mbps" ] && [ -n "$ss_basic_hy2_down_mbps" ]; then
    bw_block='"bandwidth":{"up":"'$ss_basic_hy2_up_mbps' mbps","down":"'$ss_basic_hy2_down_mbps' mbps"}'
  fi

  # udpTProxy（游戏模式/UDP同步时写入）
  if [ "$mangle" == "1" ]; then
    udp_block='"udpTProxy":{"listen":"0.0.0.0:3333","timeout":"60s"}'
  fi

  # 组装 JSON ...
}
```

---

## 7. 建议新增的 dbus 字段

### 高优先级

| dbus 键 | 用途 | 默认值 |
|---------|------|--------|
| `ss_basic_hy2_obfs_type` | 混淆类型 | 空(不启用) |
| `ss_basic_hy2_obfs_password` | 混淆密码 | 空 |
| `ss_basic_hy2_up_mbps` | 上行带宽(数字) | 空(用BBR) |
| `ss_basic_hy2_down_mbps` | 下行带宽(数字) | 空(用BBR) |
| `ss_basic_hy2_pin_sha256` | 证书 pin | 空 |

### 订阅节点字段

| dbus 键 | 用途 |
|---------|------|
| `ssconf_basic_hy2_obfs_type_<n>` | 节点混淆类型 |
| `ssconf_basic_hy2_obfs_password_<n>` | 节点混淆密码 |
| `ssconf_basic_hy2_up_mbps_<n>` | 节点上行 |
| `ssconf_basic_hy2_down_mbps_<n>` | 节点下行 |
| `ssconf_basic_hy2_pin_sha256_<n>` | 节点证书pin |

### 兼容策略

- `ss_basic_hy2_sni` 为空时 fallback 到 `ss_basic_trojan_sni`
- `ss_basic_hy2_insecure` 为空时 fallback 到 `ss_basic_allowinsecure`
- 不复用 SSR 的 `ss_basic_rss_obfs`（语义完全不同）

---

## 8. 实机验证清单

```bash
# 1. 确认架构
uname -m                                    # armv7l

# 2. 确认二进制
file /koolshare/bin/hysteria                # ELF 32-bit LSB, ARM
/koolshare/bin/hysteria version             # 版本号

# 3. 确认配置有效
/koolshare/bin/hysteria client -c /koolshare/ss/hysteria.json --log-level debug --disable-update-check

# 4. 确认监听端口
netstat -nlp | grep hysteria
# 应看到: tcp 0.0.0.0:3333, udp 0.0.0.0:3333(如有udpTProxy), tcp 127.0.0.1:23456

# 5. 确认 iptables 配套
iptables-save -t nat | grep 3333            # TCP REDIRECT
iptables-save -t mangle | grep TPROXY       # UDP TPROXY (游戏模式)
ip rule show | grep 310                     # 策略路由
ip route show table 310                     # local 0.0.0.0/0 dev lo

# 6. 功能测试
curl --socks5 127.0.0.1:23456 https://www.google.com   # SOCKS5
# LAN 设备访问外网验证透明代理
```
