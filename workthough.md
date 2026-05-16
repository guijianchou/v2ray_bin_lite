# HY2 Obfs And Bandwidth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为主目录 `shadowsocks` 插件包的 Hysteria2/HY2 增加 `obfs`、`obfs-password`、上行 `up`、下行 `download/down` 支持，并在 Web 端提供完整新增、编辑、保存、回显接口。

**Architecture:** 保持现有兼容模型：HY2 仍然是 `ss_basic_type=4` + `ss_basic_trojan_binary=Hysteria2`，不新增协议大类。新增参数单独落在 `hy2_*` dbus 字段，Web、节点库、订阅、正式运行 JSON、测速 JSON 使用同一字段语义。运行配置使用 `jq -n` 生成，避免 heredoc 手写 JSON 时被密码、SNI、obfs-password 中的引号或反斜杠破坏。

**Tech Stack:** Merlin/Koolshare ASP + JavaScript、dbus/skipd、POSIX shell、jq、Hysteria2 JSON client config、现有 iptables/DNS 链路。

---

## Scope

本计划只针对主目录 `shadowsocks`，不是 `v2ray_bin-main/shadowsocks`。

本阶段必须完成：

- Web 主运行节点支持 `ss_basic_hy2_obfs_type`、`ss_basic_hy2_obfs_password`、`ss_basic_hy2_up_mbps`、`ss_basic_hy2_down_mbps`。
- 节点库支持 `ssconf_basic_hy2_obfs_type_<n>`、`ssconf_basic_hy2_obfs_password_<n>`、`ssconf_basic_hy2_up_mbps_<n>`、`ssconf_basic_hy2_down_mbps_<n>`。
- `create_hy2_json()` 输出官方 Hysteria2 客户端字段：

```json
"obfs": {
  "type": "salamander",
  "salamander": {
    "password": "..."
  }
},
"bandwidth": {
  "up": "20 mbps",
  "down": "100 mbps"
}
```

- `ss_webtest.sh` 测速临时配置同步支持相同字段。
- `ss_online_update.sh` 订阅解析支持 `obfs`、`obfs-password`，并兼容常见非官方带宽参数 `upmbps/downmbps`、`up/down`、`upload/download`。

本阶段不做：

- 不做 `tls.pinSHA256`。
- 不做 `udpTProxy`。`knowledge.md` 已确认这是 UDP 链路关键缺口，但它和 obfs/bandwidth 是独立改造，避免这一轮扩大范围。
- 不改 `start_hy2()` 命令行。obfs/bandwidth 都是 JSON 参数，不需要改启动参数。

## Field Contract

字段命名固定为：

```text
ss_basic_hy2_obfs_type
ss_basic_hy2_obfs_password
ss_basic_hy2_up_mbps
ss_basic_hy2_down_mbps

ssconf_basic_hy2_obfs_type_<n>
ssconf_basic_hy2_obfs_password_<n>
ssconf_basic_hy2_up_mbps_<n>
ssconf_basic_hy2_down_mbps_<n>
```

约束：

- `hy2_obfs_type` 只接受空值、`none`、`salamander`。空值和 `none` 都表示不写 `obfs`。
- `hy2_obfs_password` 只在 `hy2_obfs_type=salamander` 时有效；启用 salamander 时必须非空。
- `hy2_up_mbps` 和 `hy2_down_mbps` 必须同时为空，或同时为正整数。
- 带宽字段为空时不写 `bandwidth`，Hysteria2 回退默认 BBR。
- JSON 输出单位固定拼成 `"数字 mbps"`，Web 和 dbus 只存纯数字。

---

### Task 1: Web 当前运行节点字段

**Files:**

- Modify: `C:\Users\Zen\Repo\Codes\Merlin\shadowsocks\webs\Main_Ss_Content.asp`
- Verify: Web 保存当前运行 HY2 节点后，dbus 出现 `ss_basic_hy2_*` 和 `ssconf_basic_hy2_*_<node>`。

- [ ] **Step 1: 在主运行面板 HTML 增加 HY2 字段**

在 `trojan_sni_basic_tr` 后面插入四行。字段只属于 Hysteria2，不放进 SSR 的 obfs 行。

