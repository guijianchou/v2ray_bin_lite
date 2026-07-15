# swap 插件维护文档

> 给 koolshare 梅林路由器用 USB 磁盘扩展虚拟内存的插件。本文档记录插件逻辑与本次维护（v1.8 → v1.9）的全部变更，供后续维护参考。

## 一、插件概述

在 U 盘（ext2/3/4 分区）上创建一个 `swapfile` 并 `swapon`，为路由器扩展虚拟内存，缓解物理内存不足。典型使用场景：跑 shadowsocks 全家桶（xray / dns2socks / smartdns 等）、aria2、游戏加速时防 OOM。

**目标运行环境**（据实机确认）：

| 项 | 值 |
|---|---|
| 固件 | koolshare 梅林 380.63_X7.2 |
| CPU | ARMv7 (Cortex-A9) 双核 |
| 物理内存 | 约 249 MB |
| 内核 | 2.6.36.4 |
| Shell | busybox ash（支持 `local`、`==`、`$$`） |
| U 盘挂载点 | `/tmp/mnt/<卷标>` |
| 开机钩子 | `/jffs/scripts/post-mount`（**全插件共享**） |

当前版本：**1.9**

## 二、文件结构

```
swap/
├── install.sh              安装：拷贝文件、chmod、复制 uninstall 到 scripts、清理旧版死文件
├── uninstall.sh            卸载：守卫式 swapoff → 删文件 → 清 post-mount → dbus remove
├── res/icon-swap.png       软件中心图标
├── scripts/
│   ├── swap_check.sh        → sh /koolshare/swap/swap.sh check   （Web「检测状态」入口）
│   ├── swap_load.sh         → sh /koolshare/swap/swap.sh load    （Web「创建」入口 + 开机钩子调用）
│   └── swap_unload.sh       → sh /koolshare/swap/swap.sh unload  （Web「删除」入口）
├── swap/swap.sh            主逻辑（唯一有实际逻辑的脚本）
└── webs/Module_swap.asp    Web UI
```

三个 `scripts/swap_*.sh` 只是薄封装,把 Web 的 `SystemCmd` 转发到主脚本的对应 `ACTION`。真正的逻辑全在 [`swap/swap.sh`](swap/swap/swap.sh)。

## 三、核心逻辑

### 3.1 状态码（`swap_warnning`）

主脚本用一个状态码驱动 UI 显示,存在 skipd（dbus key `swap_warnning`),UI 每 2 秒轮询 `dbconf?p=swap_` 读取:

| 码 | 含义 | UI 表现 |
|---|---|---|
| 1 | 没有找到可用的 USB 磁盘 | 提示插盘,隐藏创建按钮 |
| 2 | U 盘格式不符合要求（非 ext） | 提示格式错误 |
| 3 | 检测到 ext 磁盘,可创建 | 显示「创建」按钮 + 容量下拉 |
| 4 | swap 已加载 | 显示使用率 + 「删除」按钮 |
| 5 | swapoff 失败,内存不足无法安全卸载 | 橙字提示先关占内存应用再重试 |
| 6 | 磁盘剩余空间不足,无法创建 | 橙字提示清理磁盘或选更小容量 |
| 7 | swap 已加载,但未开启 JFFS 脚本 | 橙字提示去系统设置开启,否则重启不自动挂载 |

状态码与 UI 分支一一对应,见 [`Module_swap.asp` 的 `write_usb_status()`](swap/webs/Module_swap.asp)。

### 3.2 四个动作（`case $ACTION`）

| ACTION | 触发来源 | 做什么 |
|---|---|---|
| `start` | 预留 | 仅 `check_usb_status` 刷新状态 |
| `check` | Web 打开页面(`init`) | `check_usb_status`;有 swapfile 未挂载时顺带 swapon 兜底;**不注册开机项** |
| `load` | Web 点「创建」/ 开机 post-mount | `check_usb_status` → `create_swap` → swap 挂载成功才 `swap_load_start` 注册开机项 |
| `unload` | Web 点「删除」 | 守卫式 `swapoff`,成功才删文件、清开机项;失败置状态 5 保留文件 |

### 3.3 关键函数（都在 swap.sh）

- **`set_state <码>`** — 同时更新 shell 变量 `$swap_warnning` **和** dbus。这是 v1.9 的核心修复：`dbus set` 不会改变当前 shell 变量,而 `create_swap` 靠 `$swap_warnning` 判断是否执行,两者必须同步,否则创建会读到脚本启动时的过期值而失效。**后续任何状态变更都必须走 `set_state`,不要裸写 `dbus set swap_warnning`。**

