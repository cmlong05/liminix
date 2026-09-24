# JDCloud AX6600 (RE-CS-02) — Liminix NSS 满血有线/无线 bring-up 计划

> 分支：`nss`（HEAD `266b23f`）　
> 内核基线：**Linux 6.18.52**　
> 目标：有线 + 无线走 NSS 满血路径
> 参考实现：
  **VIKINGYFY/immortalwrt `main`**（6.18 + NSS 代，唯一同内核版本的实证组合）、
  **LiBwrt/LibWrt `25.12-nss`**（6.12，中文社区「满血 NSS」参考）

> 本文只写**计划**。
> 未确认前不构建、不提交（见仓库根 `AGENTS.md`）。

---

### 1. 当前网络服务侧（换镜像形态时会碰）


* 存在问题：
  `ax6600-lan.nix` 加 `services.packet_forwarding` 和手写的
  `services.nat`（`oifname ppp0 masquerade`）。
  **不能用 `modules/firewall`**：它的 `build` 一定依赖一个 kmodloader 服务，而
  `pkgs/liminix-tools/modules/default.nix` 的注释写明 kmodloader **服务**在 fullSystem 镜像里不可能
  存在（需要 `kernel.modulesupport`，而 fullSystem 把整个 rootdir 嵌进同一个 kernel derivation → 成环）。
  NB：`ax6600-lan-ram.nix`（有线版）也会拿到 `services.nat`，但它没有 `preloadModules`，模块不会加载，
  那段 nft 会失败——那个镜像要 NAT 得把这几项写成 `=y`。

* 本设备还没有 eMMC rootfs/updater 输出；`hardware.rootDevice` 是 `/dev/mtdblock0` 占位。

---

## 2. 参考项目与来源台账

### 2.1 参考矩阵

| 来源 | ref | 提供什么 | 在本计划中的角色 |
|---|---|---|---|
| `VIKINGYFY/immortalwrt` | `main`（qualcommax `KERNEL_PATCHVER:=6.18`） | `package/qca-nss/*` 全套模块打包、`files/.../ipq6018-ess.dtsi` + `ipq6018-nss.dtsi`、`dts/ipq6010-re-cs-02.dts` + `ipq6010-re-cs.dtsi`、`patches-6.18/` 的 NSS 补丁、CLO QSDK pin 与其 6.18 compat 补丁 | **主参考**（唯一 6.18+NSS 的实证组合） |
| `LiBwrt/LibWrt` | `25.12-nss`（`KERNEL_PATCHVER:=6.12`） | 「IPQ60XX/IPQ807X 满血 NSS」参考实现、`qosmio/nss-packages` feed、NSS WiFi offload 的 mac80211 补丁、`jdcloud_re-cs-02` 设备定义 | 次要参考；N6 的评估来源 |
| `qosmio/nss-packages` | `NSS-12.5-K6.x` | QSDK 模块的 Kconfig/打包（`NSS_MEM_PROFILE_*`、`NSS_DRV_WIFIOFFLOAD_ENABLE` …） | 参考（VIKINGYFY 不用这个 feed，自己带补丁） |
| `qosmio/qca-sdk-nss-fw` | `v2025.05.01` | `nss-firmware-2025.05.01.tar.zst`（sha256 `10a4b1e6…d7abb0`）→ ipq60xx 装 `/lib/firmware/qca-nss0-retail.bin` | NSS 固件来源（闭源 blob） |
| git.codelinaro.org QSDK（第一方） | `nss-dp d8f802f(2026-01-19)`、`qca-ssdk d9a1964(2025-11-14)`、`nss-drv 6aa14c7(2026-01-12, QSDK 13.1)`、`nss-clients 51be82d`、`qca-nss-ecm 8c7355b(2026-04-03)`、`nss-crypto 60e27b9`、`qca-mcs da120b1`、`qca-nss-phy 85cb19f` | 驱动源码 | 驱动来源（第一方） |

### 2.2 落地时要逐个校验的 pin

新增 `devices/jdcloud-ax6600/nss/SOURCES.nix`，每条都按现有风格写
`path + blob + sha256 + role + note`（`sha256` 用 `nix-hash --flat --type sha256 --sri <file>`）：

* DTS：`ipq6018-ess.dtsi`（NSS 版）、`ipq6018-nss.dtsi`、`ipq6018-common.dtsi`、
  `ipq6010-re-cs.dtsi`、`ipq6010-re-cs-02.dts`（VIKINGYFY `main`）。
