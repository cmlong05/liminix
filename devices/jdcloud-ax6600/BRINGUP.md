# JDCloud AX6600 (RE-CS-02) — Liminix NSS 满血有线/无线 bring-up 计划

> 分支：`nss`（HEAD `266b23f`）　
> 内核基线：**Linux 6.18.52**　
> 目标：有线 + 无线走 NSS 满血路径
> 参考实现：
  **VIKINGYFY/immortalwrt `main`**（6.18 + NSS 代，唯一同内核版本的实证组合）、
  **LiBwrt/LibWrt `25.12-nss`**（6.12，中文社区「满血 NSS」参考）

> 本文只写**计划**。代码/配置改动按 N0..N7 分步进行，每一步单独确认后实施；
> 未确认前不构建、不提交（见仓库根 `AGENTS.md`）。

---

---

## 1. 现状

### 1.1 `nss` 分支现状（必须原样记录）

* `overrides.dtsi` 仍是 PPE 代的两条（`&switch assigned-clock-rates`、关 Bluetooth），
  换到 NSS 代后必须重新推导（NSS 的 ess-switch 节点没有 `assigned-clock-rates`）。
* `Guide.md` 与 `md5_result.sh` 仍引用本分支不存在的 `ax6600-wifi-ram.nix` / `result-wifi`,后续会重新添加。
* 参考关系：`re-cs-02` = PPE 有线（硬件验证过）+ 无线移植；`ax6600` = 老的双轨（radio
  bring-up 历史，`DEVELOPMENT_LOG.md` 是最完整的失败/修复记录）。

### 1.2 Liminix 侧决定路线形态的硬约束

来自 `pkgs/kernel/default.nix`、`modules/kernel/default.nix`、`pkgs/kmodloader/default.nix`、
`modules/outputs/initramfs.nix`：

1. **内核**：单一 derivation；`out` / `headers` / `modulesupport` / `config` 四个输出，
   `installPhase` 里 `make modules` 后 `cp -a . $modulesupport`，因此 `=m` 可用且
   `Module.symvers` 在 `modulesupport` 里。**没有** `modules_install`，rootfs 里没有
   `/lib/modules`。
2. **模块加载**：只有 `pkgs/kmodloader`：从 `kernel.modulesupport` 收集 `*.ko`、
   `depmod -b . 0.0`、用 `modprobe --show-depends` 算加载序、生成
   `load.sh` / `unload.sh` 的 oneshot。没有 modprobe/uevent 自动加载。
3. **没有 out-of-tree kmod 的正式支持**。`pkgs/mac80211/default.nix` 里有
   `KLIB_BUILD=<kernel>` 的现成形态（“make out-of-tree modules given a backported kernel
   source tree”），但 `klibBuild` 目前没有任何调用方传入 —— 它是模板，不是机制。
   NSS 驱动要落到 Liminix 里，需要**新增最小的内核外模块构建路径**（N2）。
4. **fullSystem initramfs 与 kmodloader 结构性互斥**：`boot.initramfs.fullSystem = true`
   把整个 rootdir 嵌进内核，而 rootdir 里的 kmodloader 服务依赖 `kernel.modulesupport`
   —— 同一个 kernel derivation 的另一个输出 → `INITRAMFS_SOURCE` 递归。
   （`re-cs-02` 的 `wifi/README` 已记录同一个坑，那里的做法是把 ath11k 全部 `=y`。）

   *N2 实测补正*：这个环比上面写的更深一层，**换掉 insmod 的执行者也绕不开**——
   环不在"谁载入模块"，而在 `.ko` 必须针对 `kernel.modulesupport` 编译，而
   `modulesupport` 是 kernel derivation 的输出。所以 `=y` graft 之所以能成立，正是
   因为它不需要 `modulesupport`（源码编进内核树）。落地解法是让模块针对**同一个内核
   去掉 initramfs 的孪生体**编译，实现在 `modules/kernel/modules-kernel.nix`，见 N2。
