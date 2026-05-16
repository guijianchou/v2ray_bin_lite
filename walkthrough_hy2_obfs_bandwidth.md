# Walkthrough Plan: HY2 添加 obfs + bandwidth 支持

## 目标

为 Hysteria2 协议添加以下能力：
1. **obfs** (salamander 混淆) — `obfs.type` + `obfs.salamander.password`
2. **bandwidth** (带宽声明) — `bandwidth.up` + `bandwidth.down`
3. **Web UI** — 主页面和节点编辑面板增加对应输入框

---

## 涉及文件清单

| 文件 | 改动类型 | 说明 |
|------|----------|------|
| `shadowsocks/ss/ssconfig.sh` | 修改 | `create_hy2_json()` 增加 obfs/bandwidth 块 |
| `shadowsocks/scripts/ss_webtest.sh` | 修改 | `create_hy2_json()` 同步增加 obfs/bandwidth |
| `shadowsocks/webs/Main_Ss_Content.asp` | 修改 | 增加 HTML 表单行 + JS 显隐逻辑 + params 数组 |

---

## Step 1: ssconfig.sh — 修改 `create_hy2_json()`

**位置**: 行 2127-2155

**当前代码**:
```bash
create_hy2_json(){
    rm -f "$HY2_CONFIG_FILE"
    if [ "$ss_basic_type" == "4" ] && [ "$ss_basic_trojan_binary" == "Hysteria2" ]; then
        echo_date 生成Hysteria2配置文件...
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
        echo_date Hysteria2 配置文件写入成功到 "$HY2_CONFIG_FILE"
    fi
}
```

**目标代码**:
```bash
create_hy2_json(){
    rm -f "$HY2_CONFIG_FILE"
    if [ "$ss_basic_type" == "4" ] && [ "$ss_basic_trojan_binary" == "Hysteria2" ]; then
        echo_date 生成Hysteria2配置文件...

        # 构建 obfs 块
        local obfs_block=""
        if [ -n "$ss_basic_hy2_obfs_type" ] && [ "$ss_basic_hy2_obfs_type" != "none" ]; then
            obfs_block='"obfs": {"type": "'$ss_basic_hy2_obfs_type'", "'$ss_basic_hy2_obfs_type'": {"password": "'$ss_basic_hy2_obfs_password'"}},'
        fi

        # 构建 bandwidth 块
        local bw_block=""
        if [ -n "$ss_basic_hy2_up_mbps" ] && [ -n "$ss_basic_hy2_down_mbps" ]; then
            bw_block='"bandwidth": {"up": "'$ss_basic_hy2_up_mbps' mbps", "down": "'$ss_basic_hy2_down_mbps' mbps"},'
        fi

        cat >"$HY2_CONFIG_FILE" <<-EOF
            {
                "server": "$(dbus get ss_basic_server):$ss_basic_port",
                "auth": "${ss_basic_password}",
                "tls": {
                    "sni": "$ss_basic_trojan_sni",
                    "insecure": $(get_function_switch $ss_basic_allowinsecure)
                },
                ${obfs_block}
                ${bw_block}
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

        # 用 jq 格式化并验证 JSON
        local validated=$(cat "$HY2_CONFIG_FILE" | jq . 2>/dev/null)
        if [ -n "$validated" ]; then
            echo "$validated" > "$HY2_CONFIG_FILE"
            echo_date Hysteria2 配置文件写入成功到 "$HY2_CONFIG_FILE"
        else
            echo_date "Hysteria2 配置文件 JSON 格式错误！请检查设置！"
            close_in_five
        fi
    fi
}
```

**关键点**:
- `obfs_block` 和 `bw_block` 为空时不输出任何内容（heredoc 中空变量展开为空行，jq 格式化后会消除）
- 最后用 jq 验证+格式化，确保 JSON 合法
- 变量来源：`eval $(dbus export ss)` 已在脚本头部执行，所以 `ss_basic_hy2_*` 自动可用

---

## Step 2: ss_webtest.sh — 同步修改测速配置

**位置**: `create_hy2_json()` 行 587-605

