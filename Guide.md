# 构建命令

# uboot设置env从U盘启动，未插U盘，检测不到则从默认内部启动
# IPQ60XX DRAM地址映射从0x40000000起，再留部分余量给NSS和其他关键保留区
setenv bootcmd 'usb start; if fatload usb 0:1 0x44000000 fit.itb; then bootm 0x44000000; else mmc dev 0; mmc read 0x44000000 0x4222 0x3000; bootm 0x44000000; fi'
saveenv
printenv bootcmd
reset

### 基础版 uimage rootfs
### eMMC 固定布局
# p16: 0:HLOS，只放 fit.itb（kernel + dtb + initramfs，cmdline 内嵌）
# p18: rootfs，ext4，initramfs 启动后挂载到 /persist
# -Q 不把各 derivation 的构建日志转发到终端
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./devices/jdcloud-ax6600/images/ax6600-rootfs.nix \
    -A outputs.uimage \
    -o result-uimage \
&& nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./devices/jdcloud-ax6600/images/ax6600-rootfs.nix \
    -A outputs.rootfs \
    -o result-rootfs \
    && md5sum result-uimage result-rootfs

# 刷写
scp result-uimage root@<device>:/tmp/fit.itb
dd if=/tmp/fit.itb of=/dev/mmcblk0p16 bs=4M conv=fsync
sync
# 测试 eMMC 启动前拔掉 U 盘，U-Boot 会优先从 U 盘加载 fit.itb

### USB ext4 版
# rootfs：完整 ext4 镜像（自带 /bin、/etc、fifo）
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./devices/jdcloud-ax6600/images/ax6600-usb-ext4.nix \
    -A outputs.rootfs \
    -o result-usb-ext4-rootfs
# Kernel
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./devices/jdcloud-ax6600/images/ax6600-usb-ext4.nix \
    -A outputs.uimage \
    -o result-usb-ext4-uimage

# md5
md5sum result-usb-ext4-rootfs result-usb-ext4-uimage

# 在线 userspace 升级（在仓库 nix-shell 中执行；不更新 p16 内核）
nix-build -Q \
  --arg device 'import ./devices/jdcloud-ax6600' \
  -I "liminix-config=$PWD/devices/jdcloud-ax6600/images/ax6600-rootfs.nix" \
  -I "liminix-deployment=$PWD/devices/jdcloud-ax6600/config.nix" \
  -I "liminix-firewall=$PWD/devices/jdcloud-ax6600/config_firewall.nix" \
  -A outputs.updater \
  -o result-updater

# --fast 通过 restart-services 执行 activate /，不重启设备
./result-updater/bin/update.sh --fast root@<device>

# U盘系统里的内容，两个分区（GPT 自己建，见下面"U 盘分区与刷写"）
# p1: FAT，只放 fit.itb（内核 FIT = kernel + dtb，cmdline 内嵌，U-Boot 按这个名字 fatload）
# p2: rootfs（ext4），GPT 分区名必须是 liminix-root（root=PARTLABEL=liminix-root）
### U 盘分区 
nix shell nixpkgs#gptfdisk
# Use -g to override 强制重新分区
sudo sgdisk -o \
    -n 1:0:+64M   -c 1:boot            -t 1:ef00 \
    -n 2:0:0      -c 2:liminix-root    -t 2:8300 \
    /dev/sdX
# 如果无法完成，可先清理擦除后再进行上一步
# 谨慎使用
sudo wipefs -a /dev/sd*
# 
sudo partprobe /dev/sdX

# # 首次需要格式化 p1 p2
nix shell nixpkgs#e2fsprogs
sudo mkfs.vfat -F 16 -n BOOT /dev/sdX1
sudo mkfs.ext4 -m 1 -L liminix-root /dev/sdX2

# 部署参数在建构时固定：修改 config.nix，或用 -I liminix-deployment=... 指定文件，
# 然后重新构建并更新镜像。运行时不读取 /etc/liminix/config.json。
# update-usb.sh 全量同步 p2，但保留 /var/lib/liminix 状态。
# kernel/initramfs 变化刷新 p16；完整 rootfs 镜像变化刷新 p18；仅 userspace
# 变化可使用 updater。

# WAN 侧：s6 oneshot wan-if 按 wan/vlan 决定 PPPoE 跑在 wan 还是新建的 wan.<vid> 上
# （MTU/MRU 随之 1488 / 1492），所以 PPPoE 服务名是 wan-if.pppoe：
s6-rc -d change wan-if.pppoe   # 停
s6-rc -u change wan-if.pppoe   # 起
# wan/vlan 变更需要重新构建镜像

# 检查wifi状态：
iw dev
hostapd_cli -i wlan24g status    # wlan24g=2.4G，wlan58g=5.8G
cat /run/art/mac.24g /run/art/mac.58g
# 服务名形如 wlan24g.link.hostapd / wlan58g.link.hostapd，用 s6-rc list 查：
s6-rc -d change wlan24g.link.hostapd   # 停
s6-rc -u change wlan24g.link.hostapd   # 起

# ttl 命令
sudo nix-shell -p picocom --run "picocom -b 115200 /dev/ttyUSB0"


# 设备上首次配置tailscale的流程

# tailscale up 需要浏览器授权，在路由器上就跑成「打印链接」的形式
#    --netfilter-mode=off：不让 tailscaled 去 fork iptables 管理 ts-input/ts-forward，防火墙交给 liminix 自己的 nftables。
#    --accept-dns=false：/etc/resolv.conf 是软链到 /run/resolv.conf、由 WAN 的 resolvconf 服务在管，别让 tailscale 接管。
#    --force-reauth #非必要
tailscale up --netfilter-mode=off --accept-dns=false --accept-routes --advertise-routes=10.10.x.x/24
tailscale status
ip addr show tailscale0
