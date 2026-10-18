# 构建命令

# uboot设置env从U盘启动，未插U盘，检测不到则从默认内部启动
setenv bootcmd 'usb start; if fatload usb 0:1 0x44000000 fit.itb; then bootm 0x44000000; fi; bootipq'
saveenv
printenv bootcmd
reset

### 基础版 uimage rootfs
# -Q 不把各 derivation 的构建日志转发到终端
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./devices/jdcloud-ax6600/images/ax6600-rootfs.nix \
    -A outputs.uimage \
&& nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./devices/jdcloud-ax6600/images/ax6600-rootfs.nix \
    -A outputs.rootfs \
    -o result-rootfs \
    && md5sum result result-rootfs

### USB ext4 版
# rootfs：完整 ext4 镜像（自带 /bin、/etc、fifo）
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./devices/jdcloud-ax6600/images/ax6600-usb-ext4.nix \
    -A outputs.rootfs \
    -o result-usb-ext4-rootfs \
# Kernel
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./devices/jdcloud-ax6600/images/ax6600-usb-ext4.nix \
    -A outputs.uimage \
    -o result-usb-ext4-uimage \

# md5
md5sum result-usb-ext4-rootfs result-usb-ext4-uimage


# U盘系统里的内容，三个分区（GPT 自己建，见下面"U 盘分区与刷写"）
# p1: FAT，只放 fit.itb（内核 FIT = kernel + dtb，cmdline 内嵌，U-Boot 按这个名字 fatload）
# p2: rootfs（ext4），GPT 分区名必须是 liminix-root（root=PARTLABEL=liminix-root）
# p3: 持续化存储，ext4，卷标 liminix-persist，挂 /persist

### U 盘分区 
nix shell nixpkgs#gptfdisk
# Use -g to override 强制重新分区
sudo sgdisk -o \
    -n 1:0:+64M   -c 1:boot            -t 1:ef00 \
    -n 2:0:+6144M -c 2:liminix-root    -t 2:8300 \
    -n 3:0:0      -c 3:liminix-persist -t 3:8300 \
    /dev/sdX
# 如果无法完成，可先清理擦除后再进行上一步
# 谨慎使用
sudo wipefs -a /dev/sd*
# 
sudo partprobe /dev/sdX

# # 首次需要格式化p1 p2 p3 , 注意卷标，系统靠它挂载
nix shell nixpkgs#e2fsprogs
sudo mkfs.vfat -F 16 -n BOOT /dev/sdX1
sudo mkfs.ext4 -m 1 -L liminix-root /dev/sdX2
sudo mkfs.ext4 -m1 -L liminix-persist /dev/sdX3

# p3会被挂载到/persist, 如果把其中的 config.json 删掉后重启即回到镜像里的默认值文件。 
# 不是合法 JSON 会整份回落到镜像里的种子并在日志里报错；
# 少了某个键时，hostname/地址/DHCP/resolvers 各自回落到建构期默认值
# PPPoE 账号则没有默认值可用、拨号服务起不来。LAN 和 ssh 不受影响，可以ssh进去改回来
# 值一律写成 JSON 字符串（prefixLength 要写成 "24"：读的那侧只认字符串和对象，数字/布尔等于没有这个键）
# wan.vlan 同理（写成 "1510"）：不写这个键或写 null，就是该环境不做 VLAN

# WAN 侧：s6 oneshot wan-if 按 wan/vlan 决定 PPPoE 跑在 wan 还是新建的 wan.<vid> 上
# （MTU/MRU 随之 1488 / 1492），所以 PPPoE 服务名是 wan-if.pppoe：
s6-rc -d change wan-if.pppoe   # 停
s6-rc -u change wan-if.pppoe   # 起
# 改 wan/vlan 需要重启才生效 或 如上停止再启动

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
