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
  NB：已删除的 RAM/fullSystem 形态里那份手写 `services.nat` 依赖 `preloadModules`
  把 `nft_nat`/`nft_masq` 加载进来；要更早可用就得把那几项写成 `=y`。

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

### N6（可选/实验）NSS WiFi offload 评估

* 依据 LibWrt 的 `package/kernel/mac80211/patches/nss/{ath11k,subsys,ath10k}` 与
  `ATH11K_NSS_SUPPORT`，以及 `NSS_DRV_WIFIOFFLOAD_ENABLE`。
* 结论必须写清：VIKINGYFY 6.18 NSS 栈**没有** ath11k NSS 补丁；官方 OpenWrt 也没有
  （issue `#23798`）；LibWrt 自称 IPQ60xx 2.4G/5G offload ✅，但 AP-VLAN 有已知问题。
* 若要做：先在 6.12+LibWrt 上复现，再评估移植到 6.18 的成本，不要一开始就动 6.18。

### N7a：eMMC rootfs 形态


**这个形态的收益不只是"换个介质"**：

* `embedsInitramfs=false` → `config.system.outputs.kernel.modulesupport` 可用 → 模块改由
  **标准 `pkgs/kmodloader` 服务**加载（原来是 preinit 读 `boot.initramfs.preloadModules`）；
* 同一理由让 **`modules/firewall` 可用** → NAT（默认规则里的 `nat-tx: oifname @wan masquerade`）
  和整套默认网关规则来自模块；手写 masquerade 只留给（已删除的）fullSystem 形态；
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

**AHB 无线（2026-09-25 完成交付改造）**：`devices/jdcloud-ax6600/wireless/default.nix` 原来用
`boot.initramfs.preloadFirmware` 交固件，而那个选项只声明在 `modules/outputs/initramfs.nix` 里，
所以只有 fullSystem 形态能用它。现在拆成两层（fullSystem 一侧的
`preload-firmware.nix` 后来随 RAM 形态一起删除）：

* `wireless/default.nix` —— 只留与形态无关的部分：内核配置 / `conditionalConfig.WLAN`、hostapd 与
  `wlan-2g`/`wlan-5g` 工具，并把同一批 blob 做成 `wireless.firmwareFiles`（`attrsOf package`，
  key 就是内核问的名字：`IPQ6018/q6_fw.*`、`m3_fw.*`、
  `ath11k/IPQ6018/hw1.0/{board-2.bin,cal-ahb-c000000.wifi.bin}`）；
* `wireless/rootfs-firmware.nix` —— 挂根一侧：把同一批文件装成一棵树，只把顶层目录
  `IPQ6018`/`ath11k` 做成 `/lib/firmware` 下的符号链接，于是别的模块还能往同一目录里加东西
  （`modules/wlan.nix` 的 `regulatory.db`、`ax6600-rootfs.nix` 的 `qca-nss0.bin`——`filesystem` 是
  `types.anything`，会按属性递归合并，实测四个定义合成
  `{IPQ6018, ath11k, qca-nss0.bin, regulatory.db}`）。

`ax6600-rootfs.nix`（eMMC/USB 两个挂根形态共用）现在 import 这两者，并把 `services.modules` 的
targets 从 `.wired` 换成 `.all`（`wired ++ wireless`，见 `nss/targets.nix`）——这正是当初把
targets 分成三组的原因：缺 `.ko` 的 target 会让 `modules.build` 的 `modprobe --show-depends`
直接失败。**待重编后验**：2.4G/5.8G 两个 pdev、`FW memory mode: 1`、以及
`wlan-2g`/`wlan-5g` 起 AP（N5 的判据在挂根形态上复验一次）。

# 不要管实际的eMMC GPT，各种机器有各种不同

块设备编号有个坑：分区号 ≥8 的走扩展主设备号，所以 `rootfs`(p18) 是 **259:10**——日志里
`Mounted root … on device 259:10` 指的就是它，不是 p10。

### N7b：USB 根形态（2026-09-25，N7 的第二半）

uimage 形状与 N7a 完全相同（FIT = kernel + dtb，cmdline 内嵌，无 rootdir），只把根设备
从 eMMC 分区换成 U 盘分区：`hardware.rootDevice = "PARTLABEL=liminix-root"`。

* 新增 `ax6600-usb.nix` = `ax6600-rootfs.nix` + `modules/usb.nix` + IPQ6018 USB3 host 配置；
* `ax6600-rootfs.nix` 只改一处：cmdline 的 `root=` 改成插值 `config.hardware.rootDevice`
  （原来写死 `PARTLABEL=rootfs`，与同一个文件里的 `hardware.rootDevice` 重复），
  新形态用 `lib.mkForce` 覆盖该选项即可，eMMC 形态的取值与行为不变；
* 用法与恢复流程写进了仓库根 `Guide.md`。


**ext4 变体**：`ax6600-usb-ext4.nix` = N7b + `modules/outputs/ext4fs.nix` +
`boot.rootfs.mount = "kernel"`，与 N7b 并存。判据在 N7b 四条之外再加：
串口日志里**没有** `Running pre-init...`，而是
`Waiting for root device PARTLABEL=liminix-root...` 之后直接
`VFS: Mounted root (ext4 filesystem)`；其余（s6、LAN、DHCP、ssh、无线）与 N7b 一致。

**风险/未验**：qusb_phy_0 的 vbus 由内核 fixed regulator（GPIO22）拉起，U-Boot 是否已预热未知；
`/dev/sda` 这个名字只在单盘时成立（eMMC 是 `mmcblk0`），所以主用 PARTLABEL，`/dev/sda1`
只作兜底；拔盘没有回退，救援只能靠网页重传。

### N7 产品化
* 可考虑：**U 盘持久化 **：USB 根形态现在根是只读 squashfs（`/` 100% used，可写的
  只有 `/dev`、`/run`、`/tmp`），**没有任何持久数据位置**。做法：给 U 盘加第二个 ext4 分区
  （或用 `sgdisk` 把现在单分区改成 GPT 双分区），用 `modules/mount` 的 `partlabel` 服务挂到
  `/persist`——它自带 mdevd/uevent 等待，正好解决 USB 异步枚举；需要落盘的服务（密钥、
  dnsmasq lease、hostapd 配置等）再按 `doc/configuration.adoc` 的 runtime secrets 指过去。
  注意只读根下 `/etc` 不可写，凡是要写配置的模块都得改成写 `/persist` 或 `/run`；
  另外 eMMC 形态要持久化的话同理，但那边写的是 p18（会覆盖原厂内容），见 N7a 实测表。
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

# N8，QCN9024外挂的5.2g
* 不要设置开机启动，由我手动开启
* **验证**：`CH`（QCN9024/QCN9074）出现，hostapd AP 可关联；
---

## 附录 

### QEMU 这条验证路径正式关闭（不要再试）



