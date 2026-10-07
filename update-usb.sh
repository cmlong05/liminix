#!/bin/sh
# 更新已分区的 U 盘上 p1（内核 fit.itb）与 p2（rootfs）的数据。
# 不分区、不 mkfs：GPT、p3/persist 和两个分区的现有文件系统都原样保留。
# p3（卷标 liminix-persist，挂 /persist）上的 config.json 优先于镜像里的种子，
# 与构建出的 config.json 不同就问一次是否替换（无 tty 时不替换，替换前备份为
# config.json.bak）；p3 上没有就不动。
# 用法：
#   sh update-usb.sh /dev/sdc
#   DRY_RUN=1 sh update-usb.sh /dev/sdc	# 只打印将执行的命令
set -eu
cd "$(dirname "$0")"

MAX_BYTES=33000000000	# 33 GB 上限，防止误刷到别的盘
UIMAGE=result-usb-ext4-uimage
ROOTFS=result-usb-ext4-rootfs
CONFIG=config.json
PERSIST_LABEL=liminix-persist

die() { echo "update-usb.sh: $*" >&2; exit 1; }
usage() { echo "usage: $0 /dev/sdX   (whole disk, < 33 GB)" >&2; exit 2; }

[ "$#" -eq 1 ] || usage
dev=$1
case "$dev" in /dev/*) ;; *) usage ;; esac

# DRY_RUN 只打印；root 直接执行；否则一律走 sudo
if [ "${DRY_RUN:-0}" = 1 ]; then
	run() { echo "  + $*"; }
elif [ "$(id -u)" = 0 ]; then
	run() { "$@"; }
else
	run() { sudo "$@"; }
fi

lsblk_field() { lsblk -b -dn -o "$2" "$1" 2>/dev/null | tr -d ' \n'; }	# -b：SIZE 输出字节数
mountpoint_of() { findmnt -rno TARGET --source "$1" 2>/dev/null || true; }
# 分区节点名：sdc -> sdc1，nvme0n1 -> nvme0n1p1
part() { case "$1" in *[0-9]) echo "${1}p$2" ;; *) echo "$1$2" ;; esac; }
size_of() {	# 取字节数；读不到就报错，别把 "14.8G" 当数字比
	v=$(lsblk_field "$1" SIZE)
	case "$v" in '' | *[!0-9]*) die "$1: cannot read size from lsblk ('$v')" ;; esac
	echo "$v"
}

command -v lsblk >/dev/null 2>&1 || die "lsblk not found"
command -v rsync >/dev/null 2>&1 || die "rsync not found"

# 以下检查任一不过就退出，保证不去动写错的盘
[ "$(lsblk_field "$dev" TYPE)" = disk ] || die "$dev is not a whole block device"
bytes=$(size_of "$dev")
[ "$bytes" -lt "$MAX_BYTES" ] || die "$dev is $bytes bytes: refusing disks of 33 GB and more"

p1=$(part "$dev" 1)
p2=$(part "$dev" 2)
p3=$(part "$dev" 3)
# 分区名必须对得上（p1=boot，p2=liminix-root），且两个分区都没被挂载
check_part() {
	[ "$(lsblk_field "$1" TYPE)" = part ] || die "$1 missing: the disk must already have p1 + p2"
	m=$(mountpoint_of "$1")
	[ -z "$m" ] || die "$1 is mounted at $m"
	label=$(lsblk_field "$1" PARTLABEL)
	[ "$label" = "$2" ] || die "$1 PARTLABEL is '${label:-none}', expected $2"
}
check_part "$p1" boot
check_part "$p2" liminix-root

# p3 是可选的：没有 liminix-persist 就跳过下面 config.json 的比较
have_p3=no
if [ "$(lsblk_field "$p3" TYPE)" = part ] && [ "$(lsblk_field "$p3" PARTLABEL)" = "$PERSIST_LABEL" ]; then
	have_p3=yes
fi

for f in "$UIMAGE" "$ROOTFS"; do
	[ -e "$f" ] || die "$f not built (run sh build.sh)"
done
uimage=$(readlink -f "$UIMAGE")
rootfs=$(readlink -f "$ROOTFS")
uimage_bytes=$(stat -c%s "$uimage")
p1_bytes=$(size_of "$p1")
[ "$uimage_bytes" -le "$p1_bytes" ] || die "$uimage is $uimage_bytes bytes, p1 only holds $p1_bytes"

m1=$(mktemp -d)
m2=$(mktemp -d)
m3=$(mktemp -d)
mi=$(mktemp -d)
# 失败或中断时兜底卸载并删掉挂载点
cleanup() {
	run umount "$m3" 2>/dev/null || true
	run umount "$m2" 2>/dev/null || true
	run umount "$m1" 2>/dev/null || true
	run umount "$mi" 2>/dev/null || true
	rmdir "$m1" "$m2" "$m3" "$mi" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# p3：/persist/config.json 优先于镜像里的种子，可能被手工改过；与构建出的
# config.json 不同就问一次是否替换，不做就等于沿用 U 盘那份
if [ "$have_p3" = no ]; then
	echo "p3 $p3: no $PERSIST_LABEL partition, skipping /persist/config.json"
elif [ ! -e "$CONFIG" ]; then
	echo "p3: $CONFIG not built, skipping /persist/config.json"
elif [ "${DRY_RUN:-0}" = 1 ]; then
	echo "p3: DRY_RUN, would compare /persist/config.json with $CONFIG"
else
	run mount "$p3" "$m3"
	if [ ! -e "$m3/config.json" ]; then
		echo "p3: no /persist/config.json, the image seed stays in charge"
	elif cmp -s "$CONFIG" "$m3/config.json" 2>/dev/null; then
		echo "p3: /persist/config.json already matches $CONFIG"
	else
		echo "p3: /persist/config.json differs from $CONFIG"
		if [ -t 0 ]; then
			printf 'p3: replace it on %s? [y/N] ' "$dev"
			read -r ans || ans=
		else
			echo "p3: stdin is not a tty, keeping the U-disk copy"
			ans=
		fi
		case "${ans:-}" in
		[yY]*)
			run cp -p "$m3/config.json" "$m3/config.json.bak"
			run cp "$CONFIG" "$m3/config.json"
			;;
		*) echo "p3: kept the U-disk /persist/config.json" ;;
		esac
	fi
	run sync
	run umount "$m3"
fi

# p1：FAT 分区，只放 fit.itb；-c 按内容比较，内核没变就不重传
echo "p1 $p1 <- $UIMAGE as fit.itb ($uimage_bytes bytes)"
run mount "$p1" "$m1"
run rsync -c --info=progress2 "$uimage" "$m1/fit.itb"
run sync
run umount "$m1"

# p2：loop 挂载 ext4 rootfs 镜像后 rsync 展开，--delete 清掉新镜像里已删除的文件
echo "p2 $p2 <- $ROOTFS"
run mount -o loop,ro "$rootfs" "$mi"
run mount "$p2" "$m2"
run rsync -aHAX --numeric-ids --info=progress2 --delete --exclude=/lost+found "$mi/" "$m2/"
run sync
run umount "$m2"
run umount "$mi"

rmdir "$m1" "$m2" "$m3" "$mi"
trap - EXIT INT TERM
echo "update-usb.sh: done, $dev p1 + p2 refreshed"