- **`find_usb_disk`** — 遍历 `/bin/mount` 里 `/tmp/mnt/` 下的挂载点,**优先选 ext2/3/4 分区**（多分区 U 盘第一个是 NTFS 也能找对);找不到 ext 时取第一个挂载点用于报「格式不符」。busybox 管道属子 shell、变量不回传,故用临时文件 `/tmp/swap_disk.$$` 中转。结果写入 shell 变量 `$usb_disk` / `$ext_type` 及 dbus。

- **`create_swap`**（原名 `mkswap`,改名避免与系统 `/sbin/mkswap` 混淆）— 仅在状态 3 时执行:按 `swap_size`（1/2/3 → 256/512/1024 MB,未设兜底 512）算块数 → `df -k` 检查剩余空间(预留 10 MB)不足则状态 6 → `dd bs=1M` 创建(失败清理残файл并报 6)→ `sync` → `mkswap` → `chmod 0600` → `swapon`。

- **`swap_load_start`** — 向 `post-mount` **只追加不覆盖**:文件不存在才建带 shebang 的新文件;`grep -q swap_load` 查重;**追加前 `tail -c1` 判断末尾有无换行**,无则先补一个,避免与已有插件的最后一行拼接成一条命令。

- **`swap_unload_start`** — `sed -i '/swap_load/d'` 从 post-mount 删除本插件的开机行,不动其它行。

### 3.4 开机自动挂载链路

```
路由器启动
  → U 盘挂载触发 /jffs/scripts/post-mount
    → sh /koolshare/scripts/swap_load.sh
      → sh /koolshare/swap/swap.sh load
        → check_usb_status（找到 swapfile → swapon）
        → create_swap（已挂载则跳过）
        → swap_load_start（grep 查重,已存在则不重复写）
```

**前提**:必须开启「系统管理 → 系统设置 → Enable JFFS custom scripts and configs」,否则 post-mount 不执行,开机不自动挂载（对应状态码 7 的提示）。

### 3.5 数据流

```
UI 选容量/点按钮 → form 提交 applydb.cgi?p=swap_ → 存入 skipd(dbus)
                → SystemCmd 触发 scripts/swap_*.sh → swap.sh <action>
swap.sh 内部    → dbus export swap（启动时导入 swap_* 为 shell 变量）
                → set_state 写回 swap_warnning
UI 轮询 dbconf?p=swap_ 每 2s 读 swap_warnning/swap_usb_* → 刷新界面
```

## 四、本次维护变更（v1.8 → v1.9）

### 第一轮（结合环境的初次修复）

**P0 — 数据/其它插件安全**
- **post-mount 覆盖 → 只追加**:原逻辑在「文件存在但无 swap_load 行」时用 `echo >` **整文件覆盖**,会清掉 entware / 其它 koolshare 插件写的开机项。改为查重后 `>>` 追加。
- **unload 无守卫的 `rm -rf`**:`$usb_disk` 为空时会变成 `rm -rf /swapfile`;且 `swapoff` 失败仍无条件删文件,会把正被内核使用的 swap 删成无名 inode(空间到重启才释放,U 盘凭空少 1G)。改为全程 `[ -n ] && [ -f ]` 守卫 + **swapoff 成功才删**,失败置状态 5 保留文件。

**P1 — 正确性/性能**
- **256M 档 `256144` 笔误** → dd 改 `bs=1M count=256`,尺寸精确(旧值实际只有 250 MB)。
- **`dd bs=1024` 太慢** → 改 `bs=1M` + `sync`,USB2 + 单核上快约一个数量级,与 UI 进度条时间对得上,避免"进度显示完成但后台还在写"。
- **`mkswap` 存在性检查查错文件**(`/swap` vs `/swapfile`) → 修正为检查 `swapfile` 本身;损坏的 swapfile 走「重新格式化」自愈。
- **`check` 动作也注册开机项** → 拆分:仅 `load` 成功后注册,`check` 只读状态。避免"只打开过页面没创建 swap"就写入开机项。
- **缺 jffs2_scripts 检测** → 已挂载但该选项未开时置状态 7,UI 提示去开启。
- **dd 前不查剩余空间** → `df -k` 检查(预留 10 MB),不足置状态 6。
- **磁盘探测 `grep mnt | sed 1p` 太粗** → 统一为 `find_usb_disk()`,精确匹配 `/tmp/mnt/` 且**优先 ext 分区**,全部变量加引号(防带空格卷标断词),三处调用共用。

**P2 — 清理**
- 删除死文件 `swap_startup.sh`(无人引用,且含 `swapswapfile` 拼写 bug)。
- 新增 `uninstall.sh`(守卫式 swapoff → 删文件 → 清 post-mount → `dbus remove`)。
- `install.sh` 补 chmod webs/res、复制 uninstall 到 scripts、清理旧版死文件。
- UI 默认选中「512M 推荐」,`init()` 调 `conf2obj()` 回填已存容量。

