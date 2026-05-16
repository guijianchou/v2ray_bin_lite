# Shadowsocks ONLY on koolshare Merlin 380 ARM （安全，好用）
This project will update bin and package for [**fancyss_arm380**](https://github.com/hq450/fancyss_history_package/tree/master/legacy/fancyss_arm380)    

add and support new features  
fixed many historical legacy issues  

除插件原有功能外，另外

* 支持 xray, vless, xtls vision, reality, trojan, trojan-go, NaiveProxy, Hysteria2 等协议及更新，
* 支持 ss2022，
* 支持多个 xray 节点聚合，负载平衡，
* 支持混合节点订阅，
* 支持同时订阅多个链接，回车隔开，
* 支持ss:// vless:// trojan:// trojan-go:// hysteria2:// 格式订阅和导入，
* 支持smartDNS (不熟悉配置请勿选择)，ChinaDNS-NG
* 支持在线更新

## Requirements / 运行与打包环境

本仓库主要是 Koolshare/Merlin 380 ARM 插件包和预编译二进制归档，不是完整源码工程。正常魔改 `shadowsocks/` 目录时，重点是 Web ASP 页面写 dbus、后端 Shell 脚本读取 dbus 并调用预编译二进制；不需要准备完整交叉编译环境。

只有在你准备自己重编译 `ss-local`、`ss-redir`、`ss-tunnel`、`xray`、`hysteria` 等核心二进制时，才需要额外处理工具链。单纯修改 Web、Shell、规则、订阅解析、iptables/DNS 流程，只需要能打包和在目标 Merlin 环境验证。

### 目标运行环境

* 固件：koolshare 梅林 380 ARM 改版固件，软件中心可用。
* 架构：`armv7l`，内核约束沿用原包说明，主要面向 Linux `2.6.36.4`。
* 固件版本：安装脚本要求 `extendno` 解析后的版本不低于 `X7.2`。
* 路由器运行依赖：`/koolshare` 目录、`dbus`、`nvram`、`cru`、`iptables`、`ipset`、`dnsmasq`、`service`、`mount/umount`、BusyBox 常用命令。
* 插件安装包结构必须保持 `shadowsocks/bin`、`shadowsocks/scripts`、`shadowsocks/webs`、`shadowsocks/res`、`shadowsocks/ss` 和根部 `install.sh`、`uninstall.sh`。

### 开发主机基础工具

推荐使用 Linux 或 WSL2 做最终打包，主要是为了保留执行权限和 LF 换行。Windows/PowerShell 适合阅读和编辑，但最终发布前最好在 Linux/WSL2 或目标路由器环境复核。

Ubuntu/Debian 打包和静态检查常用依赖：

```bash
sudo apt-get update
sudo apt-get install -y tar gzip coreutils findutils sed gawk grep file
```

如果系统没有单独的 `md5sum` 包，通常它已经由 `coreutils` 提供。

### 插件打包工具链

插件打包脚本是 `shadowsocks/scripts/ss_pack.sh`。它不是从当前 Git 工作目录打包，而是假设插件已经安装在路由器或固件 staging 环境的 `/koolshare` 下，然后复制：

* `/koolshare/bin` 中的代理/DNS/辅助二进制；
* `/koolshare/scripts/ss_*` 和安装、卸载脚本；
* `/koolshare/webs/Main_Ss*.asp`；
* `/koolshare/res` 中的 UI 资源；
* `/koolshare/ss` 中的主控脚本、规则、版本和模板。

输出文件为 `/tmp/shadowsocks.tar.gz`。打包前需要确认脚本可执行位、Shell 文件 LF 换行、运行时生成的 `*.json` 已清理，且 `install.sh` 能在目标固件上通过 `uname -m` 和固件版本检查。

如果当前仓库里的 `shadowsocks/` 已经是准备发布的完整插件目录，也可以直接在仓库根目录打包：

```bash
tar --exclude='shadowsocks/ss/*.json' -czf shadowsocks.tar.gz shadowsocks/
tar -tzf shadowsocks.tar.gz | head
```

直接打包后，压缩包解开必须是 `shadowsocks/install.sh`、`shadowsocks/uninstall.sh`、`shadowsocks/bin/*`、`shadowsocks/scripts/*`、`shadowsocks/webs/*`、`shadowsocks/res/*`、`shadowsocks/ss/*` 这一层结构，不能多套一层父目录。这个方式只包含当前仓库文件；如果路由器上的 `/koolshare` 已经通过在线更新替换过核心、规则或用户脚本，则应先同步回来，或改用 `ss_pack.sh` 从实际安装环境反打包。

不要在普通开发机上直接执行 `install.sh`、`uninstall.sh` 或 `ss_pack.sh`，这些脚本会读写 `/koolshare`、`/jffs/scripts`、`/tmp`、dbus、iptables 和 dnsmasq。

### 可选：shadowsocks-libev 交叉编译

这一节不是普通打包要求。只有你要自己重编译 shadowsocks-libev 核心时才需要看；如果只是魔改插件 Web 壳、dbus 字段、shell 调用、DNS/NAT 规则，可以跳过。

仓库只保留了 shadowsocks-libev 的交叉编译脚本：

* `380_armv5/shadowsocks-libev/v3.3.6/cross_and_static_compile_shadowsocks-libev.sh`
* `380_armv5/shadowsocks-libev/v3.3.5/cross_and_static_compile_shadowsocks-libev.sh`

必须提前准备并加入 `PATH` 的工具链命令：

```bash
arm-uclibc-linux-2.6.36-gcc
arm-uclibc-linux-2.6.36-g++
arm-uclibc-linux-2.6.36-ar
arm-uclibc-linux-2.6.36-ranlib
arm-uclibc-linux-2.6.36-strip
```

`v3.3.6` 脚本会下载或拉取 `pcre2`、`mbedtls`、`libsodium`、`libev`、`c-ares` 和 `shadowsocks-libev`，使用 `cmake`、`make`、`git`、`wget`、`tar`、`sed`、`getconf` 完成静态编译。默认输出在脚本目录的 `dists/shadowsocks-libev/bin/`，主要产物是：

* `ss-local`
* `ss-redir`
* `ss-tunnel`
* `ss-server`，当前插件安装包通常不需要这个文件。

替换插件运行核心时，把需要的二进制复制到 `shadowsocks/bin/`，保持文件名和执行权限一致，再重新打包。

### Xray / V2Ray / Trojan-Go / NaiveProxy / Hysteria 二进制更新

`380_armv5/` 目录是在线更新使用的二进制归档源，通常放置上游已经编译好的 ARMv5/ARM 兼容二进制，本仓库不包含这些核心的完整源码编译流程。每个核心目录应维护：

* `latest.txt`：当前最新版本号；
* `v<version>/<binary>`：实际二进制；
* `v<version>/md5sum.txt`：在线更新脚本校验使用。

二进制压缩沿用 `380_armv5/readme.md` 的 UPX 方案：

```bash
upx-ucl --lzma --ultra-brute <binary>
upx -9 <binary>
upx --best <binary>
```

如果新版 UPX 压缩后的文件在 380 固件上运行异常，优先回退到 UPX 3.94。仓库内 `.github/workflows/update-hysteria.yml` 也固定使用 Ubuntu 22.04、`curl`、`xz-utils`、`jq`、`ca-certificates`、`file` 和 UPX 3.94 来下载、压缩、生成 `md5sum.txt` 并提交 Hysteria ARMv5 二进制。

### 打包后校验

建议每次发布前至少检查：

```bash
tar -tzf shadowsocks.tar.gz
md5sum shadowsocks.tar.gz
find shadowsocks -type f -name "*.sh" -exec sh -n {} \;
```

最终仍需要在目标 Merlin 380 路由器或等价测试环境验证安装、启动、停止和重启流程，并观察：

```bash
dbus list ss
ps | grep -E "ss-|xray|trojan|naive|hysteria|dns|haproxy"
iptables-save
ipset save
cru l
```

目前 xray 完全替代了 v2ray，xray 支持 vmess，vless，trojan 和 ss2022。

NaiveProxy 使用下来也还不错，延迟很低，速度也很快。

离线安装包仅能在 koolshare 梅林 arm 380 平台，且 linux 内核为 2.6.36.4 的 armv7 架构的机器上使用！

**离线安装包**支持机型（需刷 koolshare 梅林**380**改版固件，最新版本：X7.9.1）：

* 华硕系列：`RT-AC56U` `RT-AC68U` `RT-AC66U-B1` `RT-AC1900P` `RT-AC87U` `RT-AC88U` `RT-AC3100` `RT-AC3200` `RT-AC5300`
* 网件系列：`R6300V2` `R6400` `R6900` `R7000` `R8000` `R8500`
* linksys EA系列：`EA6200` `EA6400` `EA6500v2` `EA6700` `EA6900`
* 华为：`ws880`