```html
<tr id="hy2_obfs_type_basic_tr" style="display: none;">
  <th width="35%">HY2 混淆类型</th>
  <td>
    <select id="ss_basic_hy2_obfs_type" name="ss_basic_hy2_obfs_type" style="width:164px;margin:0px 0px 0px 2px;" class="input_option" onchange="verifyFields(this, 1);">
      <option value="">不启用</option>
      <option value="salamander">salamander</option>
    </select>
  </td>
</tr>
<tr id="hy2_obfs_password_basic_tr" style="display: none;">
  <th width="35%">HY2 混淆密码</th>
  <td>
    <input type="text" name="ss_basic_hy2_obfs_password" id="ss_basic_hy2_obfs_password" class="input_ss_table" style="width:300px;" placeholder="obfs-password" maxlength="300" value=""/>
  </td>
</tr>
<tr id="hy2_up_mbps_basic_tr" style="display: none;">
  <th width="35%">HY2 上行带宽(Mbps)</th>
  <td>
    <input type="text" name="ss_basic_hy2_up_mbps" id="ss_basic_hy2_up_mbps" class="input_ss_table" style="width:120px;" placeholder="如 20" maxlength="8" value=""/>
  </td>
</tr>
<tr id="hy2_down_mbps_basic_tr" style="display: none;">
  <th width="35%">HY2 下行带宽(Mbps)</th>
  <td>
    <input type="text" name="ss_basic_hy2_down_mbps" id="ss_basic_hy2_down_mbps" class="input_ss_table" style="width:120px;" placeholder="如 100" maxlength="8" value=""/>
  </td>
</tr>
```

- [ ] **Step 2: 把主运行 HY2 字段加入 `save()` 的 `params_input`**

在 `params_input` 数组末尾追加：

```javascript
"ss_basic_hy2_obfs_type",
"ss_basic_hy2_obfs_password",
"ss_basic_hy2_up_mbps",
"ss_basic_hy2_down_mbps"
```

- [ ] **Step 3: 把 HY2 字段加入当前节点同步数组**

在 `save()` 里的 `var params = [...]` 末尾追加不带 `ss_basic_` 前缀的字段名：

```javascript
"hy2_obfs_type",
"hy2_obfs_password",
"hy2_up_mbps",
"hy2_down_mbps"
```

这样保存当前运行节点时会同时写：

```text
ss_basic_hy2_*
ssconf_basic_hy2_*_<node_sel>
```

- [ ] **Step 4: 增加主运行字段校验函数**

在 `save()` 前新增函数：

```javascript
function validate_hy2_fields(prefix) {
  var binary = E(prefix + "_trojan_binary");
  if (!binary || binary.value != "Hysteria2") {
    return true;
  }

  var obfsType = E(prefix + "_hy2_obfs_type").value;
  var obfsPassword = $.trim(E(prefix + "_hy2_obfs_password").value);
  var up = $.trim(E(prefix + "_hy2_up_mbps").value);
  var down = $.trim(E(prefix + "_hy2_down_mbps").value);
  var re = /^[1-9][0-9]*$/;

  if (obfsType == "salamander" && obfsPassword == "") {
    alert("Hysteria2 启用 salamander 混淆时，必须填写 obfs-password。");
    return false;
  }

  if ((up != "" || down != "") && (!re.test(up) || !re.test(down))) {
    alert("Hysteria2 上行/下行带宽必须同时填写正整数，单位为 Mbps。");
    return false;
  }

  if (obfsType != "salamander") {
    E(prefix + "_hy2_obfs_password").value = "";
  }
  return true;
}
```

在 `save()` 开始处，完成 server/port/password trim 后调用：

```javascript
if (!validate_hy2_fields("ss_basic")) {
  return false;
}
```

- [ ] **Step 5: 更新主运行显隐逻辑**

在 `verifyFields()` 的 `//trojan Hysteria2` 段落附近加入：

```javascript
var hy2_on = trojan_on && E("ss_basic_trojan_binary").value == "Hysteria2";
showhide("hy2_obfs_type_basic_tr", hy2_on);
showhide("hy2_obfs_password_basic_tr", hy2_on && E("ss_basic_hy2_obfs_type").value == "salamander");
showhide("hy2_up_mbps_basic_tr", hy2_on);
showhide("hy2_down_mbps_basic_tr", hy2_on);
```

- [ ] **Step 6: 静态检查**

Run:

```powershell
rg -n "ss_basic_hy2_obfs_type|hy2_obfs_type_basic_tr|validate_hy2_fields|hy2_down_mbps" shadowsocks\webs\Main_Ss_Content.asp
```

Expected:

- 能看到 HTML 行。
- 能看到 `params_input`。
- 能看到当前节点同步 `params`。
- 能看到 `validate_hy2_fields("ss_basic")`。

---

### Task 2: Web 节点库新增、编辑、回显、删除

**Files:**

