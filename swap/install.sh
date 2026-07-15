#! /bin/sh
cd /tmp
cp -rf /tmp/swap/swap /koolshare/
cp -rf /tmp/swap/scripts/* /koolshare/scripts/
cp -rf /tmp/swap/webs/* /koolshare/webs/
cp -rf /tmp/swap/res/* /koolshare/res/
cp -rf /tmp/swap/uninstall.sh /koolshare/scripts/uninstall_swap.sh
cd /
rm -rf /tmp/swap* >/dev/null 2>&1

chmod 755 /koolshare/swap/*
chmod 755 /koolshare/scripts/swap*
chmod 755 /koolshare/scripts/uninstall_swap.sh
chmod 644 /koolshare/webs/Module_swap.asp
chmod 644 /koolshare/res/icon-swap.png

# 清理老版本遗留的死脚本（v1.8及以前）
rm -f /koolshare/scripts/swap_startup.sh