### 第二轮（对抗性复审,修上一轮遗留）

- **Bug A — 状态 shell/dbus 不同步**:`create_swap` 读 shell 变量 `$swap_warnning`,而 `check_usb_status` 只 `dbus set`,导致创建判断用过期值。→ 引入 `set_state()` 双写,状态更新全部走它。
- **Bug B — `echo >>` 与无换行末行拼接**:已有 post-mount 末尾无换行时,追加会连成一行破坏命令。→ 追加前 `tail -c1` 补换行。
- **优化 C — 移除 `swappiness=30`**:重启不持久(走 check 的 swapon 路径不经过设置点),且此内存紧张场景 swap 是防 OOM 兜底,不该抑制换出。→ 保持内核默认 60。
- 附带:dd 失败清理残余文件;`mkswap()` 改名 `create_swap()`;`Module_swap.asp` 由 CRLF 统一为 LF。

## 五、与 shadowsocks 共存

- **swappiness 保持默认 60**:swap 在此就是给 shadowsocks 重负载 + aria2/游戏加速做防 OOM 兜底,压低反而更易触发 dnsmasq/xray 被 OOM kill。
- **默认 512M**:249 MB 物理 + 512 MB swap ≈ 761 MB 虚拟内存,覆盖全家桶峰值又不过度占盘。
- **post-mount 互不干扰**:shadowsocks 主要用 nat-start 等钩子,swap 用 post-mount;即便共用 post-mount,swap 也是查重追加、删除时只删自己那行。
- **卸载守卫**:swap 用满时点删除,swapoff 成功才删、失败保留并提示,避免内存紧张时删掉内核在用的 swapfile 或触发 OOM 杀掉代理进程。

## 六、存量 swap 兼容

插件认**固定路径 `<U盘挂载点>/swapfile`**,检测到就直接 `swapon`,不校验大小、不重建。所以已有的 swap:

- 文件名就是 `swapfile` 且在 U 盘根目录 → 插件直接接管,显示「已挂载」,无需删除重建。
- 文件名是别的 → 插件会显示「可创建」,**此时别点创建**(会在同盘再 dd 一个,两份叠加占空间)。正确做法是改名而非重建:
  ```sh
  swapoff /tmp/mnt/xxx/旧名
  mv /tmp/mnt/xxx/旧名 /tmp/mnt/xxx/swapfile
  ```

## 七、已知限制 / 风险

- **swapoff 可能阻塞**:内存不足时 `swapoff` 会阻塞较久(内核尝试换回页面),UI 只等 5 秒。脚本会等它自然返回,失败置状态 5。busybox 无可靠 `timeout`,未加超时。
- **单盘假设**:`find_usb_disk` 取第一个 ext 分区。多个 ext U 盘时选第一个,未做盘选择。
- **路径写死 `swapfile`**:见第六节。
- **卷标含空格/中文**:变量已加引号可容忍,但仍建议用英文卷标。
- **NTFS 显示为 `fuseblk`**:ntfs-3g 挂载在 mount 里 fs 字段是 `fuseblk`,会正确落入「格式不符」(状态 2)。

## 八、打包 / 安装 / 卸载

**打包**（在仓库根目录,git bash / Linux）:
```sh
tar -czf swap.tar.gz swap/
```
顶层须为 `swap/`,与 koolshare 软件中心离线安装包格式一致。改脚本后务必:
```sh
for f in $(find swap -name '*.sh'); do sh -n "$f" || echo "FAIL $f"; done   # 语法
grep -rlU $'\r' swap/                                                        # CRLF 必须为空
```
**shell 脚本必须 LF**,CRLF 会让 busybox 报 `\r` 错误。

**安装**:软件中心 → 离线安装 → 上传 `swap.tar.gz`。

**卸载**:软件中心卸载会调 `uninstall.sh`,自动 swapoff、删文件、清开机项、清 dbus 数据。

## 九、维护约定

- 改脚本只用 busybox ash 支持的语法;测试判断用 `==`（本环境 busybox 接受）。
- 任何状态变更走 `set_state`,不裸写 `dbus set swap_warnning`。
- 动 `post-mount` 只增删自己那一行,永不覆盖整文件。
- 涉及 `rm` / `swapoff` 前先 `[ -n "$var" ]` 守卫,`swapoff` 判返回值再删。
- 提交前跑 `sh -n` + CRLF 检查;改 asp 的 `<script>` 后可用 esprima(剔除 `<% %>` 后)校验 JS。
- 版本号在 [`swap/swap/swap.sh`](swap/swap/swap.sh) 顶部 `version=` 与 UI「当前版本」联动,发布新版记得同步。