- Modify: `C:\Users\Zen\Repo\Codes\Merlin\shadowsocks\webs\Main_Ss_Content.asp`
- Verify: 手动新增 HY2 节点、编辑 HY2 节点、应用 HY2 节点后，四个 `ssconf_basic_hy2_*_<n>` 字段不会丢。

- [ ] **Step 1: 在节点新增/编辑弹窗 HTML 增加 HY2 字段**

在弹窗里的 `trojan_sni_tr` 后面插入：

```html
<tr id="hy2_obfs_type_tr" style="display: none;">
  <th width="35%">HY2 混淆类型</th>
  <td>
    <select id="ss_node_table_hy2_obfs_type" name="ss_node_table_hy2_obfs_type" style="width:350px;margin:0px 0px 0px 2px;" class="input_option" onchange="verifyFields(this, 1);">
      <option value="">不启用</option>
      <option value="salamander">salamander</option>
    </select>
  </td>
</tr>
<tr id="hy2_obfs_password_tr" style="display: none;">
  <th width="35%">HY2 混淆密码</th>
  <td>
    <input type="text" name="ss_node_table_hy2_obfs_password" id="ss_node_table_hy2_obfs_password" class="input_ss_table" style="width:342px;" placeholder="obfs-password" maxlength="300" value=""/>
  </td>
</tr>
<tr id="hy2_up_mbps_tr" style="display: none;">
  <th width="35%">HY2 上行带宽(Mbps)</th>
  <td>
    <input type="text" name="ss_node_table_hy2_up_mbps" id="ss_node_table_hy2_up_mbps" class="input_ss_table" style="width:120px;" placeholder="如 20" maxlength="8" value=""/>
  </td>
</tr>
<tr id="hy2_down_mbps_tr" style="display: none;">
  <th width="35%">HY2 下行带宽(Mbps)</th>
  <td>
    <input type="text" name="ss_node_table_hy2_down_mbps" id="ss_node_table_hy2_down_mbps" class="input_ss_table" style="width:120px;" placeholder="如 100" maxlength="8" value=""/>
  </td>
</tr>
```

- [ ] **Step 2: 节点弹窗显隐逻辑**

在 `verifyFields()` 的节点新增/编辑面板段落中加入统一显隐，不要只写在某一个分支里：

```javascript
var hy2_node_on = save_flag == "trojan" && E("ss_node_table_trojan_binary").value == "Hysteria2";
showhide("hy2_obfs_type_tr", hy2_node_on);
showhide("hy2_obfs_password_tr", hy2_node_on && E("ss_node_table_hy2_obfs_type").value == "salamander");
showhide("hy2_up_mbps_tr", hy2_node_on);
showhide("hy2_down_mbps_tr", hy2_node_on);
```

在 `trojan_change_off(xy)` 里切离 Hysteria2 时清空 HY2 专属字段：

```javascript
if (xy != "Hysteria2") {
  E("ss_node_table_hy2_obfs_type").value = "";
  E("ss_node_table_hy2_obfs_password").value = "";
  E("ss_node_table_hy2_up_mbps").value = "";
  E("ss_node_table_hy2_down_mbps").value = "";
}
```

- [ ] **Step 3: 节点新增默认值清空**

在 `Add_profile()` 清空其它节点字段的位置加入：

```javascript
E("ss_node_table_hy2_obfs_type").value = "";
E("ss_node_table_hy2_obfs_password").value = "";
E("ss_node_table_hy2_up_mbps").value = "";
E("ss_node_table_hy2_down_mbps").value = "";
```

- [ ] **Step 4: 新增节点保存**

在 `add_ss_node_conf(flag)` 的 `paramsTrojan` 数组末尾追加：

```javascript
"hy2_obfs_type",
"hy2_obfs_password",
"hy2_up_mbps",
"hy2_down_mbps"
```

在 `flag == 'trojan'` 分支开头加入校验：

```javascript
if (!validate_hy2_fields("ss_node_table")) {
  node_global_max -= 1;
  return false;
}
```

在新增成功后的表单 reset 位置加入：

```javascript
E("ss_node_table_hy2_obfs_type").value = "";
E("ss_node_table_hy2_obfs_password").value = "";
E("ss_node_table_hy2_up_mbps").value = "";
E("ss_node_table_hy2_down_mbps").value = "";
```

- [ ] **Step 5: 编辑节点回显**

在 `edit_conf_table()` 的 `params1_input` 数组末尾追加：

```javascript
"hy2_obfs_type",
"hy2_obfs_password",
"hy2_up_mbps",
"hy2_down_mbps"
```