5. **固件**：`FW_LOADER_USER_HELPER=n`，没有 firmware 服务；blob 必须在 `/lib/firmware`
   就位（`filesystem = dir {...}` 软链），或者用 `EXTRA_FIRMWARE` 内嵌进内核镜像。
6. **内核 config 一致性检查**（`pkgs/kernel/default.nix:124-134`）会把 olddefconfig 丢弃的
   attrset 项报出来，并且打印后是 `exit 0` 提前结束该 phase —— 添加 promptless 符号
   （如 `PAGE_POOL` 那类）时要注意它只能由 `select` 打开。

### 1.3 当前网络服务侧（换镜像形态时会碰）

* `ax6600-lan.nix`：`int` 桥（lan1..lan4）+ dnsmasq + 2.5G `wan` 上跑 PPPoE + sshd。
* `ax6600-lan-ram.nix`：fullSystem 单 FIT（U-Boot web 上传 `/uimage.html`），无 root 设备。
* 无线侧文件（`ax6600-wifi.nix` / `ax6600-wifi-options.nix` / `ax6600-wifi-ram*.nix`）只在
  `re-cs-02` 上。
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

### 2.3 来源政策（沿用 `re-cs-02` 的风格，并记录例外）

* 第一方（CLO / OpenWrt 官方 / 内核官方）优先；上游字节不抄进仓库，构建期按
  URL+sha256 拉取。
* VIKINGYFY 的 `patches/*compat-linux-6.18*` 是 **fork 派生**，以**独立补丁文件 + sha256 +
  来源标注**的形式收录，并在台账里写明“派生自哪个 fork 的哪个文件”；不直接改外源代码。

---

## 3. 总体路线

### 3.1 主线（已定）

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
  放哪儿另有一层约束，见 N3：fullSystem 镜像里 `filesystem.lib.firmware` 到模块加载时
  还不存在（`activate` 在 `preinit` 的 `load_modules()` 之后才跑），要用
  `boot.initramfs.preloadFirmware` 嵌进镜像。

### 3.2 备选 B：若「WiFi NSS offload」是最高优先

降到 6.12 + LibWrt 栈（6.12 是它的实证基线，且有 `patches/nss/{ath11k,subsys,ath10k}`）。
代价：放弃本分支已有的 6.18 ath11k 补丁集与全部 6.18 适配。注意：**VIKINGYFY 的 6.18 NSS
栈没有任何 ath11k/mac80211 补丁**，官方 OpenWrt 也无 NSS WiFi offload（issue `#23798`）。

---

## 4. 分阶段计划

每步统一给：**目标 / 改动 / 验证 / 回滚 / 风险**。任何一步失败都可回退到 `re-cs-02`
的 PPE 有线镜像（已硬件验证）。

### N3 `nss-firmware` + `qca-nss-drv`（NSS 核启动）

* **目标**：NSS 核（uBI32）起来并进入可用状态，datapath 由 NSS 接管。
* **改动**（review 后定稿，见附录 C）：
  * `nss/SOURCES.nix` 加两个 pin：CLO `nss-drv` `6aa14c78…`（QSDK 13.1，2026-01-12）、
    qosmio `qca-sdk-nss-fw` v2025.05.01（12.5 CP retail）。
  * `nss/PATCHES.nix` 加 20 条 fork 补丁（`001` 构建系统 + `002` 的 6.18 版本窗口是硬性
    必需：不改就是 `#error`）。
  * `nss/qca-nss-drv/`：`SoC=ipq60xx_64`（不是 nss-dp 的 `ipq60xx`）、
    `-DNSS_FIRMWARE_VERSION_12_5`、`NSS_DRV_EXTRA_INCLUDES` 指向 nss-dp/ssdk。
  * `nss/qca-nss-dp/`：导出 `exports/*.h`（nss-drv `#include <nss_dp_api_if.h>`）。
  * `nss/nss-firmware/`：解外层 `.tar.zst` + 内层（**名为 `.tar.bz2` 实为 xz**），
    产出 flat output 的 `qca-nss0.bin`。
  * `modules/outputs/initramfs.nix` 加 `boot.initramfs.preloadFirmware`，与
    `preloadModules` 对称地把固件嵌进 fullSystem 的 cpio：
    `preinit` 的 `load_modules()` 早于 `activate`，那时 `/lib/firmware` 还不存在，
    而驱动在 probe 里同步 `request_firmware`，缺失即 `finit_module` 失败。