**目标代码**:
```bash
create_hy2_json(){
    rm -f /tmp/tmp_hysteria.json

    # 读取节点的 obfs 和 bandwidth
    local obfs_type=$(eval echo \$ssconf_basic_hy2_obfs_type_$nu)
    local obfs_pass=$(eval echo \$ssconf_basic_hy2_obfs_password_$nu)
    local up_mbps=$(eval echo \$ssconf_basic_hy2_up_mbps_$nu)
    local down_mbps=$(eval echo \$ssconf_basic_hy2_down_mbps_$nu)

    local obfs_block=""
    if [ -n "$obfs_type" ] && [ "$obfs_type" != "none" ]; then
        obfs_block='"obfs": {"type": "'$obfs_type'", "'$obfs_type'": {"password": "'$obfs_pass'"}},'
    fi

    local bw_block=""
    if [ -n "$up_mbps" ] && [ -n "$down_mbps" ]; then
        bw_block='"bandwidth": {"up": "'$up_mbps' mbps", "down": "'$down_mbps' mbps"},'
    fi

    cat >/tmp/tmp_hysteria.json <<-EOF
        {
            "server": "${array1}:${array2}",
            "auth": "${array3}",
            "tls": {
                "sni": "$(eval echo \$ssconf_basic_trojan_sni_$nu)",
                "insecure": $(get_function_switch $(eval echo \$ssconf_basic_allowinsecure_$nu))
            },
            ${obfs_block}
            ${bw_block}
            "fastOpen": true,
            "lazy": true,
            "socks5": {
                "listen": "127.0.0.1:23458"
            }
        }
    EOF
}
```

---

## Step 3: Main_Ss_Content.asp — Web UI 修改

### 3.1 新增 HTML 表单行

**位置**: 在 `allowinsecure_basic_tr` 附近（主页面节点设置区域），找到 Hysteria2 相关的 `<tr>` 块，在其后插入：

```html
<tr id="hy2_obfs_type_basic_tr" style="display:none;">
    <th width="35%">HY2 混淆类型</th>
    <td>
        <select id="ss_basic_hy2_obfs_type" name="ss_basic_hy2_obfs_type" style="width:170px;" onchange="update_visibility();">
            <option value="">不启用</option>
            <option value="salamander">salamander</option>
        </select>
    </td>
</tr>
<tr id="hy2_obfs_password_basic_tr" style="display:none;">
    <th width="35%">HY2 混淆密码</th>
    <td>
        <input type="text" id="ss_basic_hy2_obfs_password" name="ss_basic_hy2_obfs_password" class="input_ss_table" style="width:170px;" value="">
    </td>
</tr>
<tr id="hy2_up_mbps_basic_tr" style="display:none;">
    <th width="35%">HY2 上行带宽(Mbps)</th>
    <td>
        <input type="text" id="ss_basic_hy2_up_mbps" name="ss_basic_hy2_up_mbps" class="input_ss_table" style="width:100px;" value="" placeholder="如: 50">
        <span style="color:#888;">留空则使用BBR</span>
    </td>
</tr>
<tr id="hy2_down_mbps_basic_tr" style="display:none;">
    <th width="35%">HY2 下行带宽(Mbps)</th>
    <td>
        <input type="text" id="ss_basic_hy2_down_mbps" name="ss_basic_hy2_down_mbps" class="input_ss_table" style="width:100px;" value="" placeholder="如: 200">
        <span style="color:#888;">留空则使用BBR</span>
    </td>
</tr>
```

同样在**节点编辑弹窗**中（搜索 `ss_node_table_trojan_sni` 附近）添加对应字段：

```html
<tr id="hy2_obfs_type_tr" style="display:none;">
    <th width="35%">HY2 混淆类型</th>
    <td>
        <select id="ss_node_table_hy2_obfs_type" style="width:170px;">
            <option value="">不启用</option>
            <option value="salamander">salamander</option>
        </select>
    </td>
</tr>
<tr id="hy2_obfs_password_tr" style="display:none;">
    <th width="35%">HY2 混淆密码</th>
    <td>
        <input type="text" id="ss_node_table_hy2_obfs_password" class="input_ss_table" style="width:170px;" value="">
    </td>
</tr>
<tr id="hy2_up_mbps_tr" style="display:none;">
    <th width="35%">HY2 上行带宽(Mbps)</th>
    <td>
        <input type="text" id="ss_node_table_hy2_up_mbps" class="input_ss_table" style="width:100px;" value="">
    </td>
</tr>
<tr id="hy2_down_mbps_tr" style="display:none;">
    <th width="35%">HY2 下行带宽(Mbps)</th>
    <td>
        <input type="text" id="ss_node_table_hy2_down_mbps" class="input_ss_table" style="width:100px;" value="">
    </td>
</tr>
```

