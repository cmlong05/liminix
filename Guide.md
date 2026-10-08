# 构建命令
# -Q 不把各 derivation 的构建日志转发到终端
# 指定配置文件 （此项设定和现有持续化config路径是否和谐？）
# -I liminix-deployment=./devices/jdcloud-ax6600/config-lab.nix

# uboot设置env从U盘启动，未插U盘，检测不到则从默认内部启动
setenv bootcmd 'usb start; if fatload usb 0:1 0x44000000 fit.itb; then bootm 0x44000000; fi; bootipq'
saveenv
printenv bootcmd
reset

### 基础版 uimage rootfs
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

### USB squashfs版
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb.nix \
    -A outputs.rootfs \
    -o result-usb-rootfs

nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb.nix \
    -A outputs.uimage \
    -o result-usb-uimage

sh md5_result.sh

### USB ext4 版
# rootfs：完整 ext4 镜像（自带 /bin、/etc、fifo）
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb-ext4.nix \
    -A outputs.rootfs \
    -o result-usb-ext4-rootfs \
# Kernel
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-usb-ext4.nix \
    -A outputs.uimage \
    -o result-usb-ext4-uimage \

sh md5_result.sh


# U盘系统里的内容，三个分区（GPT 自己建，见下面"U 盘分区与刷写"）
# p1: FAT，只放 fit.itb（内核 FIT = kernel + dtb，cmdline 内嵌，U-Boot 按这个名字 fatload）
# p2: rootfs（squashfs），GPT 分区名必须是 liminix-root（root=PARTLABEL=liminix-root）
# p3: 持续化存储，ext4，卷标 liminix-persist，挂 /persist

### U 盘分区
nix shell nixpkgs#gptfdisk
sudo sgdisk -o \
    -n 1:0:+64M   -c 1:boot            -t 1:ef00 \
    -n 2:0:+6144M -c 2:liminix-root    -t 2:8300 \
    -n 3:0:0      -c 3:liminix-persist -t 3:8300 \
    /dev/sdX
sudo partprobe /dev/sdX

# # 首次需要格式化p1 p2 p3 , 注意卷标，系统靠它挂载
nix shell nixpkgs#e2fsprogs
sudo mkfs.vfat -F 16 -n BOOT /dev/sdX1
sudo mkfs.ext4 -m 1 -L liminix-root /dev/sdX2
sudo mkfs.ext4 -m1 -L liminix-persist /dev/sdX3

# p3会被挂载到/persist, 如果把其中的 config.json 删掉后重启即回到镜像里的默认值文件。 
# 不是合法 JSON 会整份回落到镜像里的种子并在日志里报错；
# 少了某个键时，hostname/地址/DHCP/resolvers 各自回落到建构期默认值
# PPPoE 账号则没有默认值可用、拨号服务起不来（LAN 和 ssh 不受影响，可以ssh进去改回来）
# 值一律写成 JSON 字符串（prefixLength 要写成 "24"：读的那侧只认字符串和对象，数字/布尔等于没有这个键）；
# wan.vlan 同理（写成 "1510"）：不写这个键或写 null，就是该环境不做 VLAN。

# WAN 侧：s6 oneshot wan-if 按 wan/vlan 决定 PPPoE 跑在 wan 还是新建的 wan.<vid> 上
# （MTU/MRU 随之 1488 / 1492），所以 PPPoE 服务名是 wan-if.pppoe：
#   s6-rc -d change wan-if.pppoe   # 停
#   s6-rc -u change wan-if.pppoe   # 起
# 改 wan/vlan 需要重启（或 s6-rc -d/-u change wan-if wan-if.pppoe）才生效。


# per-unit 数据开机时从 0:ART 读出（devices/jdcloud-ax6600/art.nix）：
#   art-extract（rc-init.d/05-art，先于 modules）：物化 /lib/firmware/ath11k 为
#     可写目录、写入 cal-ahb-c000000.wifi.bin、导出本机 MAC 到 /run/art/。
#   art-apply（s6 oneshot）：给 lan1..4/wan 设本机 MAC；按 MAC 把 AHB 两个 netdev
#     改名成 wlan24g / wlan58g。
# 因此接口名固定为 wlan24g(2.4G) / wlan58g(5.8G)，无线 MAC 由 ath11k 从 cal 自动设。

# wifi 开机自动启动：由 s6 长驻的 hostapd 服务拉起，没有手动启动脚本。
# SSID/密码/信道取自 /persist/config.json（改后会自动重启 hostapd）。
# 检查状态：
iw dev
hostapd_cli -i wlan24g status    # wlan24g=2.4G，wlan58g=5.8G
cat /run/art/mac.24g /run/art/mac.58g
# 服务名形如 wlan24g.link.hostapd / wlan58g.link.hostapd，用 s6-rc list 查：
#   s6-rc -d change wlan24g.link.hostapd   # 停
#   s6-rc -u change wlan24g.link.hostapd   # 起

# ttl 命令
sudo nix-shell -p picocom --run "picocom -b 115200 /dev/ttyUSB0"


# 设备上首次配置tailscale的流程

# tailscale up 需要浏览器授权，在路由器上就跑成「打印链接」的形式
# 因为镜像里没有 iptables（我特意去掉了那层 wrap），建议第一次就这么跑：

tailscale up --force-reaut --netfilter-mode=off --accept-dns=false --accept-routes --advertise-routes=10.10.x.x/24

  • --netfilter-mode=off：不让 tailscaled 去 fork iptables 管理 ts-input/ts-forward，防火墙交给 liminix 自己的 nftables。
  • --accept-dns=false：/etc/resolv.conf 是软链到 /run/resolv.conf、由 WAN 的 resolvconf 服务在管，别让 tailscale 接管。

tailscale status
ip addr show tailscale0
