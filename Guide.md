# 构建命令
# -Q 不把各 derivation 的构建日志转发到终端
# 指定配置文件 （此项设定和现有持续化config路径是否和谐？）
# -I liminix-deployment=./devices/jdcloud-ax6600/config-lab.nix

# uboot设置env从U盘启动
setenv bootcmd 'usb start; if fatload usb 0:1 0x44000000 fit.itb; then bootm 0x44000000; fi; bootipq'
saveenv
printenv bootcmd
reset

# U盘系统里的内容，三个分区（GPT 自己建，见下面"U 盘分区与刷写"）
# p1: FAT，只放 fit.itb（内核 FIT = kernel + dtb，cmdline 内嵌，U-Boot 按这个名字 fatload）
# p2: rootfs（squashfs），GPT 分区名必须是 liminix-root（root=PARTLABEL=liminix-root）
# p3: 持续化存储，ext4，卷标 liminix-persist，挂 /persist


# uimage rootfs
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-rootfs.nix \
    -A outputs.uimage \
&& nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-rootfs.nix \
    -A outputs.rootfs \
    -o result-rootfs \
    && sh md5_result.sh


# USB 根：内核形状与 rootfs 形态相同（FIT = kernel + dtb，无 rootdir），
# 根文件系统在 U 盘的 liminix-root 分区上；eMMC 完全不被写。
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb.nix \
    -A outputs.uimage \
    -o result-usb-uimage \
    && nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb.nix \
    -A outputs.rootfs \
    -o result-usb-rootfs \
    && sh md5_result.sh

# U 盘分区与刷写
nix shell nixpkgs#gptfdisk
sudo sgdisk -o \
    -n 1:0:+64M   -c 1:boot            -t 1:ef00 \
    -n 2:0:+6144M -c 2:liminix-root    -t 2:8300 \
    -n 3:0:0      -c 3:liminix-persist -t 3:8300 \
    /dev/sdX
sudo partprobe /dev/sdX

# 格式化 p1 内核分区
sudo mkfs.vfat -F 16 -n BOOT /dev/sdX1
# 复制kernel(注意修改文件名)
sudo mount /dev/sdX1 /mnt
sudo cp result-usb-uimage /mnt/fit.itb && sync
sudo umount /mnt

# p2：squashfs 原样 dd 进分区（分区比文件系统大即可，其余是空洞）
# 进一步考虑改成 ext4，或者看什么分区内型适合nixos
sudo dd if=result-usb-rootfs of=/dev/sdX2 bs=4M conv=fdatasync status=progress

# p3：ext4 空盘，卷标必须和 ax6600-usb.nix 的 persistLabel 一致，hook 靠它挂
nix shell nixpkgs#e2fsprogs
sudo mkfs.ext4 -L liminix-persist /dev/sdX3
# p3会被挂载到/persist, 如果把其中的 config.json 删掉后重启即回到镜像里的默认值文件。 
# 不是合法 JSON 会整份回落到镜像里的种子并在日志里报错；
# 少了某个键时，hostname/地址/DHCP/resolvers 各自回落到建构期默认值
# PPPoE 账号则没有默认值可用、拨号服务起不来（LAN 和 ssh 不受影响，可以ssh进去改回来）
# 值一律写成 JSON 字符串（prefixLength 要写成 "24"：读的那侧只认字符串和对象，数字/布尔等于没有这个键）。


# ext4 根变体
# rootfs
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb-ext4.nix \
    -A outputs.rootfs \
    -o result-usb-ext4-rootfs \
    && sh md5_result.sh

# 或者 方便直接拷贝
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb-ext4.nix \
    -A outputs.bootablerootdir \
    -o result-usb-ext4-tree

# Kernel
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb-ext4.nix \
    -A outputs.uimage \
    -o result-usb-ext4-uimage \
    && sh md5_result.sh

# 写入U盘，两种方式，一种直接将dd整个分区，之后修改扩容
# 一种挂载分区后，rsync过去

# 修改uboot的环境变量第一顺位为usb
setenv bootcmd 'usb start; fatload usb 0:1 0x44000000 fit.itb; bootm 0x44000000'
saveenv

# 手动开wifi。脚本按频段找 AHB pdev 
ssh root@10.10.10.10
# wlan-2g status / wlan-2g stop 
wlan-2g
wlan-5g
# 检查wifi状态
iw dev
hostapd_cli -p /run/hostapd-2g status

# ttl 命令
sudo nix-shell -p picocom --run "picocom -b 115200 /dev/ttyUSB0"