* **mem profile**：**不需要处理**。`NSS_MEM_PROFILE_*` 只是驱动里的 C 宏，没有 Kconfig
  也没有默认 `#define`；VIKINGYFY 的包和驱动 Makefile 都不传它 → 走
  `nss_hlos_if.h` 的 `#else` 分支 = 最大档（IPv4/IPv6 各 4096、合计 8192、empty buffer
  1984），正是 1 GiB 该用的。原文说的「ipq60xx 默认 MEDIUM、HIGH 被限制在 ipq807x」是
  qosmio `nss-packages` feed 的规则，不适用于本 pin。ipq60xx 恒为 `num_nss=1`。
* **特性集**：照 fork「无 client 包」的默认，显式关掉
  C2C/CAPWAP/CLMAP/DTLS/IPSEC/PVXLAN/QVPN/TLS、GRE*/IPV4_REASM/IPV6_REASM/LSO_RX/QRFS/
  RMNET/SJACK/TRUSTSEC*/UDP_ST/WIFI_EXT_VDEV、BRIDGE/CRYPTO/GRE/IGS/L2TP/LAG/MAPT/
  MATCH/MIRROR/PPPOE/PPTP/SHAPER/TUN6RD/TUNIPIP6/VIRT_IF/VLAN/VXLAN/WIFI_MESH/WIFIOFFLOAD；
  留着的是 IPV4、**IPV6**、ETH_RX、SoC 选中的 PPE/EDMA，以及频率缩放。
  *构建实测*：IPV6 **不能关**——`nss_rps.c` 的 `nss_rps_hash_bitmap_cfg_handler()` 是
  `#if !defined(NSS_DRV_IPV4_ENABLE) || !defined(NSS_DRV_IPV6_ENABLE)` 整段返回
  「not supported」，两者关任意一个，`nss_rps_ipv4_hash_bitmap_cfg()` 就成了无调用者的
  static 函数，驱动自带的 `-Wall -Werror` 直接失败。fork 的包选型总是同时打开
  IPV4/IPV6，所以这个坑它自己碰不到。N4/N5 再逐个放开 PPPOE/BRIDGE/VLAN/VIRT_IF。
* **内核 config**：**不新增**。N2 的 config 已有 MODULES/MODULE_UNLOAD/DEBUG_FS/PROC_FS/
  PROC_SYSCTL/FW_LOADER/SMP/IPQ_GCC_6018/QCOM_SMEM/RESET_CONTROLLER/PPP/BRIDGE；
  `NET_CLS_ACT`/`BRIDGE_NETFILTER`/`NF_CONNTRACK`/`SKB_EXTENSIONS`/`PAGE_POOL` 在驱动的
  源码里全是 `#ifdef` 可选路径，参考 fork 的 qualcommax config 里同样基本没有。
* **验证**：`dmesg` 出现 `NSS fw version: NSS.FW.12.5-210-CP.R`
  （驱动打印的是 blob 里的版本串，归档名/成员名才带 `BIN-` 前缀）与
  `NSS core 0 DDR from 40000000 to 41000000`、`NSS core 0 booted successfully`；
  `/proc/sys/dev/nss/` 可读；`/sys/kernel/debug/qca-nss-drv/` 要先
  `mount -t debugfs none /sys/kernel/debug`（Liminix 的 init 只挂 /proc /sys /dev /run，
  不挂 debugfs，而驱动是把目录建在 debugfs 根上的）；转发路径上 NSS 计数增长。