- [ ] **Step 6: 编辑节点保存**

在 `edit_ss_node_conf(flag)` 的 `paramsTrojan` 数组末尾追加：

```javascript
"hy2_obfs_type",
"hy2_obfs_password",
"hy2_up_mbps",
"hy2_down_mbps"
```

在 `flag == 'trojan'` 分支开头加入：

```javascript
if (!validate_hy2_fields("ss_node_table")) {
  return false;
}
```

- [ ] **Step 7: 应用节点到当前运行节点**

在 `ssconf_node2obj(node_sel)` 的 `params2` 数组末尾追加：

```javascript
"hy2_obfs_type",
"hy2_obfs_password",
"hy2_up_mbps",
"hy2_down_mbps"
```

在 `getAllConfigs()` 的 `params` 数组末尾追加同样四个字段，保证列表对象 `confs[field]` 带齐 HY2 字段。

- [ ] **Step 8: 删除节点时清理新字段**

在 `remove_conf_table(o)` 的 `params` 数组末尾追加：

```javascript
"hy2_obfs_type",
"hy2_obfs_password",
"hy2_up_mbps",
"hy2_down_mbps"
```

- [ ] **Step 9: 非 HY2 当前节点避免残留**

在 `save()` 里根据选中协议清理当前运行 HY2 字段。最小做法是在 `ss_basic_trojan_binary != "Hysteria2"` 时写空：

```javascript
if (E("ss_basic_trojan_binary").value != "Hysteria2") {
  dbus["ss_basic_hy2_obfs_type"] = "";
  dbus["ss_basic_hy2_obfs_password"] = "";
  dbus["ss_basic_hy2_up_mbps"] = "";
  dbus["ss_basic_hy2_down_mbps"] = "";
}
```

- [ ] **Step 10: 静态检查**

Run:

```powershell
rg -n "ss_node_table_hy2|hy2_obfs_password|hy2_up_mbps|hy2_down_mbps" shadowsocks\webs\Main_Ss_Content.asp
```

Expected:

- 每个字段至少出现在 HTML、默认值、显隐、add、edit、回显、删除、应用链路里。

---

### Task 3: 正式运行 HY2 JSON 生成

**Files:**

- Modify: `C:\Users\Zen\Repo\Codes\Merlin\shadowsocks\ss\ssconfig.sh`
- Verify: `/koolshare/ss/hysteria.json` 在启用字段时包含 `obfs` 和 `bandwidth`，未启用时不包含。

- [ ] **Step 1: 替换 `create_hy2_json()`**

将当前 heredoc 版本改成 `jq -n` 版本。保留 `tcpRedirect.listen=0.0.0.0:3333` 和 `socks5.listen=127.0.0.1:23456`。

```sh
create_hy2_json(){
	rm -f "$HY2_CONFIG_FILE"
	if  [ "$ss_basic_type" == "4" ] && [ "$ss_basic_trojan_binary" == "Hysteria2" ]; then
		echo_date 生成Hysteria2配置文件...

		local hy2_obfs_type="$ss_basic_hy2_obfs_type"
		local hy2_obfs_password="$ss_basic_hy2_obfs_password"
		local hy2_up_mbps="$ss_basic_hy2_up_mbps"
		local hy2_down_mbps="$ss_basic_hy2_down_mbps"
		local hy2_has_obfs="false"
		local hy2_has_bandwidth="false"

		[ "$hy2_obfs_type" == "salamander" ] && [ -n "$hy2_obfs_password" ] && hy2_has_obfs="true"
		echo "$hy2_up_mbps" | grep -Eq '^[1-9][0-9]*$' && echo "$hy2_down_mbps" | grep -Eq '^[1-9][0-9]*$' && hy2_has_bandwidth="true"

		jq -n \
			--arg server "$(dbus get ss_basic_server):$ss_basic_port" \
			--arg auth "$ss_basic_password" \
			--arg sni "$ss_basic_trojan_sni" \
			--argjson insecure "$(get_function_switch $ss_basic_allowinsecure)" \
			--arg obfs_password "$hy2_obfs_password" \
			--arg up "$hy2_up_mbps" \
			--arg down "$hy2_down_mbps" \
			--argjson has_obfs "$hy2_has_obfs" \
			--argjson has_bandwidth "$hy2_has_bandwidth" '
			{
				server: $server,
				auth: $auth,
				tls: {
					sni: $sni,
					insecure: $insecure
				},
				fastOpen: true,
				lazy: true,
				socks5: {
					listen: "127.0.0.1:23456"
				},
				tcpRedirect: {
					listen: "0.0.0.0:3333"
				}
			}
			+ (if $has_obfs then {
				obfs: {
					type: "salamander",
					salamander: {
						password: $obfs_password
					}
				}
			} else {} end)
			+ (if $has_bandwidth then {
				bandwidth: {
					up: ($up + " mbps"),
					down: ($down + " mbps")
				}
			} else {} end)
			' > "$HY2_CONFIG_FILE"

		if [ "$?" != "0" ] || [ ! -s "$HY2_CONFIG_FILE" ]; then
			echo_date "Hysteria2 配置文件 JSON 生成失败！"
			close_in_five
		fi

		echo_date Hysteria2 配置文件写入成功到 "$HY2_CONFIG_FILE"
	fi
}
```