* 内核补丁：
  * `0103-arm64-dts-ipq6018-add-reserved-memory-nodes.patch`：加 `nss_region`（16 MiB）、
    把 `q6_region` 从 `0x5500000` 缩到 `0x4000000`、新增 `q6_etr@4eb00000`、
    `m3_dump@4ec00000`、`ramoops@4ed00000`；
  * `0600-1..8`（ECM CORE/PPPOE/bonding/LAG/macvlan/DSCPREMARK/fraglist-GRO）、
    `0602-1`（nss-drv qdisc）、`0603-1..7`（nss-clients qdisc/l2tp/pptp/iptunnel/vxlan/bridge-mgr）、
    `0604-*`（qca-mcs）、`0606-1`（ECM bridge VLAN）、`0607-*`（clients iptunnel fixes）；
  * 时钟：现有 pin 的 `0080`、`0082`、`0191`、`0920`、`0904`、`0917`（复用 `ether/` 的清单条目）。
* 模块源码：上面 2.1 表格里的 CLO 仓库（按 Makefile 里的 `PKG_SOURCE_VERSION` 取 commit），
  以及各包 `patches/*-compat-linux-6.18-*.patch`（fork 派生，见 2.3）。
* 固件：`qca-sdk-nss-fw` v2025.05.01 的 `IPQ6018/…retail_router0.bin` → `qca-nss0-retail.bin`。

### 2.3 来源政策（沿用现有风格，并记录例外）

* 第一方（CLO / OpenWrt 官方 / 内核官方）优先；上游字节不抄进仓库，构建期按
  URL+sha256 拉取。
* VIKINGYFY 的 `patches/*compat-linux-6.18*` 是 **fork 派生**，以**独立补丁文件 + sha256 +
  来源标注**的形式收录，并在台账里写明“派生自哪个 fork 的哪个文件”；不直接改外源代码。

---

## 3. 总体路线

* **内核维持 6.18.52**：与现有 pin、现有 ath11k 补丁集、`hardware.dts` 组装方式一致；
  NSS 参考实现取 **VIKINGYFY main**。
* **驱动形态 = loadable kmod**：与 OpenWrt/QSDK 一致，加载顺序
  `qca-ssdk`(30) → `qca-nss-dp`(31) → `qca-nss-drv`(32) → `ecm`；由 `pkgs/kmodloader`
  用显式 `targets` 加载（`targets` 用 depmod 名字，落地时用
  `modprobe --show-depends` 校对，必要时回落文件名）。
* **固件**：NSS blob 由驱动按名字请求：`nss_hal.c` 要的是 `qca-nss0.bin`
  （**不是** `qca-nss0-retail.bin`）。OpenWrt 装 retail 名再用
  `/etc/hotplug.d/firmware/10-qca-nss-fw` 改名/链接，**Liminix 没有 hotplug fallback**
  （`FW_LOADER_USER_HELPER=n`），所以镜像里必须直接就叫 `qca-nss0.bin`。

---

## 4. 分阶段计划

### N5 无线：ath11k 三频 * 无线分成两组（2.4g+5.8g）和（5.2g QCN9024)，共三频

#### 阶段一，先起 IPQ6010 核心支持的双频 2.4g 和 5.8g


# 阶段二，再起QCN9024外挂的5.2g
* 不要设置开机启动，由我手动开启
* **验证**：`CH`（QCN9024/QCN9074）出现，hostapd AP 可关联；
* **风险**： 同上


### N6（可选/实验）NSS WiFi offload 评估

* 依据 LibWrt 的 `package/kernel/mac80211/patches/nss/{ath11k,subsys,ath10k}` 与
  `ATH11K_NSS_SUPPORT`，以及 `NSS_DRV_WIFIOFFLOAD_ENABLE`。
* 结论必须写清：VIKINGYFY 6.18 NSS 栈**没有** ath11k NSS 补丁；官方 OpenWrt 也没有
  （issue `#23798`）；LibWrt 自称 IPQ60xx 2.4G/5G offload ✅，但 AP-VLAN 有已知问题。
* 若要做：先在 6.12+LibWrt 上复现，再评估移植到 6.18 的成本，不要一开始就动 6.18。

### N7a：eMMC rootfs 形态（2026-09-24 起，最终形态；N7 的第一半）

**两个产物写进两个已存在的 GPT 分区**，不是一个整盘镜像——整盘镜像会重写 GPT 并毁掉 `+0:ART+`：