* **回滚**：`ax6600-nss-ram.nix` 的 `targets` 去掉 `qca-nss-drv`（`preloadFirmware` 可留，
  无害），退回 N2 的纯 SSDK/nss-dp 路径。
* **风险**：驱动自带 `-Wall -Werror`，6.18 的告警是**最可能的第一个构建失败点**；
  闭源固件版本（11.4 / 12.1 / 12.2 / 12.5 的差异；MESH 只在 11.4）、固件许可
  （QuIC 二进制，仅限 QTI 芯片）；N2 的 `nr_cpus=1` 只让 NSS RPS 退化，不阻塞 N3。

### N4 `qca-nss-ecm`（硬件 NAT/PPPoE offload = 「满血」）

* **目标**：连接跟踪 offload 生效，WAN 转发不再走 A53 软转发。
* **改动**：`0600-*` ECM 内核补丁、`qca-nss-ecm` 模块、必要的 netfilter 符号
  （`NF_CONNTRACK_DSCPREMARK_EXT=y` 等，取自参考 config）；PPPoE 场景（本板 `wan` 是
  PPPoE）需要 `0600-2`(PPPOE offload) 与 `qca-nss-drv-pppoe` 客户端。
* **验证**：offload 计数/数据库（以 OpenWrt 的 `ecm_dump.sh` 对应接口为准，落地时确认
  sysfs/debugfs 路径）；同一流量下 A53 占用显著下降；WAN 吞吐基准（PPPoE/2.5G）。
* **回滚**：停 ECM，保留 N3。
* **风险**：ECM 与 bridge/vlan/PPPoE 组合的补丁依赖链最长，建议在 N3 稳定后再动。

### N5 无线：ath11k 双 radio（AHB 2.4G + QCN9074 5G）
* 无线分成两组（2.5g+5.8g）（5.2g QCN9024)
* 注意 qcom,ath11k-fw-memory-mode 0,1,2的可选值
* **目标**：把 `re-cs-02` 已整理好的无线移植搬回本分支，与 NSS 有线共存。
* **改动**：`git checkout re-cs-02 -- devices/jdcloud-ax6600/wifi`（5 个本地补丁 + README +
  `SOURCES.nix`）；把 `SOURCES.nix` 的 wifi 段与 `extraPatchPhase` 的 wifi 循环接回
  `default.nix`；恢复顶层 `ax6600-wifi.nix` / `ax6600-wifi-options.nix` /
  `ax6600-wifi-ram*.nix` 并适配 NSS 的镜像形态；与 N1 的保留内存布局对齐（q6/m3_dump）。
* **验证**：`wlan24`（AHB 2.4G）与 `wlan5g1`（QCN9074）出现，hostapd AP 可关联；
  **`qcom,ath11k-fw-memory-mode` 必须是 2**。
* **回滚**：不 import `modules/wlan.nix`，回到纯有线。
* **风险**：AHB 无线与 NSS 的 QRTR/固件加载时序、保留内存冲突；QCN9074 的
  `fw_mem_mode`/MHI-790 等历史坑（见 `ax6600:DEVELOPMENT_LOG.md` §4.13–4.18）。

### N6（可选/实验）NSS WiFi offload 评估

* 依据 LibWrt 的 `package/kernel/mac80211/patches/nss/{ath11k,subsys,ath10k}` 与
  `ATH11K_NSS_SUPPORT`，以及 `NSS_DRV_WIFIOFFLOAD_ENABLE`。
* 结论必须写清：VIKINGYFY 6.18 NSS 栈**没有** ath11k NSS 补丁；官方 OpenWrt 也没有
  （issue `#23798`）；LibWrt 自称 IPQ60xx 2.4G/5G offload ✅，但 AP-VLAN 有已知问题。