- [ ] **Step 2: shell 语法检查**

Run:

```powershell
sh -n shadowsocks\ss\ssconfig.sh
```

Expected:

```text
无输出，退出码 0
```

如果 Windows 本机没有 `sh`，在 Merlin 路由器上运行：

```sh
sh -n /koolshare/ss/ssconfig.sh
```

- [ ] **Step 3: 实机 JSON 验证**

Run on router:

```sh
dbus set ss_basic_type=4
dbus set ss_basic_trojan_binary=Hysteria2
dbus set ss_basic_server=hy2.example.com
dbus set ss_basic_port=443
dbus set ss_basic_password=$(echo -n 'auth-secret' | base64_encode)
dbus set ss_basic_trojan_sni=hy2.example.com
dbus set ss_basic_allowinsecure=0
dbus set ss_basic_hy2_obfs_type=salamander
dbus set ss_basic_hy2_obfs_password='obfs-secret'
dbus set ss_basic_hy2_up_mbps=20
dbus set ss_basic_hy2_down_mbps=100
sh /koolshare/ss/ssconfig.sh restart
jq . /koolshare/ss/hysteria.json
```

Expected JSON contains:

```json
{
  "obfs": {
    "type": "salamander",
    "salamander": {
      "password": "obfs-secret"
    }
  },
  "bandwidth": {
    "up": "20 mbps",
    "down": "100 mbps"
  }
}
```

- [ ] **Step 4: 兼容空字段**

Run on router:

```sh
dbus remove ss_basic_hy2_obfs_type
dbus remove ss_basic_hy2_obfs_password
dbus remove ss_basic_hy2_up_mbps
dbus remove ss_basic_hy2_down_mbps
sh /koolshare/ss/ssconfig.sh restart
jq 'has("obfs"), has("bandwidth")' /koolshare/ss/hysteria.json
```

Expected:

```text
false
false
```

---

### Task 4: HY2 Web 测速同步

**Files:**

- Modify: `C:\Users\Zen\Repo\Codes\Merlin\shadowsocks\scripts\ss_webtest.sh`
- Verify: `/tmp/tmp_hysteria.json` 测速配置和正式运行支持同样的 obfs/bandwidth。

- [ ] **Step 1: 替换 `ss_webtest.sh::create_hy2_json()`**

测速只走 SOCKS5 `127.0.0.1:23458`，不要写 `tcpRedirect` 或 `udpTProxy`。

```sh
create_hy2_json(){
	rm -f /tmp/tmp_hysteria.json

	local hy2_obfs_type="$(dbus get ssconf_basic_hy2_obfs_type_$nu)"
	local hy2_obfs_password="$(dbus get ssconf_basic_hy2_obfs_password_$nu)"
	local hy2_up_mbps="$(dbus get ssconf_basic_hy2_up_mbps_$nu)"
	local hy2_down_mbps="$(dbus get ssconf_basic_hy2_down_mbps_$nu)"
	local hy2_has_obfs="false"
	local hy2_has_bandwidth="false"

	[ "$hy2_obfs_type" == "salamander" ] && [ -n "$hy2_obfs_password" ] && hy2_has_obfs="true"
	echo "$hy2_up_mbps" | grep -Eq '^[1-9][0-9]*$' && echo "$hy2_down_mbps" | grep -Eq '^[1-9][0-9]*$' && hy2_has_bandwidth="true"

	jq -n \
		--arg server "${array1}:${array2}" \
		--arg auth "${array3}" \
		--arg sni "$(eval echo \$ssconf_basic_trojan_sni_$nu)" \
		--argjson insecure "$(get_function_switch $(eval echo \$ssconf_basic_allowinsecure_$nu))" \
		--arg obfs_password "$hy2_obfs_password" \
		--arg up "$hy2_up_mbps" \
		--arg down "$hy2_down_mbps" \
		--argjson has_obfs "$hy2_has_obfs" \
		--argjson has_bandwidth "$hy2_has_bandwidth" '
		{
			server: $server,
			auth: $auth,
			tls: {
				sni: $sni,
				insecure: $insecure
			},
			fastOpen: true,
			lazy: true,
			socks5: {
				listen: "127.0.0.1:23458"
			}
		}
		+ (if $has_obfs then {
			obfs: {
				type: "salamander",
				salamander: {
					password: $obfs_password
				}
			}
		} else {} end)
		+ (if $has_bandwidth then {
			bandwidth: {
				up: ($up + " mbps"),
				down: ($down + " mbps")
			}
		} else {} end)
		' > /tmp/tmp_hysteria.json
}
```

