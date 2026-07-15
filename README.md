# Shadowsocks ONLY on koolshare Merlin 380 ARM （安全，好用）
This project will update bin and package for [**fancyss_arm380**](https://github.com/hq450/fancyss_history_package/tree/master/legacy/fancyss_arm380)    

add and support new features  
fixed many historical legacy issues  

除插件原有功能外，另外

* 支持 xray, vless, xtls vision, reality, trojan, trojan-go, NaiveProxy, Hysteria2, AnyTLS 等协议及更新，
* 支持 ss2022，
* 支持多个 xray 节点聚合，负载平衡，
* 支持混合节点订阅，
* 支持同时订阅多个链接，回车隔开，
* 支持ss:// vless:// trojan:// trojan-go:// hysteria2:// hy2:// anytls:// 格式订阅和导入，
* 支持smartDNS (不熟悉配置请勿选择)，ChinaDNS-NG
* 支持在线更新

目前 xray 完全替代了 v2ray，trojan-go，xray 支持 vmess，vless，trojan，trojan-go ws 和 ss2022。

NaiveProxy 使用下来也还不错，延迟很低，速度也很快。
Hysteria2 目前是最稳定，速度也是最快的。 

离线安装包仅能在 koolshare 梅林 arm 380 平台，且 linux 内核为 2.6.36.4 的 armv7 架构的机器上使用！

**离线安装包**支持机型（需刷 koolshare 梅林**380**改版固件，最新版本：X7.9.1）：

* 华硕系列：`RT-AC56U` `RT-AC68U` `RT-AC66U-B1` `RT-AC1900P` `RT-AC87U` `RT-AC88U` `RT-AC3100` `RT-AC3200` `RT-AC5300`
* 网件系列：`R6300V2` `R6400` `R6900` `R7000` `R8000` `R8500`
* linksys EA系列：`EA6200` `EA6400` `EA6500v2` `EA6700` `EA6900`
* 华为：`ws880`

---

## 本分支（v2ray_bin_lite）变更

本分支在原 [cary-sas/v2ray_bin](https://github.com/cary-sas/v2ray_bin) 基础上，聚焦大陆白名单场景做了如下调整（上文功能列表描述的是插件底层能力，本分支在界面上对部分入口做了精简，以下为准）：

### 代理链路修复
修复大陆白名单模式下部分境外网站（尤其 Google / YouTube 等 HTTP/3 站点）加载不出、不走代理的问题：

* **境外 QUIC 泄漏防护**：未开启 UDP 代理时，丢弃境外 QUIC（UDP/443）首包，强制浏览器回退 TCP 走代理；
* **IPv6 泄漏防护**：白名单模式且启用 IPv6 时，拒绝 IPv6 直连转发，强制回退到受透明代理接管的 IPv4。

### UDP / QUIC 分流（全局设定 →「同步 UDP 与 TCP」）
原开关由「开/关」升级为三档：

* **关闭**：UDP 不走代理（默认）；
* **仅代理 QUIC（低负载，推荐）**：只把 QUIC（UDP/443）按 chnroute 分流走代理，其余 UDP（BT、视频、游戏等）一律直连，兼顾 HTTP/3 站点可用与路由器负载；
* **全量 UDP（高负载）**：所有 UDP 按 chnroute 分流走代理；
* 存在游戏模式主机、或主模式为游戏模式时，自动回退为全量 UDP。

### 界面精简
* 移除「KCP 加速」「UDP 加速」入口；
* 「更新管理」移除「节点订阅设置」「通过链接添加服务器」入口；
* 「添加节点」移除「SSR」「koolgame」「Naive」入口（存量节点仍可正常编辑）。

### 更新源
* 插件自动更新指向本分支仓库 [guijianchou/v2ray_bin_lite](https://github.com/guijianchou/v2ray_bin_lite)；
* 二进制（xray / hysteria / naive 等）更新仍沿用原仓库 [cary-sas/v2ray_bin](https://github.com/cary-sas/v2ray_bin)。