* 若要做：先在 6.12+LibWrt 上复现，再评估移植到 6.18 的成本，不要一开始就动 6.18。

### N7 产品化

* eMMC 可写 rootfs + `outputs.updater`（参考 `turris-omnia` 的 `/dev/mmcblk0p1` 形态，
  本板 GPT：`0:HLOS` / `rootfs` / `0:ART`）；
* 从 `0:ART` 读 MAC（`label-mac-device = &dp1` 已由 DTS 声明，仍需把 per-unit MAC
  落到 `local-mac-address`）；
* 三频配置：PCI QCN9074 = 5.2G（ch36–64）、AHB 5G pdev = 5.8G（ch149+）、AHB 2.4G；
* 长期 soak 与回退策略（保留 `re-cs-02` PPE 镜像作为救砖路径）。

---

## 5. 验收与「满血」判据

| 阶段 | 判据 |
|---|---|
| N0 | `nix-instantiate --parse` 通过 |
| N1 | dtb 含 `ess-switch` / `nss@40000000` / `dp1..dp5`；真机无 panic |
| N2 | `lan1..lan4` + `wan` 存在、链路 up、DHCP/ssh 可用、`wan` 2500 Mbps |
| N3 | ✅ 真机：`NSS fw version: NSS.FW.12.5-210-CP.R` + `NSS core 0 booted successfully`；`/proc/sys/dev/nss/` 可读（debugfs 需手工 mount）；计数增长待验 |
| N4 | ECM offload 命中 + 转发热路径 A53 占用显著下降 + 吞吐基准 |
| N5 | 2.4G/5G AP 可关联 |

**明确不承诺**：满血 ≠ WiFi offload（6.18 栈没有）；满血 ≠ 保证 2.5G 线速（社区反馈
有 2.5G 口只协商到 1G 的案例，链路速率要单独实测）。

构建命令沿用现有惯例（N2 起镜像形态可能换成 tftpboot）：

```console
$ nix-build -Q --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-lan-ram.nix -A outputs.uimage -o result-lan-ram
$ sh md5_result.sh
```

---

## 6. 风险与失败模式

1. **唯一 6.18+NSS 的实证是 fork**：compat 补丁是 fork 派生材料，逐条落地时可能遇到
   补丁上下文漂移；台账 + `.rej` 扫描是唯一保险。
2. **镜像形态**：不接受 tftpboot/串口就必须走备选 B（内建），风险显著上升。
3. **闭源固件**：许可与版本差异（11.4/12.5；MESH 需 11.4）；NSS 固件文件名在无 hotplug
   fallback 的 Liminix 下要手工对准。
4. **内存 profile**（*N3 review 更正*）：不再是风险。`NSS_MEM_PROFILE_*` 只是驱动里的 C
   宏，没有 Kconfig/默认定义，VIKINGYFY 的包与 Makefile 都不传 → 默认即最大档，适合 1 GiB。
   「`NSS_MEM_PROFILE_HIGH` 被限制在 ipq807x」是 qosmio feed 的规则，与本 pin 无关。
5. **DTS/保留内存**：`0103` 改了 `q6_region` 并新增 `m3_dump`，与 AHB 无线的区域重叠
   必须在 N1 定稿。
6. **时钟**：CMN PLL 节点是否必须、NSS crypto rcg 警告的来源在换代后要重新确认。
   *N1 实测*：NSS 代的 `ipq6018-ess.dtsi` 把 `bias_pll_cc_clk`/`bias_pll_nss_noc_clk`
   定义成 `fixed-clock`，且**不引用** `qcom,ipq6018-cmn-pll` 节点 —— 所以 CMN PLL 的
   0080/0082/0191 对 DTS 非必需（mainline `gcc-ipq6018.c` 靠 `fixed-clock` 满足父时钟）。
   crypto rcg 警告源于 PPE 代 dtsi 的 `assigned-clock-rates = 600 MHz`，NSS 代已改为
   `eip197_node` 的 `clock-frequency = 300 MHz`，该覆盖因此删除。