### 3.2 修改 JS params 数组

**位置**: `params_input` 数组（行259）末尾追加：
```javascript
"ss_basic_hy2_obfs_type", "ss_basic_hy2_obfs_password", "ss_basic_hy2_up_mbps", "ss_basic_hy2_down_mbps"
```

**位置**: `params` 数组（行360）追加：
```javascript
"hy2_obfs_type", "hy2_obfs_password", "hy2_up_mbps", "hy2_down_mbps"
```

**位置**: `params2` 数组（行920）追加：
```javascript
"hy2_obfs_type", "hy2_obfs_password", "hy2_up_mbps", "hy2_down_mbps"
```

### 3.3 修改 JS 显隐逻辑

**位置**: `update_visibility()` 函数中（约行641），在 `//trojan Hysteria2` 注释块内追加：

```javascript
// HY2 专属字段：仅 Hysteria2 时显示
var hy2_on = (trojan_on && E("ss_basic_trojan_binary").value == "Hysteria2");
showhide("hy2_obfs_type_basic_tr", hy2_on);
showhide("hy2_obfs_password_basic_tr", (hy2_on && E("ss_basic_hy2_obfs_type").value != ""));
showhide("hy2_up_mbps_basic_tr", hy2_on);
showhide("hy2_down_mbps_basic_tr", hy2_on);
```

**位置**: 节点编辑弹窗的显隐逻辑（约行671），在 `Hysteria2` 分支内追加：

```javascript
} else if (E("ss_node_table_trojan_binary").value == "Hysteria2") {
    E('allowinsecure_tr').style.display = "";
    E('hy2_obfs_type_tr').style.display = "";
    E('hy2_obfs_password_tr').style.display = "";
    E('hy2_up_mbps_tr').style.display = "";
    E('hy2_down_mbps_tr').style.display = "";
}
```

### 3.4 修改节点加载逻辑

在 `ss_node_sel()` 中加载 Hysteria2 节点时（约行936-942附近），追加读取新字段：

```javascript
if (trojan_binary == "Hysteria2") {
    obj["ss_basic_hy2_obfs_type"] = db_ss["ssconf_basic_hy2_obfs_type_" + node_sel] || "";
    obj["ss_basic_hy2_obfs_password"] = db_ss["ssconf_basic_hy2_obfs_password_" + node_sel] || "";
    obj["ss_basic_hy2_up_mbps"] = db_ss["ssconf_basic_hy2_up_mbps_" + node_sel] || "";
    obj["ss_basic_hy2_down_mbps"] = db_ss["ssconf_basic_hy2_down_mbps_" + node_sel] || "";
}
```

### 3.5 修改节点保存逻辑

在 `save()` 函数中，当 `trojan_binary == "Hysteria2"` 时，将新字段写入提交对象：

```javascript
if (trojan_binary == "Hysteria2") {
    obj["ss_basic_hy2_obfs_type"] = E("ss_basic_hy2_obfs_type").value;
    obj["ss_basic_hy2_obfs_password"] = E("ss_basic_hy2_obfs_password").value;
    obj["ss_basic_hy2_up_mbps"] = E("ss_basic_hy2_up_mbps").value;
    obj["ss_basic_hy2_down_mbps"] = E("ss_basic_hy2_down_mbps").value;
}
```

同时在节点编辑保存（`edit_ss_node_conf` / `add_ss_node_conf`）中追加：

```javascript
if (E("ss_node_table_trojan_binary").value == "Hysteria2") {
    push_data("ssconf_basic_hy2_obfs_type_" + idx, E("ss_node_table_hy2_obfs_type").value);
    push_data("ssconf_basic_hy2_obfs_password_" + idx, E("ss_node_table_hy2_obfs_password").value);
    push_data("ssconf_basic_hy2_up_mbps_" + idx, E("ss_node_table_hy2_up_mbps").value);
    push_data("ssconf_basic_hy2_down_mbps_" + idx, E("ss_node_table_hy2_down_mbps").value);
}
```

---