| 产物 | 内容 | 写到 |
|---|---|---|
| `outputs.uimage` | kernel + dtb 的 FIT，cmdline 嵌在镜像里 | `0:HLOS` |
| `outputs.rootfs` | squashfs 镜像（`modules/outputs/squashfs.nix`） | `rootfs` |

**不需要的内核工作**：eMMC 那套本来就齐（`MMC_SDHCI_MSM=y`、`SQUASHFS=y`+`SQUASHFS_XZ=y`、
`DEVTMPFS_MOUNT=y`、`EFI_PARTITION=y`）。**安装器就是现在的 fullSystem 镜像**：boot 进去 →
把两个产物 `dd` 到对应分区 → reboot；搞砸了用 web uploader 把 fullSystem uImage 传回去恢复。
**不要用 `outputs.updater`**（它是构建机上的脚本，靠 `min-copy-closure` 推给**可写根**，
我们的 squashfs 根只读），也不要 `outputs.mbrimage`（带新分区表的整盘镜像）。

**这个形态的收益不只是"换个介质"**：

* `embedsInitramfs=false` → `config.system.outputs.kernel.modulesupport` 可用 → 模块改由
  **标准 `pkgs/kmodloader` 服务**加载（原来是 preinit 读 `boot.initramfs.preloadModules`）；
* 同一理由让 **`modules/firewall` 可用** → NAT（默认规则里的 `nat-tx: oifname @wan masquerade`）
  和整套默认网关规则来自模块；`ax6600-nss-ram.nix` 那份手写 masquerade 只留给 fullSystem 形态；
* 固件与 ART 校准不必再嵌进 initramfs（N7 原本那两条的前提）。

**新建 `ax6600-rootfs.nix`**（不 import `modules/outputs/initramfs.nix`）：

* `services.modules = pkgs.kmodloader.override { kernel = config.system.outputs.kernel; … }`，
  模块目标用共用的 `devices/jdcloud-ax6600/nss/targets.nix`；
* `services.firewall`（zones lan/wan）+ 共用的 `services.packet_forwarding`（仍是 sysctl，和规则无关）；
* `/lib/firmware/qca-nss0.bin`——NSS 固件必须在 `services.modules` insmod 之前就在磁盘上；
* `services.netfilter-sysctls`：ECM 的 conntrack sysctl **不能再走 `early.sysctl`**——rc.init 跑
  `/etc/sysctl.sh` 时 `nf_conntrack` 还没被 kmodloader 加载，写入会打空；改成依赖
  `services.modules` 的 oneshot；
* `hardware.rootDevice = "PARTLABEL=rootfs"`、`rootfsType = "squashfs"`，cmdline 必须显式带
  `root=`/`rootfstype=`/`rootwait`/`init=/bin/init`（NSS 那份 `lib.mkForce` 里没有它们，照抄起不来）；
* **加载顺序**：模块改由服务加载后，`lan1..lan4`/`wan` 的 link 服务要等 netdev 出现。`ifwait` 没有
  超时（`-t` 只在 `ifwait.fnl` 里解析、从未使用），而 `services.modules` 无依赖、会并行启动，所以
  LAN 会在 insmod 之后自己起来——不需要显式依赖，但比 initramfs 形态慢一拍。`services.firewall`
  自带它的 kmodloader（`build` 会把它加进 `dependencies`），`services.netfilter-sysctls` 显式依赖
  `services.modules`。

**两处定义冲突**（都在求值期报错，不是静默降级）：

* `modules/firewall` 写 `NF_TABLES = "m"`，板级为 ECM 刻意写 `"y"`（`NFT_COMPAT` 与
  `NF_TABLES_BRIDGE` 依赖它）→ 板级那份改成 `lib.mkForce "y"`；
* `hardware.rootDevice` 板级从 `/dev/mtdblock0` 占位改成 `lib.mkDefault`，让组合去命名真分区。

**还没做（下一步）**：AHB 无线。`devices/jdcloud-ax6600/wireless/default.nix` 用
`boot.initramfs.preloadFirmware` 交固件，而那个选项只声明在 `modules/outputs/initramfs.nix` 里；
rootfs 形态要把同一批 blob（`IPQ6018/q6_fw.*`、`m3_fw.*`、
`ath11k/IPQ6018/hw1.0/{board-2.bin,cal-ahb-c000000.wifi.bin}`）放到 `/lib/firmware`。
在固件交付改造完成前，`ax6600-rootfs.nix` 是**有线形态**。