7. **ath11k fw-memory-mode 故意偏离上游**：`overrides.dtsi` 把两个 radio 都设成 mode 0
   （17 vdevs / 512 peers），而上游与 OpenWrt/ImmortalWrt 都不设该属性（= 主线默认 mode 2）。
   1 GiB 内存下多出的固件表可忽略，但 **mode 0 本机未实测**；mode 1 已知有害
   （QCN9074 载波 5180↔5500 MHz 振荡，见 ax6600 分支 `DEVELOPMENT_LOG` 4.7/4.8）。
   N5 无线落地时必须实测，异常则回退 mode 2（改两个数字即可）。
8. **止损**：任何阶段失败都能回到 `re-cs-02` 的 PPE 有线镜像（已硬件验证）。

---

## 7. 待确认决策（已按推荐值写在上面，可改）

1. 基线：**6.18.52 + VIKINGYFY main 的 NSS 代**（备选：6.12 + LibWrt）。
2. 形态：**kmod + `pkgs/kmodloader` + tftpboot 镜像**（备选：fullSystem + `=y` graft）。
3. fork 派生补丁：**以独立补丁 + sha256 收录并标注来源**（备选：只作参考、自行重写）。
4. 文档语言与粒度：中文正文、每阶段单独确认后实施。

---

## 附录 A：PPE 代 vs NSS 代 DTS 关键片段

PPE 代（当前 pin，`immortalwrt 8d9475a99f` → `ipq6018-ess.dtsi` + board dts）：

```dts
switch: ppe@3a000000 { compatible = "qualcomm,ipq6018-ppe"; ... };
edma  { compatible = "qualcomm,ipq6018-edma"; ... };
uniphy0: ethernet-pcs@7a00000 { compatible = "qualcomm,ipq6018-uniphy"; ... };  /* + uniphy1 */
/* 同文件还有 cmn_pll: clock-controller@9b000 { compatible = "qcom,ipq6018-cmn-pll"; ... } */

&switch { ports { port@0 { ethernet = <&edma>; }; swport1: port@1 { label="lan1";
          phy-handle = <&qca8075_0>; phy-mode="psgmii"; pcs-handle = <&uniphy0 0>; }; ... } };
aliases { ethernet0 = &swport1; ... };
```

NSS 代（`VIKINGYFY/immortalwrt main` → `ipq6018-ess.dtsi` + `ipq6018-nss.dtsi` + board）：

```dts
edma: edma@3ab00000 { compatible = "qcom,edma"; ... status = "disabled"; };
ess_instance { switch: ess-switch@3a000000 { compatible = "qcom,ess-switch-ipq60xx";
        mdio-bus = <&mdio>; switch_cpu_bmp = <ESS_PORT0>; switch_inner_bmp = <(ESS_PORT6|ESS_PORT7)>;
        switch_mac_mode = <MAC_MODE_DISABLED>; ... }; ess-uniphy@7a00000 { ... }; };
dp1: dp1 { compatible = "qcom,nss-dp"; qcom,id = <1>; reg = <0x0 0x3a001000 0x0 0x200>; ... };

/* board： */
aliases { ethernet0 = &dp1; ... ethernet4 = &dp5; label-mac-device = &dp1; };
&switch { switch_lan_bmp = <(ESS_PORT1|ESS_PORT2|ESS_PORT3|ESS_PORT4)>; switch_wan_bmp = <ESS_PORT5>;
          switch_mac_mode1 = <MAC_MODE_SGMII_PLUS>;
          qcom,port_phyinfo { port@5 { port_id = <5>; phy_address = <12>; port_mac_sel = "QGMAC_PORT"; } }; };
&dp1 { status = "okay"; phy-handle = <&qca8075_24>; label = "lan1"; }; ...
&dp5 { status = "okay"; phy-mode = "sgmii"; phy-handle = <&qca8081>; label = "wan"; };
// 板级还有一处同样的属性，在 &pcie0 / pcie@0 / wifi@0,0（PCIe QCN9074）里；
// ath11k 从各自的 of_node 读，所以两处都要覆盖。
&wifi { status = "okay"; qcom,ath11k-fw-memory-mode = <1>;  /* 上游值；我们覆盖成 0 */
        qcom,ath11k-calibration-variant = "JDC-RE-CS-02"; };
```