- [ ] **Step 2: shell 语法检查**

Run:

```powershell
sh -n shadowsocks\scripts\ss_webtest.sh
```

Expected:

```text
无输出，退出码 0
```

- [ ] **Step 3: 实机测速验证**

在 Web 里对一个带 `obfs/bandwidth` 的 Hysteria2 节点执行测速，然后在路由器上检查：

```sh
jq '.obfs, .bandwidth, .socks5.listen' /tmp/tmp_hysteria.json
```

Expected:

```text
obfs 为 salamander
bandwidth.up/down 为 "数字 mbps"
socks5.listen 为 "127.0.0.1:23458"
```

---

### Task 5: 订阅和单链接导入同步

**Files:**

- Modify: `C:\Users\Zen\Repo\Codes\Merlin\shadowsocks\scripts\ss_online_update.sh`
- Modify: `C:\Users\Zen\Repo\Codes\Merlin\shadowsocks\webs\Main_Ss_Content.asp`
- Verify: `hysteria2://` 或 `hy2://` 链接导入后，新字段写入 `ssconf_basic_hy2_*_<n>`。

- [ ] **Step 1: 增加 URI 参数读取 helper**

在 `urldecode()` 和 `dbus_update_if_diff()` 附近加入：

```sh
get_uri_param(){
	local key="$1"
	echo "$decode_link" | tr '?#&' '\n' | grep -m1 "^${key}=" | cut -d'=' -f2- | urldecode
}

normalize_mbps(){
	echo "$1" | sed 's/%20/ /g' | awk '{print $1}' | grep -Eo '^[1-9][0-9]*'
}
```

- [ ] **Step 2: 扩展 `get_hysteria2_config()`**

在解析 `sni` 和 `insecure` 后加入：

```sh
hy2_obfs_type="$(get_uri_param obfs)"
hy2_obfs_password="$(get_uri_param obfs-password)"
hy2_up_mbps="$(get_uri_param upmbps)"
hy2_down_mbps="$(get_uri_param downmbps)"

[ -z "$hy2_up_mbps" ] && hy2_up_mbps="$(get_uri_param up)"
[ -z "$hy2_up_mbps" ] && hy2_up_mbps="$(get_uri_param upload)"
[ -z "$hy2_down_mbps" ] && hy2_down_mbps="$(get_uri_param down)"
[ -z "$hy2_down_mbps" ] && hy2_down_mbps="$(get_uri_param download)"

[ "$hy2_obfs_type" != "salamander" ] && hy2_obfs_type=""
hy2_up_mbps="$(normalize_mbps "$hy2_up_mbps")"
hy2_down_mbps="$(normalize_mbps "$hy2_down_mbps")"
```

保留官方事实：Hysteria2 URI 标准主要表达 `obfs` 和 `obfs-password`，带宽字段没有完全统一的 URI 规范；这里是兼容订阅供应商常见扩展参数。

- [ ] **Step 3: 新增订阅节点写入字段**

在 `add_hysteria2_servers()` 中写入基础字段后加入：

```sh
dbus set ssconf_basic_hy2_obfs_type_$hysteria2index="$hy2_obfs_type"
dbus set ssconf_basic_hy2_obfs_password_$hysteria2index="$hy2_obfs_password"
dbus set ssconf_basic_hy2_up_mbps_$hysteria2index="$hy2_up_mbps"
dbus set ssconf_basic_hy2_down_mbps_$hysteria2index="$hy2_down_mbps"
```

- [ ] **Step 4: 更新订阅节点时比较字段**

在 `update_hysteria2_config()` 的 diff 区域加入：

