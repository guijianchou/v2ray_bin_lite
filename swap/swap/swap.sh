#! /bin/sh
# ====================================变量定义====================================
# 版本号定义
version="1.9"
dbus set swap_version="$version"
# 导入skipd数据
eval `dbus export swap`

# 引用环境变量等
source /koolshare/scripts/base.sh

# 状态码定义（swap_warnning）
# 1	没有找到可用的USB磁盘
# 2	USB磁盘格式不符合要求
# 3	成功检测到ext？格式磁盘,可以创建swap
# 4	swap已经加载
# 5	swap使用中的页面塞不回空闲内存，swapoff失败，暂时无法安全卸载
# 6	磁盘剩余空间不足，无法创建
# 7	swap已加载，但未开启JFFS custom scripts，开机无法自动挂载

# 同时更新 shell 变量与 dbus：check_usb_status 中途改状态后，mkswap 才能读到最新值。
# 只 dbus set 不会改变当前 shell 里的 $swap_warnning（它在脚本启动时由 dbus export 赋值一次）。
set_state(){
	swap_warnning="$1"
	dbus set swap_warnning="$1"
}

# 遍历 /tmp/mnt 下的挂载点，优先选择 ext2/3/4 分区；
# 找不到 ext 分区时，取第一个挂载点用于报告"格式不符"。
# busybox ash 管道属子shell，变量不回传，用临时文件中转。
find_usb_disk(){
	local tmpf=/tmp/swap_disk.$$
	usb_disk=""
	ext_type=""
	/bin/mount | grep ' /tmp/mnt/' | while read _dev _on mnt _type fs _rest;do
		case "$fs" in
			ext2|ext3|ext4)
				echo "$mnt $fs"
				break
			;;
		esac
	done > "$tmpf"
	if [ -s "$tmpf" ];then
		read usb_disk ext_type < "$tmpf"
	else
		usb_disk=$(/bin/mount | grep ' /tmp/mnt/' | sed -n 1p | cut -d" " -f3)
		ext_type=$(/bin/mount | grep ' /tmp/mnt/' | sed -n 1p | cut -d" " -f5)
	fi
	rm -f "$tmpf"
	dbus set swap_usb_type="$ext_type"
	dbus set swap_usb_disk="$usb_disk"
}

get_swap_total(){
	free | grep Swap | awk '{print $2}'
}

# swap处于挂载状态时：正常为4；jffs脚本未开启时为7（开机不会自动挂载）
set_mounted_state(){
	if [ "$(nvram get jffs2_scripts)" != "1" ];then
		set_state "7"
	else
		set_state "4"
	fi
}

check_usb_status(){
	find_usb_disk

	if [ "$(get_swap_total)" != "0" ];then
		set_mounted_state
		return 0
	fi
	if [ -z "$usb_disk" ];then
		set_state "1"
		return 0
	fi
	# 先判文件系统：非ext一律格式不符（残留swapfile也无法swapon）
	case "$ext_type" in
		ext2|ext3|ext4) ;;
		*)
			set_state "2"
			return 0
		;;
	esac
	if [ -f "$usb_disk"/swapfile ];then
		swapon "$usb_disk"/swapfile >/dev/null 2>&1
		if [ "$(get_swap_total)" != "0" ];then
			set_mounted_state
		else
			# swapfile存在但挂载失败（可能损坏），进入创建流程重新格式化
			set_state "3"
		fi
		return 0
	fi
	set_state "3"
}

create_swap(){
	# 仅在"可创建"状态下执行；依赖 check_usb_status 刚经 set_state 更新的 $swap_warnning
	if [ "$swap_warnning" == "3" ];then
		# 256M 512M 1G 对应 dd bs=1M 的块数；swap_size未设置时兜底512M
		case "$swap_size" in
			1) count=256;;
			3) count=1024;;
			*) count=512;;
		esac
		if [ ! -f "$usb_disk"/swapfile ];then
			# 创建前检查磁盘剩余空间（额外预留10MB）
			free_kb=$(df -k "$usb_disk" | awk 'NR==2{print $4}')
			if [ -z "$free_kb" ] || [ "$free_kb" -lt $((count*1024+10240)) ];then
				set_state "6"
				return 1
			fi
			# bs=1M 减少syscall次数，在USB2+性能有限的CPU上比bs=1024快一个数量级；
			# dd失败（磁盘满/IO错误）时清理残file并报空间不足
			if ! dd if=/dev/zero of="$usb_disk"/swapfile bs=1M count=$count 2>/dev/null;then
				rm -f "$usb_disk"/swapfile
				set_state "6"
				return 1
			fi
			sync
		fi
		/sbin/mkswap "$usb_disk"/swapfile
		chmod 0600 "$usb_disk"/swapfile
		swapon "$usb_disk"/swapfile
		if [ "$(get_swap_total)" != "0" ];then
			set_mounted_state
			return 0
		fi
		return 1
	fi
}

swap_load_start(){
	# 只追加，绝不覆盖：post-mount 是全插件共享的启动钩子
	if [ ! -f /jffs/scripts/post-mount ];then
		printf '#!/bin/sh\n' > /jffs/scripts/post-mount
	fi
	if ! grep -q "swap_load" /jffs/scripts/post-mount;then
		# 若已有内容且末尾无换行，先补一个换行，避免与最后一行拼接成一条命令
		[ -n "$(tail -c1 /jffs/scripts/post-mount)" ] && echo "" >> /jffs/scripts/post-mount
		echo "sh /koolshare/scripts/swap_load.sh" >> /jffs/scripts/post-mount
	fi
	chmod +x /jffs/scripts/post-mount
}

swap_unload_start(){
	sed -i '/swap_load/d' /jffs/scripts/post-mount >/dev/null 2>&1
}

case $ACTION in
start)
	check_usb_status
	;;
load)
	check_usb_status
	create_swap
	# 只有swap真正挂载成功才注册开机项（jffs脚本未开启时也写入，待用户开启后即生效）
	if [ "$(get_swap_total)" != "0" ];then
		swap_load_start
	fi
	;;
unload)
	find_usb_disk
	if [ -n "$usb_disk" ] && [ -f "$usb_disk"/swapfile ];then
		# swapoff在内存不足时可能阻塞较久（内核尝试将swap页换回内存），成功后才删文件
		if swapoff "$usb_disk"/swapfile >/dev/null 2>&1;then
			rm -f "$usb_disk"/swapfile
			sync
			swap_unload_start
			check_usb_status
		else
			# swap已用页面塞不回空闲内存：保留swapfile与开机项，提示稍后重试
			set_state "5"
			exit 1
		fi
	else
		# 没找到swapfile（U盘被拔/文件已删），仅清理开机项并刷新状态
		swap_unload_start
		check_usb_status
	fi
	;;
check)
	# 仅查询状态；有swapfile未挂载时会顺带swapon兜底，但不注册开机项
	check_usb_status
	;;
esac
