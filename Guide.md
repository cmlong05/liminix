# 构建命令
# -Q 不把各 derivation 的构建日志转发到终端
# 指定配置文件
# -I liminix-deployment=./devices/jdcloud-ax6600/config-lab.nix


# 单文件 RAM 镜像（lan1..lan4 桥接 + 2.5G PPPoE + 2.4g + 5.8g + NSS）
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-nss-ram.nix \
    -A outputs.uimage \
    -o result-nss-lan-ram && \
    sh md5_result.sh

# uimage rootfs
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-rootfs.nix \
    -A outputs.uimage \
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

# U 盘准备：GPT + 一个名为 liminix-root 的分区（root=PARTLABEL=liminix-root，
# 分区名必须一致；兜底可把 ax6600-usb.nix 里的 rootDevice 换成 /dev/sda1）
sudo sgdisk -o -n 1:2048:0 -c 1:liminix-root -t 1:8300 /dev/sdX
sudo partprobe /dev/sdX
sudo dd if=result-usb-rootfs of=/dev/sdX1 bs=1M conv=fdatasync status=progress

# 启动：把 result-usb-uimage 从 U-Boot 网页上传，和 -ram 镜像同一个入口，
# 从内存 bootm；也可以 dd 进 eMMC 的 0:HLOS，两种方式都从 U 盘挂根。
# 起不来就重新上传 ram 镜像（ax6600-nss-ram.nix）恢复。
# 注意：拔盘重启时 rootwait 是无限等设备，不是回退。


# 无线（2.4G = CHEN，5.8G = CHEN_5g，密码 88888888）：这两个 AP 不由开机自启，
# 进系统后手动开。脚本按频段找 AHB pdev 的 netdev，起来后把它 join 进 int 桥。
ssh root@10.10.10.10
wlan-2g                # wlan-2g status / wlan-2g stop 同理
wlan-5g
iw dev                 # 两个 pdev 的 netdev；hostapd_cli -p /run/hostapd-2g status


# ttl 命令
sudo nix-shell -p picocom --run "picocom -b 115200 /dev/ttyUSB0"
