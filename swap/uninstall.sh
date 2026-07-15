#! /bin/sh
# 卸载 swap 插件：先安全卸下 swap，再清理文件、开机项与 skipd 数据

source /koolshare/scripts/base.sh 2>/dev/null

# 与 swap.sh 相同的探测逻辑：优先 ext 分区
find_usb_disk(){
	local tmpf=/tmp/swap_disk.$$
	usb_disk=""
	/bin/mount | grep ' /tmp/mnt/' | while read _dev _on mnt _type fs _rest;do
		case "$fs" in
			ext2|ext3|ext4)
				echo "$mnt"
				break
			;;
		esac
	done > "$tmpf"
	[ -s "$tmpf" ] && read usb_disk < "$tmpf"
	rm -f "$tmpf"
}

find_usb_disk
if [ -n "$usb_disk" ] && [ -f "$usb_disk"/swapfile ];then
	if swapoff "$usb_disk"/swapfile >/dev/null 2>&1;then
		rm -f "$usb_disk"/swapfile
		sync
	else
		# 内存不足以收回swap页面：保留swapfile，不阻塞卸载，仅提示
		logger "[软件中心]: swap卸载：内存不足，swapoff失败，已保留swapfile，请重启后手动删除 $usb_disk/swapfile"
	fi
fi

# 清理开机项
sed -i '/swap_load/d' /jffs/scripts/post-mount >/dev/null 2>&1

# 清理插件文件
rm -rf /koolshare/swap
rm -f /koolshare/scripts/swap_check.sh
rm -f /koolshare/scripts/swap_load.sh
rm -f /koolshare/scripts/swap_unload.sh
rm -f /koolshare/scripts/swap_startup.sh
rm -f /koolshare/webs/Module_swap.asp
rm -f /koolshare/res/icon-swap.png
rm -f /koolshare/scripts/uninstall_swap.sh

# 清理skipd数据
dbus remove swap_version
dbus remove swap_usb_type
dbus remove swap_usb_disk
dbus remove swap_warnning
dbus remove swap_size