**上机前必须确认**：eMMC 的 GPT 分区名与编号（`ls /dev/disk/by-partlabel/`、
`cat /proc/partitions`）——`root=PARTLABEL=rootfs` 与 `0:HLOS` 槽都依赖它，现在只是照社区
dual-boot 布局写的。

### N7 产品化
* 内核和用户态软件是自动分区，还是分地方配置的？
  比如，iperf3在最终产品里，不应该rootfs/HLOS里，而应该在用户态里
* eMMC 可写 rootfs + `outputs.updater`（参考 `turris-omnia` 的 `/dev/mmcblk0p1` 形态，
  本板 GPT：`0:HLOS` / `rootfs` / `0:ART`）；
* **per-unit 数据统一从 `0:ART` 取**：MAC（0x0）落到 `local-mac-address`
  （`label-mac-device = &dp1` 已由 DTS 声明）、AHB/PCI 校准（0x1000 起 0x20000），
  由启动早期（preinit 或足够早的服务，必须先于驱动 probe）取出写进 `/lib/firmware`；
  镜像只带通用固件（q6/m3、board-2、regdb、NSS 固件）。
* **删除建构期嵌入**：`wireless/default.nix` 的 `firmwarePkg` 现在把
  `art/mmc_0-ART.bin`（`.gitignore` 忽略、未进版本库，新克隆会缺件）的 0x1000 切片
  烧进 initramfs。那是 RAM 单文件镜像的临时手段（preinit 早于 activate 建出
  `/lib/firmware`），且只对本机成立，产品化时按上一条改掉。
* 三频配置：PCI QCN9074 = 5.2G（ch36–64）、AHB 5G pdev = 5.8G（ch149+）、AHB 2.4G；

---

## 5. 验收与「满血」判据

| 阶段 | 判据 |
|---|---|
| N0 | `nix-instantiate --parse` 通过 |
| N1 | dtb 含 `ess-switch` / `nss@40000000` / `dp1..dp5`；真机无 panic |
| N2 | `lan1..lan4` + `wan` 存在、链路 up、DHCP/ssh 可用、`wan` 2500 Mbps |
| N3 | ✅ 真机：`NSS fw version: NSS.FW.12.5-210-CP.R` + `NSS core 0 booted successfully`；`/proc/sys/dev/nss/` 可读（debugfs 需手工 mount）；计数增长待验 |
| N4 | 首启：ECM init `-22`，缺 `NETFILTER_FAMILY_BRIDGE`（见 D.20）；修好后待验 ECM offload 命中（`ecm_db` 计数增长）+ 转发热路径 A53 占用显著下降 + PPPoE/2.5G 吞吐基准 |
| N5 | ✅ 双频都起 + **关联两个频段都验完**：`iw dev` 两个 AHB pdev、`FW memory mode: 1`、Q6 跑 `WLAN.HK.2.12-01460`；9-23 热替换固件那一版 `CHEN`/`CHEN_5g` 两个 hostapd 都 `state=ENABLED`；9-24 在「pin 固件 + `CRYPTO_MICHAEL_MIC=y` 都进镜像」这一版上复验，两个 AP 同样都 `state=ENABLED`（5.8G 不再「待起」），dmesg 无 BADVA、无 CE IRQ abort；9-24 再用一台密码已知的客户端把两个 SSID 各连一次，AP 侧两条都到 `hostapdWPAPTKState=11`（PTKINITDONE）+ `AUTHORIZED`。当时那个 PSK 不符的循环客户端（`invalid MIC in msg 2/4`、`AP-STA-POSSIBLE-PSK-MISMATCH`）是它自己存了错的凭据/安全类型，AP 侧无责。转发已接上（`start` 把 pdev 的 netdev join 进 `int`），待真机复验 DHCP 租约。**Q6 固件必须 pin fork 那一版**，linux-firmware 的 2.7.0.1 让 5.8G 必崩（见 N5 阶段一） |

**明确不承诺**：满血 ≠ WiFi offload（6.18 栈没有）；满血 ≠ 保证 2.5G 线速（社区反馈
有 2.5G 口只协商到 1G 的案例，链路速率要单独实测）。

构建命令沿用现有惯例（N2 起镜像形态可能换成 tftpboot）：

```console
$ nix-build -Q --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-lan-ram.nix -A outputs.uimage -o result-lan-ram
$ sh md5_result.sh
```

---

## 附录 

### QEMU 这条验证路径正式关闭（不要再试）