## 验证清单

### 配置生成验证

```bash
# 设置测试值
dbus set ss_basic_type=4
dbus set ss_basic_trojan_binary=Hysteria2
dbus set ss_basic_server=test.example.com
dbus set ss_basic_port=443
dbus set ss_basic_password=mypassword
dbus set ss_basic_trojan_sni=test.example.com
dbus set ss_basic_allowinsecure=0
dbus set ss_basic_hy2_obfs_type=salamander
dbus set ss_basic_hy2_obfs_password=obfs-secret
dbus set ss_basic_hy2_up_mbps=50
dbus set ss_basic_hy2_down_mbps=200

# 执行生成
eval $(dbus export ss)
source /koolshare/ss/ssconfig.sh
create_hy2_json

# 检查输出
cat /koolshare/ss/hysteria.json | jq .
```

期望输出：
```json
{
  "server": "test.example.com:443",
  "auth": "mypassword",
  "tls": {
    "sni": "test.example.com",
    "insecure": false
  },
  "obfs": {
    "type": "salamander",
    "salamander": {
      "password": "obfs-secret"
    }
  },
  "bandwidth": {
    "up": "50 mbps",
    "down": "200 mbps"
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

### 无 obfs/bandwidth 时验证（向后兼容）

```bash
dbus remove ss_basic_hy2_obfs_type
dbus remove ss_basic_hy2_obfs_password
dbus remove ss_basic_hy2_up_mbps
dbus remove ss_basic_hy2_down_mbps
```

期望：JSON 中不包含 `obfs` 和 `bandwidth` 块，回退到 BBR 拥塞控制。

### Web UI 验证

1. 打开主页面，选择一个 Hysteria2 节点
2. 确认显示"HY2 混淆类型"、"HY2 混淆密码"、"HY2 上行带宽"、"HY2 下行带宽"
3. 混淆类型选"不启用"时，混淆密码行隐藏
4. 切换到其他协议（Trojan/Xray），确认四个字段隐藏
5. 填入值后保存，确认 dbus 写入正确
6. 重新加载页面，确认值回显正确

### 端到端验证

```bash
# 启动插件
sh /koolshare/ss/ssconfig.sh restart

# 确认进程
pidof hysteria

# 确认配置
cat /koolshare/ss/hysteria.json | jq .obfs
cat /koolshare/ss/hysteria.json | jq .bandwidth

# 确认连通性
curl --socks5 127.0.0.1:23456 https://www.google.com -o /dev/null -w "%{http_code}"
```

---

## 执行顺序

1. **ssconfig.sh** — 核心配置生成，命令行直接测试
2. **ss_webtest.sh** — 测速配置同步
3. **Main_Ss_Content.asp** — Web UI，浏览器验证

每步独立可验证，不依赖后续步骤。

---

## 风险点

| 风险 | 缓解 |
|------|------|
| heredoc 中变量为空导致多余逗号 | jq 格式化验证，空块不输出 |
| 旧节点没有新字段 | 变量为空时不生成对应 JSON 块，向后兼容 |
| Web UI 字段未正确隐藏 | showhide 逻辑绑定 `trojan_binary == "Hysteria2"` |
| dbus key 命名冲突 | 使用 `hy2_` 前缀，不复用 SSR 的 `rss_obfs` |
| obfs_password 含特殊字符(引号等) | JSON 中直接拼接可能破坏格式，jq 验证兜底 |

---

## dbus 字段总结

| dbus 键 | 用途 | 默认值 |
|---------|------|--------|
| `ss_basic_hy2_obfs_type` | 混淆类型 | 空(不启用) |
| `ss_basic_hy2_obfs_password` | 混淆密码 | 空 |
| `ss_basic_hy2_up_mbps` | 上行带宽(纯数字) | 空(用BBR) |
| `ss_basic_hy2_down_mbps` | 下行带宽(纯数字) | 空(用BBR) |
| `ssconf_basic_hy2_obfs_type_<n>` | 节点级混淆类型 | 空 |
| `ssconf_basic_hy2_obfs_password_<n>` | 节点级混淆密码 | 空 |
| `ssconf_basic_hy2_up_mbps_<n>` | 节点级上行 | 空 |
| `ssconf_basic_hy2_down_mbps_<n>` | 节点级下行 | 空 |
