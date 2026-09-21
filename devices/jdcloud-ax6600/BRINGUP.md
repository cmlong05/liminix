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
* **固件**：NSS blob 放 `filesystem.lib.firmware`；注意 OpenWrt 在运行时用
  `/etc/hotplug.d/firmware/10-qca-nss-fw` 把 `qca-nss*-retail.bin` 改名/链接成驱动请求的
  名字，**Liminix 没有 hotplug fallback**，所以要把驱动实际请求的名字（`qca-nss0.bin`
  等）在镜像里直接放好（N3 用 `dmesg` 的 `Direct firmware load for … failed` 校准）。

### 3.2 备选 B：若「WiFi NSS offload」是最高优先

降到 6.12 + LibWrt 栈（6.12 是它的实证基线，且有 `patches/nss/{ath11k,subsys,ath10k}`）。
代价：放弃本分支已有的 6.18 ath11k 补丁集与全部 6.18 适配。注意：**VIKINGYFY 的 6.18 NSS
栈没有任何 ath11k/mac80211 补丁**，官方 OpenWrt 也无 NSS WiFi offload（issue `#23798`）。

---

## 4. 分阶段计划

每步统一给：**目标 / 改动 / 验证 / 回滚 / 风险**。任何一步失败都可回退到 `re-cs-02`
的 PPE 有线镜像（已硬件验证）。

### N2 最小内核外模块路径 + `qca-ssdk` + `qca-nss-dp`（有线网口）

* **目标**：`lan1..lan4`、`wan` netdev 出现，PHY 链路 up，LAN 桥 DHCP/ssh 可用。
* **改动**：
  1. 新增最小 out-of-tree kmod 构建路径（参照 `pkgs/mac80211` 的形态）：
     `make -C ${kernel.modulesupport} M=<src> modules` +
     `KBUILD_EXTRA_SYMBOLS`（ssdk 的 `Module.symvers` 给 nss-dp 用）+
     各包需要的 `SoC=ipq60xx` / `NSS_DP_INCLUDE` / `EXTRA_CFLAGS` 变量；
     产出 `*.ko` 后合并出一个“含 NSS .ko 的 modulesupport 树”，交给
     `pkgs/kmodloader.override { kernel = { modulesupport = merged; }; targets = [...]; }`；
  2. `qca-ssdk`（`CHIP_TYPE=CPPE`、`PTP_FEATURE=disable`、`SWCONFIG_FEATURE=disable`、
     `IN_AQUANTIA_PHY=TRUE`、`IN_QCA808X_PHY=FALSE`）与 `qca-nss-dp` 两个包；
  3. 镜像切到 `outputs.tftpboot`（或等价的可加载模块形态）：新增顶层
     `ax6600-nss-ram.nix`（基于 `ax6600-lan.nix`，import `modules/outputs/tftpboot.nix`），
     加载服务依赖顺序：ssdk → nss-dp。
* **验证**：`dmesg | grep -iE 'ssdk|ess|qca8075|qca8081|nss-dp'`；`ip link` 有 4+1 端口；
  `cat /sys/class/net/wan/speed` = 2500（SGMII+，`switch_mac_mode1 = MAC_MODE_SGMII_PLUS`）；
  PC 插 lan1 拿到 DHCP 租约、能 ssh `int` 桥。
* **回滚**：停用 kmodloader 服务与 targets，回到 N1 的 dtb。
* **风险（已知的具体坑）**：PHY package `reg` 24–27 与 `qcom,port_phyinfo` 的
  `phy_address` 必须一致；`edma` 节点是 nss-dp 按名字找的（不是 bind）；模块名/depmod 名
  与 kmodloader `targets` 对齐（用 `modprobe --show-depends` 校对）。

#### N2 落地实况（与上面计划的差异）

计划里的第 1、3 条按"kmod + tftpboot"写，实际落地改成 **kmod + preinit 在 fullSystem
镜像里载入**，因为 tftpboot 需要串口 + 主机 TFTP，而本板 bring-up 想保持 web-upload
单文件镜像。为此把 fullSystem 的那个环解掉了：

