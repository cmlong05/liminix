# JDCloud AX6600 (RE-CS-02) — Liminix NSS 满血有线/无线 bring-up

> 分支：`re-cs-02`（HEAD `63bf2e4`）　
> 内核基线：**Linux 6.18.52**　
> 目标：有线 + 无线走 NSS 满血路径　
> 参考实现：
  **VIKINGYFY/immortalwrt `main`**（6.18 + NSS 代，唯一同内核版本的实证组合）、
  **LiBwrt/LibWrt `25.12-nss`**（6.12，中文社区「满血 NSS」参考）

> 本文前半（§1–§3）是**现状与设计依据**，后半（§4）是**分阶段计划**。
> 未确认前不构建、不提交（见仓库根 `AGENTS.md`）。

---

## 1. 状态总览

| 阶段 | 内容 | 状态 | 落地 commit |
|---|---|---|---|
| 前置 | NSS 有线满血 | 已落地 | `6bcfb24` |
| 前置 | AHB 2.4G / 5.8G 无线 | 已落地 | `1413f8a` |
| 前置 | eMMC 挂根：uimage + squashfs rootfs | 已落地 | `8ec44be`、`ad4f4c0` |
| 前置 | USB 挂根：uimage + squashfs rootfs | 已落地 | `04229a7` |
| 前置 | USB 挂根：ext4 可写 root | 已落地 | `234723e`、`63bf2e4` |
| 前置 | AHB 2.4G/5.8G AP 走标准 hostapd 服务（s6 长驻，`wifi.autostart` 可关） | 已落地 | — |
| N6 | NSS WiFi offload 评估 | 未启动（可选 / 实验） | — |
| N7 | 产品化：持久化、分区、per-unit 数据（ART per-unit 数据落地中） | 进行中 | — |
| N8 | 外挂 QCN9024 的 5.2G | 待办 | — |

**NB**
> 不要管实际的 eMMC GPT，各种机器有各种不同。
> 块设备编号有个坑：分区号 ≥8 的走扩展主设备号，所以 `rootfs`(p18) 是 **259:10**——日志里`Mounted root … on device 259:10` 指的就是它，不是 p10。

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

### 2.2 来源政策（沿用现有风格，并记录例外）
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

* 参考 LibWrt 的 `package/kernel/mac80211/patches/nss/{ath11k,subsys,ath10k}` 与
  `ATH11K_NSS_SUPPORT`，以及 `NSS_DRV_WIFIOFFLOAD_ENABLE`。
* 参考 VIKINGYFY 6.18 NSS 栈



### N7 产品化【进行中】

* 内核和用户态软件是自动分区，还是分地方配置的？
  比如，iperf3 在最终产品里，不应该在 rootfs/HLOS 里，而应该在用户态里。
* **per-unit 数据统一从 `0:ART` 取**（已经实现）

### N8：QCN9024 外挂的 5.2G【待办】
* 三频配置：PCI QCN9074 = 5.2G（ch36–64）、AHB 5G pdev = 5.8G（ch149+）、AHB 2.4G。
* 不要设置开机启动，由我手动开启。
* **验证**：`CH`（QCN9024/QCN9074）出现，hostapd AP 可关联。

### N9: outputs.updater
* 升级模式
* eMMC 可写 rootfs + `outputs.updater`（参考 `turris-omnia` 的 `/dev/mmcblk0p1` 形态，
  本板 GPT：`0:HLOS` / `rootfs` / `0:ART`）；
---

## 附录

### QEMU 这条验证路径正式关闭（不要再试）