```sh
dbus_update_if_diff "ssconf_basic_hy2_obfs_type_$index" "$hy2_obfs_type" && i=$((i+1))
dbus_update_if_diff "ssconf_basic_hy2_obfs_password_$index" "$hy2_obfs_password" && i=$((i+1))
dbus_update_if_diff "ssconf_basic_hy2_up_mbps_$index" "$hy2_up_mbps" && i=$((i+1))
dbus_update_if_diff "ssconf_basic_hy2_down_mbps_$index" "$hy2_down_mbps" && i=$((i+1))
```

- [ ] **Step 5: 兼容 `hy2://` 短前缀**

新增函数别名：

```sh
get_hy2_config(){
	get_hysteria2_config "$@"
}

add_hy2_servers(){
	add_hysteria2_servers "$@"
}

update_hy2_config(){
	update_hysteria2_config "$@"
}
```

把两处订阅识别正则：

```sh
^ss://|^ssr://|^vmess://|^trojan://|^vless://|^trojan-go://|^hysteria2://
```

改成：

```sh
^ss://|^ssr://|^vmess://|^trojan://|^vless://|^trojan-go://|^hysteria2://|^hy2://
```

- [ ] **Step 6: 删除和节点压缩时同步新字段**

在 `del_none_exist()` 删除节点字段列表中加入：

```sh
dbus remove ssconf_basic_hy2_obfs_type_$localindex
dbus remove ssconf_basic_hy2_obfs_password_$localindex
dbus remove ssconf_basic_hy2_up_mbps_$localindex
dbus remove ssconf_basic_hy2_down_mbps_$localindex
```

在订阅节点重新编号/压缩逻辑中加入：

```sh
[ -n "$(dbus get ssconf_basic_hy2_obfs_type_$nu)" ] && dbus set ssconf_basic_hy2_obfs_type_"$y"="$(dbus get ssconf_basic_hy2_obfs_type_$nu)" && dbus remove ssconf_basic_hy2_obfs_type_$nu
[ -n "$(dbus get ssconf_basic_hy2_obfs_password_$nu)" ] && dbus set ssconf_basic_hy2_obfs_password_"$y"="$(dbus get ssconf_basic_hy2_obfs_password_$nu)" && dbus remove ssconf_basic_hy2_obfs_password_$nu
[ -n "$(dbus get ssconf_basic_hy2_up_mbps_$nu)" ] && dbus set ssconf_basic_hy2_up_mbps_"$y"="$(dbus get ssconf_basic_hy2_up_mbps_$nu)" && dbus remove ssconf_basic_hy2_up_mbps_$nu
[ -n "$(dbus get ssconf_basic_hy2_down_mbps_$nu)" ] && dbus set ssconf_basic_hy2_down_mbps_"$y"="$(dbus get ssconf_basic_hy2_down_mbps_$nu)" && dbus remove ssconf_basic_hy2_down_mbps_$nu
```

在 `remove_online()` 和 `remove_all()` 覆盖的删除路径中确认 `dbus list ssconf_basic_` 全量删除已经覆盖；只在逐字段删除分支补新字段。

- [ ] **Step 7: 更新 Web 订阅文案**

在 `Main_Ss_Content.asp` 中把订阅支持文案和 textarea placeholder 从只写 `hysteria2://` 扩展为：

```text
hysteria2:// 或 hy2://
```

- [ ] **Step 8: shell 语法检查**

Run:

```powershell
sh -n shadowsocks\scripts\ss_online_update.sh
```

Expected:

```text
无输出，退出码 0
```

- [ ] **Step 9: 单链接导入实机验证**

Run on router:

```sh
dbus set ss_base64_links='hy2://auth-secret@hy2.example.com:443?sni=hy2.example.com&insecure=0&obfs=salamander&obfs-password=obfs-secret&upmbps=20&downmbps=100#hy2-test'
sh /koolshare/scripts/ss_online_update.sh 5
dbus list ssconf_basic_ | grep hy2_
```

Expected:

```text
ssconf_basic_hy2_obfs_type_<n>=salamander
ssconf_basic_hy2_obfs_password_<n>=obfs-secret
ssconf_basic_hy2_up_mbps_<n>=20
ssconf_basic_hy2_down_mbps_<n>=100
```

---

### Task 6: Packaging And Regression Checks

**Files:**

- Verify: `C:\Users\Zen\Repo\Codes\Merlin\shadowsocks`
- Optional modify only if needed: `C:\Users\Zen\Repo\Codes\Merlin\README.md`

- [ ] **Step 1: 静态覆盖检查**

Run:

