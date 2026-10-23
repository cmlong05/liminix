# 构建命令

# uboot设置env从U盘启动，未插U盘，检测不到则从默认内部启动
# IPQ60XX DRAM地址映射从0x40000000起，再留部分余量给NSS和其他关键保留区
# uboot下
setenv bootcmd 'usb start; if fatload usb 0:1 0x44000000 fit.itb; then bootm 0x44000000; else mmc dev 0; mmc read 0x44000000 0x4222 0x3000; bootm 0x44000000; fi'
saveenv
printenv bootcmd
reset

# openwrt 或 liminix 下使用 fw_setenv,先验证
fw_printenv
fw_setenv bootcmd 'usb start; if fatload usb 0:1 0x44000000 fit.itb; then bootm 0x44000000; else mmc dev 0; mmc read 0x44000000 0x4222 0x3000; bootm 0x44000000; fi'
fw_printenv


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
# 虽然三个config设置不同，但是当前阶段构建出的kernel相同-20261021
### 修改分区名字后验证，确定与config.nix中的相同

### 上传
scp -O result-uimage root@<device>:/tmp/
scp -O result-rootfs root@<device>:/tmp/

# 刷写Kernel
uimage=/tmp/result-uimage
md5sum $uimage
size=$(wc -c < "$uimage")
dd if="$uimage" of=/dev/mmcblk0p16 bs=1M

# 验证
dd if=/dev/mmcblk0p16 bs="$size" count=1 | md5sum
dd if=/dev/mmcblk0p17 bs="$size" count=1 | md5sum

# 确保 mmcblk0p18 的 PARTLABEL 正确与config.nix中保持一致 PARTLABEL=rootfs
blkid | grep /dev/mmcblk0p18
# 刷写rootfs
image=/tmp/root.ext4
# 先部分验证
dd if="$image" bs=4M count=10 | md5sum
dd if=/dev/mmcblk0p18 bs=4M count=10 | md5sum
# 刷写
dd if="$image" of=/dev/mmcblk0p18 bs=4M
# 再同上部分验证一次

# 扩容到实际大小
e2fsck -f /dev/mmcblk0p18
resize2fs /dev/mmcblk0p18
e2fsck -f /dev/mmcblk0p18
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
# 重新探测
sudo partprobe /dev/sdX

# # 首次需要格式化 p1 p2 （下面设置的是LABEL，区别于sgdisk的PARTLABEL）
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

### sing-box 透明分流与 LAN SOCKS5

规则完全由运行时文件提供，不需要写入部署配置或在构建时下载。首次启动时
配置模板复制到：

```sh
/etc/sing-box/config.json.template
/var/lib/liminix/sing-box/config.json
```

手动提供两份 source rule-set JSON：

```text
/var/lib/liminix/sing-box/proxy.json
/var/lib/liminix/sing-box/bypass.json
```

文件格式：

```json
{
  "version": 1,
  "rules": [
    {
      "domain_suffix": [
        ".example.com"
      ]
    }
  ]
}
```

编辑运行时配置，将 `proxy` 出站骨架改成实际代理，保持 tag 为 `proxy`：

```sh
vi /var/lib/liminix/sing-box/config.json
sing-box check -c /var/lib/liminix/sing-box/config.json
s6-rc -d change sing-box
s6-rc -u change sing-box
```

已有 `config.json` 不会随镜像覆盖。两份规则文件缺失或配置校验失败时，
服务不安装透明路由，LAN 保持直连。

透明流量中的 DNS 固定直连，之后按 `bypass` 规则直连、私网直连、`proxy`
规则走代理，其余直连。LAN 可使用两个无认证 SOCKS5 入口：

```text
<router-lan-ip>:1080  TCP/UDP 固定走 proxy，不受 rule-set 影响
<router-lan-ip>:1081  TCP/UDP 固定走 direct，不受 rule-set 影响
```

两个入口只从 `@lan` 入方向放行，WAN 地址不能访问。`1080` 的域名解析和
DNS 流量随该入口走 `proxy`；`1081` 与透明流量不经过代理 DNS。dnsmasq
继续直接使用 WAN DNS。

查看状态和日志：

```sh
s6-rc -a list | grep sing-box
ip rule show
ip route show table 233
ip -6 route show table 233
tail -Fn 100 /run/service/sing-box-log/psing-box/current
```

故障旁路：停止服务会幂等删除策略规则和表 233 的路由，LAN 恢复直连。
dnsmasq 不受 sing-box 状态影响。配置缺失或 `sing-box check` 失败时服务
不安装透明路由。

```sh
s6-rc -d change sing-box
ip rule show
ip route show table 233
```

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


# 内核Kernal和用户态同时更新的升级方式：
update.sh 里的选项说明：
--no-reboot
  = 复制新 closure
  + 执行 /bin/install
  + 建立时间戳配置链接
  + 不 activate、不重启

--no-reboot + /activate /
  = 上面全部
  + 更新 /etc、/bin 等 FHS 文件
  + 把 /etc/s6-rc/compiled 指向新服务数据库
  + 但不切换当前运行中的 s6 数据库，也不重启服务

--fast
  = 上面的“安装 + activate”
  + s6-rc-update 切换到新数据库
  + 重启发生变化的服务
  + 启动 default 服务集合
  + 不重启设备

## 修复updator bug后
直接不带参数，会自动完成所有任务
install + activate / + reboot
  = --no-reboot
  + 重启


# 内核和用户态同时更新
## 旧方式
./result-updater/bin/update.sh --no-reboot root@<device>
ssh root@<device> '/activate /'
# 手动刷入同一配置构建的 fit.itb 到 p16
ssh root@<device> 'sync; reboot'

## 更新bug后的方式
# 先手动刷入同一配置构建的 fit.itb
./result-updater/bin/update.sh root@<device>