## 附录 B：实用命令

```console
# 语法/评估
nix-instantiate --parse devices/jdcloud-ax6600/default.nix

# 构建（web-upload fullSystem，当前形态）
nix-build -Q --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-lan-ram.nix -A outputs.uimage -o result-lan-ram

# 构建（N2/N3：同一个 fullSystem 形态 + 可加载模块与 NSS 固件）
nix-build -Q --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-nss-ram.nix -A outputs.uimage -o result-nss-lan-ram

# 串口
sudo nix-shell -p picocom --run "picocom -b 115200 /dev/ttyUSB0"

# 真机核对
dmesg | grep -iE 'ssdk|ess-switch|nss-dp|nss|qca8075|qca8081|ubi32'
ip link; cat /sys/class/net/wan/speed

# N3：NSS 核
dmesg | grep -iE 'nss fw version|nss core|frequency'
ls /sys/kernel/debug/qca-nss-drv/stats/
cat /proc/sys/dev/nss/stats/non_zero_stats
```

## 附录 C：N3 review 记录

实施前对 N3 做过一次核对，结论（依据见各处注释）：

* **固件投递**（原计划错）：blob 不能只放 `filesystem.lib.firmware`。fullSystem 的 cpio
  只有 `rootdir`（activate/init/nix-store/secrets/boot）加 `preloadModules`；
  `filesystem.contents` 是 `preinit` 里 `/activate` 跑出来的，而 `preinit.c` 的调用序是
  `mount /proc` → `parseopts` → **`load_modules()`** → `activate`。驱动在 probe 里同步
  `request_firmware`，那时 `/lib/firmware` 还不存在，`finit_module` 必然失败。
  定稿方案：新增 `boot.initramfs.preloadFirmware`，与 `preloadModules` 对称地把固件写进
  cpio（备选：`CONFIG_EXTRA_FIRMWARE` 内嵌内核）。
* **驱动 pin**：CLO `nss-drv` `6aa14c78e097b29c493ff2fef87e4d35906b2b5a`（QSDK 13.1），
  nar hash `sha256-OqbVrRhnp6z9QJ38vkjEPTgLg5tfdnRu0gp2LU/p85M=`；该 hash 的算法
  （shallow fetch → `git archive` 解出 → `nix hash path --sri`）先用 nss-dp 的已知 pin
  反证一致。
* **20 条 fork 补丁**：`patch -p1 --fuzz=0` 按序累积 20/20 通过；blob sha 与 sha256 全部
  记在 `nss/PATCHES.nix`。`002` 把 `nss_core.c` 的 `LINUX_VERSION_CODE` 白名单改成 6.18
  窗口（驱动硬编码 `NSS_SKB_REUSE_SUPPORT=1`，否则 `#error`）。
* **固件字节**：外层 `nss-firmware-2025.05.01.tar.zst` sha256 `10a4b1e6…d7abb0`；
  内层 `QCA_Networking_2024.SPF_12.5/ED1/IPQ6018.ATH.12.5/BIN-NSS.FW.12.5-210-CP.R.tar.bz2`
  （**实为 xz**）sha256 `56d9cd4e…a1f2`；成员 `BIN-NSS.FW.12.5-210-CP.R/retail_router0.bin`
  862,184 B sha256 `3c770896…1ccee` → 作为 flat output 的 `qca-nss0.bin`。