```powershell
rg -n "hy2_obfs_type|hy2_obfs_password|hy2_up_mbps|hy2_down_mbps" shadowsocks
```

Expected:

- `Main_Ss_Content.asp`：HTML、保存、回显、新增、编辑、删除、显隐、校验都有命中。
- `ssconfig.sh`：正式运行 JSON 命中。
- `ss_webtest.sh`：测速 JSON 命中。
- `ss_online_update.sh`：订阅解析、新增、更新、删除、压缩都有命中。

- [ ] **Step 2: 核心脚本语法检查**

Run:

```powershell
sh -n shadowsocks\ss\ssconfig.sh
sh -n shadowsocks\scripts\ss_webtest.sh
sh -n shadowsocks\scripts\ss_online_update.sh
```

Expected:

```text
三条命令均无输出，退出码 0
```

- [ ] **Step 3: Web 端手工回归**

在 Merlin Web 页面验证：

1. 选择当前运行节点为 Hysteria2，四个 HY2 字段显示。
2. 切到 Trojan 或 Trojan-Go，四个 HY2 字段隐藏。
3. `obfs` 不启用时，`obfs-password` 行隐藏且保存后不写 JSON。
4. `obfs=salamander` 且密码为空时，保存被阻止。
5. `up/down` 只填一个或填非数字时，保存被阻止。
6. 新增 Hysteria2 节点，保存后重新编辑，四个字段能回显。
7. 应用该节点为运行节点，`ss_basic_hy2_*` 与 `ssconf_basic_hy2_*_<n>` 一致。
8. 对该节点执行 Web 测速，`/tmp/tmp_hysteria.json` 包含同样的 `obfs/bandwidth`。

- [ ] **Step 4: 正式启动回归**

Run on router:

```sh
sh /koolshare/ss/ssconfig.sh restart
pidof hysteria
jq '.server, .obfs, .bandwidth, .socks5.listen, .tcpRedirect.listen' /koolshare/ss/hysteria.json
curl --socks5 127.0.0.1:23456 https://www.google.com -o /dev/null -w "%{http_code}\n"
```

Expected:

```text
pidof hysteria 有 pid
obfs/bandwidth 按 Web 输入生成
socks5.listen 为 127.0.0.1:23456
tcpRedirect.listen 为 0.0.0.0:3333
curl 返回 200/301/302/403 之一，表示代理链路可达
```

- [ ] **Step 5: 打包检查**

本项目是 Merlin 插件包，不需要交叉编译。确认目录结构保持：

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

如果要本地直接打包：

```powershell
tar -czf shadowsocks.tar.gz shadowsocks
```

如果在路由器上沿用现有脚本：

```sh
sh /koolshare/scripts/ss_pack.sh
ls -lh /tmp/shadowsocks.tar.gz
```

Expected:

```text
包内根目录是 shadowsocks/
新增修改后的 ssconfig.sh、ss_webtest.sh、ss_online_update.sh、Main_Ss_Content.asp 都在包内
```

---

## Implementation Order

1. 先做 `Main_Ss_Content.asp` 的字段闭环。Web 字段不闭环，后端 JSON 改好也拿不到参数。
2. 再做 `ssconfig.sh:create_hy2_json()`。这是正式运行的核心落点。
3. 再做 `ss_webtest.sh:create_hy2_json()`。避免“正式能连，测速失败”。
4. 最后做 `ss_online_update.sh`。订阅字段多，改完需要跑删除和压缩路径。
5. 全部完成后再打包，不需要任何交叉编译。

## Risk Checklist

| Risk | Where | Mitigation |
|---|---|---|
| JSON 手拼被特殊字符破坏 | `ssconfig.sh`、`ss_webtest.sh` | 用 `jq -n --arg` 生成 |
| Web 数组漏一个导致保存/回显断链 | `Main_Ss_Content.asp` | 按 Task 1/2 静态检查所有 `hy2_*` |
| 非 HY2 节点残留 HY2 字段 | Web 保存和切换协议 | 切离 Hysteria2 时清空 |
| 带宽字段半填导致 Hysteria2 报错 | Web 校验、Shell 生成 | Web 阻止；Shell 只在 up/down 都是正整数时写入 |
| 订阅带宽参数非官方不统一 | `ss_online_update.sh` | 官方字段只保证 obfs；带宽兼容常见 `upmbps/downmbps/up/down/upload/download` |
| UDP 仍不通 | `hysteria.json` 无 `udpTProxy` | 本阶段不解决；后续按 `knowledge.md` 单独做 UDP/TProxy 计划 |