* `pkgs/kernel-module` + `pkgs/liminix-tools/modules`：通用内核外模块路径与模块树
  （`lib/modules/0.0/*.ko` + `load-order` + `load.sh`/`unload.sh`，由
  `modprobe --show-depends` 定序）。`pkgs/kmodloader` 改为共用它。
* `devices/jdcloud-ax6600/nss/`：`qca-nss-phy`（头文件）、`qca-ssdk`、`qca-nss-dp`
  三个设备私有包；pin 在 `nss/SOURCES.nix`，19 个 fork 派生补丁按你的要求**构建期**
  从 pin 抓取（`nss/PATCHES.nix` 记 `blob` + `sha256`，本地不留字节）。
* `modules/outputs/initramfs.nix` 新增 `boot.initramfs.preloadModules`，
  `pkgs/preinit` 在 `execve("/init.s6")` 之前用 `finit_module` 逐条载入。
  **kmodloader 服务在这个形态下依然不可用**（它就是那个环），preinit 不是服务、不引用
  内核，所以可用。
* **环的根因**（计划里没有写全）：不只是"kmodloader 依赖 modulesupport"，而是
  **`.ko` 必须针对 `modulesupport` 编译**，任何引用都会强制求值整个 kernel derivation。
  换 insmod 的执行者绕不开。且 `kernel.config` 的类型是 `attrsOf nonEmptyStr`，
  **选项类型检查会强制每一个值**，所以"事后从 config 里去掉/覆盖 INITRAMFS_SOURCE"
  一律失败（`merged // {...}` 也会先强制原值）。
* **解法**：镜像不把 initramfs 放进 `kernel.config`，而是放进
  `kernel.initramfsSource`（`nullOr str`，由 `pkgs/kernel` 在 `olddefconfig` 之后追加进
  `.config`，绕开类型检查）；`modules/kernel/modules-kernel.nix` 再给出一份
  `kernel.modulesKernel`——同源、同补丁、同 config、同 make targets，**只少那一行**。
  NSS 模块针对它编译。两个内核只差 `INITRAMFS_SOURCE`，而没有任何导出符号依赖它，
  所以模块能载入真内核。代价是内核构建两次。
* `embedsInitramfs` 布尔开关是必需的：`modulesKernel` 若去问
  `initramfsSource == null`，那个问句本身就会强制出路径 → 又是环。


### N3 `nss-firmware` + `qca-nss-drv`（NSS 核启动）

* **目标**：NSS 核（uBI32）起来并进入可用状态，datapath 由 NSS 接管。
* **改动**：固件进 `filesystem.lib.firmware`（按驱动请求名放好，见 3.1）；新增
  `qca-nss-drv` 模块与加载服务；处理 mem profile：
  ipq60xx 在 QSDK Kconfig 里默认 `NSS_MEM_PROFILE_MEDIUM`，而 `HIGH`(1G) 被硬限制在
  `TARGET_qualcommax_ipq807x` —— 本板 1 GiB（本机改装到更大），要**显式选择 profile**
  （需要时以独立补丁放宽依赖），并记录选择理由。
* **验证**：`dmesg | grep -i nss` 出现 core/frequency、`nss_stats` 之类接口可读；
  转发路径上 NSS 计数增长。
* **回滚**：卸掉 `qca-nss-drv`，退回 N2 的纯 SSDK/nss-dp 路径。
* **风险**：闭源固件版本（11.4 / 12.1 / 12.2 / 12.5 的差异；MESH 只在 11.4）、
  固件许可、NSS 与 SMP/中断亲和性的调优。

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
| N3 | NSS 核启动日志 + 加速计数增长 |
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
4. **内存 profile**：ipq60xx 的 `NSS_MEM_PROFILE_HIGH` 被限制在 ipq807x，需显式处理。
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

# 构建（tftpboot：N2 起要新增的“可加载模块”配置，文件名在 N2 定）
nix-build -Q --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-nss-ram.nix -A outputs.tftpboot -o result-tftp

# 串口
sudo nix-shell -p picocom --run "picocom -b 115200 /dev/ttyUSB0"

# 真机核对
dmesg | grep -iE 'ssdk|ess-switch|nss-dp|nss|qca8075|qca8081|ubi32'
ip link; cat /sys/class/net/wan/speed
```