* **内核 config**：N2 的 config 已够（`MODULES`/`MODULE_UNLOAD`/`DEBUG_FS`/`PROC_FS`/
  `PROC_SYSCTL`/`FW_LOADER`/`SMP`/`IPQ_GCC_6018`/`QCOM_SMEM`/`RESET_CONTROLLER`）；
  参考 fork 的 qualcommax config 也没有 `NET_CLS_ACT`/`BRIDGE_NETFILTER`/`NF_CONNTRACK`/
  `SKB_EXTENSIONS`，`PAGE_POOL` 在 nss-drv 里根本没引用。`REGULATOR=n` 也无碍（ipq60xx
  HAL 只声明 `npu_reg` 不使用）。
* **DTS 前提**：N2 镜像的 dtb 已含 `nss@40000000` / `nss-common` / `qcom,load-addr`。
* **review 时唯一没把握的点**：驱动 Makefile 自带 `-Wall -Werror`，6.18 告警会不会炸。
  实测确实炸了，见下一条。
* *构建实测（2026-09-22）*：
  * 首次构建在 `nss_rps.c:287` 失败：`nss_rps_ipv4_hash_bitmap_cfg` defined but not
    used `[-Werror=unused-function]`。原因是 `NSS_DRV_IPV4_ENABLE`/`NSS_DRV_IPV6_ENABLE`
    必须**同时**打开（见 N3 特性集）。改掉后 20 条补丁 + 编译全部通过，
    `qca-nss-drv.ko` 452 KB、vermagic `6.18.52`，只余 `nss_dp_*` 这组由 nss-dp 提供的
    未定义符号（modpost 由 `KBUILD_EXTRA_SYMBOLS` 解决）。
  * 固件 FOD 命中：`qca-nss0.bin` 862,184 B、sha256 `3c770896…1ccee`，与 pin 一致。
  * `load-order` = `qca-ssdk.ko` → `qca-nss-dp.ko` → `qca-nss-drv.ko`（depmod 推导，符合
    预期）。
  * `fullinitramfs` 里 `/lib` → `/lib/firmware` → `qca-nss0.bin`、`/lib/modules` →
    `/lib/modules/0.0` → ko 的顺序正确（父目录都先于子项，gen_init_cpio 不会静默丢弃）。
  * 环境提示：Nix 的 fetcher 缓存在 `~/.cache/nix`，被 DSH 文件沙箱挡下（SQLite
    readonly）。用 `XDG_CACHE_HOME=<可写目录>` 重定向即可，不需要放宽沙箱。
  * *产物*：`result-nss-lan-ram` → `4fzyjqhwkj6yf7h49xq52136pcbcnypb-kernel.image-…`，
    35,245,600 B，md5 `28ef5b437d069dc2a5d4b0119b6455bc`（N2 是 34,778,828 B，多出的是
    固件 + 驱动）。最终内核的 `CONFIG_INITRAMFS_SOURCE` 指向上面那个 fullinitramfs。
* *真机实测（刷入 `result-nss-lan-ram`）*：
  ```
  qca-nss 39000000.nss: NSS fw version: NSS.FW.12.5-210-CP.R
  ffffffc07aa43a78: NSS core 0 DDR from 40000000 to 41000000
  qca-nss 39000000.nss: NSS core 0 booted successfully
  ```
  `/proc/sys/dev/nss/` = clock/general/ipv4cfg/ipv6cfg/n2hcfg/ppe_vp/project/rps/
  skb_reuse/stats。`/sys/kernel/debug/qca-nss-drv/` 需要手工
  `mount -t debugfs none /sys/kernel/debug`——Liminix 的 init 不挂 debugfs，
  驱动把目录建在 debugfs 根上（`nss_stats.c` 的 `debugfs_create_dir("qca-nss-drv", NULL)`），
  内核侧 `CONFIG_DEBUG_FS=y`、`DEBUG_FS_ALLOW_ALL=y` 都在。**尚未验证**：offload/转发
  计数增长、NSS 数据面是否真的接管了转发。
