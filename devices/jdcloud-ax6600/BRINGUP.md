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
| N9 | 升级模式：离线全量 + 在线 userspace | 代码已实现，待构建与设备验证 | — |
| N10 | 单 ext4 分区启动：kernel + rootfs 同分区，FIT 优先 | 计划 | — |

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


### N8：QCN9024 外挂的 5.2G【待办】
* 三频配置：PCI QCN9074 = 5.2G（ch36–64）、AHB 5G pdev = 5.8G（ch149+）、AHB 2.4G。
* 不要设置开机启动，由我手动开启。
* **验证**：`CH`（QCN9024/QCN9074）出现，hostapd AP 可关联。

### N9：U 盘升级（离线全量 + 在线 userspace）【代码已实现，待构建验证】

* 主力路径：内核或 rootfs 变化时，关机后由构建机执行 `update-usb.sh` 刷新 p1/p2。
  eMMC 保持不动；这与其他设备的“内核单独手工刷写”边界一致。
* 在线路径：构建 `outputs.updater` 后运行 `result-updater/bin/update.sh`，只更新 p2
  上的 userspace，不传输、不写入 `fit.itb`。内核变化必须回到离线全量升级。
* p2 是唯一持久化层。服务状态位于 `/var/lib/liminix会排除同步
* 在线只使用 `result-updater/bin/update.sh --fast`：设备侧 `restart-services` 会执行
  `activate /`、更新 s6 数据库并重启受影响的服务。
* 默认重启和 `--no-reboot` 在线路径不在 N9 范围；完整重启使用 `update-usb.sh`。
* 恢复：重新构建旧 configuration 的 `outputs.updater` 后执行
  `result-updater/bin/update.sh`；kernel 恢复使用 `update-usb.sh`。

#### 边界与验证

* 不在线升级 kernel，因此不需要 VFAT kernel 支持、boot-slot、内核备份、pending 状态或
  分区标签定位脚本。
* 在线 updater 只适用于同一 kernel 下的 userspace 变化；需要 new kernel/modules 时使用
  `update-usb.sh`。
* 不新增设备专用 updater；通用 `outputs.updater` 负责传输，设备侧由
  `systemConfiguration/bin/install` 完成安装。
* 待明示批准后验证：`result-updater/bin/update.sh --fast` userspace 更新及一次服务回滚演练。

### N10：单 ext4 分区启动（kernel + rootfs 同分区）【计划】

* 目标：FIT 和 ext4 rootfs 位于同一个分区。U-Boot 从该 ext4 读取 FIT，
  启动其中的 kernel + DTB；内核随后把同一分区挂载为 `/`。
* 这不是 full initramfs，也不是把 kernel 与 rootfs 封成一个文件。FIT 仍是
  kernel + DTB 容器，rootfs 仍是 ext4 文件系统。
* 保持现有 `HLOS + rootfs` 启动路径作为回退；N10 未完成恢复验证前，不修改
  默认 U-Boot 环境，也不动 `0:ART`。

#### 候选实现

* **FIT（首选）**：启用现有 `boot.loader.fit.enable`，在 ext4 rootfs 中生成
  `/boot/fit`。U-Boot 使用 `ext4load` 读取该 FIT，再执行 `bootm`。
  这沿用当前 `imageFormat = "fit"` 和 kernel + DTB 打包流程。
* **extlinux（备选）**：启用 `boot.loader.extlinux.enable`，生成
  `/boot/kernel`、`/boot/dtb`、`/boot/initramfs` 和
  `/boot/extlinux/extlinux.conf`，由 U-Boot 的 `sysboot` 或 distro boot 读取。
  仅在 FIT 路径受 U-Boot 版本限制，或确实需要多启动菜单时采用。
* `boot.loader.fit` 与 `boot.loader.extlinux` 都会定义
  `system.outputs.bootfiles`，同一镜像只能启用一个。
* 现有 FIT 输出把 `/boot` 表示为指向 Nix store 的符号链接。若 U-Boot 的
  ext4 实现不能跟随该链接，在设备目录增加镜像输出把 FIT 物化为普通文件
  `/boot/fit.itb`，不直接修改通用输出模块。

#### 前置验证

* 记录当前 U-Boot 版本、环境和启动命令；核对 `ext4load`、`bootm`（FIT）
  以及备选 `sysboot` 是否可用。
* 通过 `mmc part` 确认 `PARTLABEL=rootfs` 对应的实际 MMC 分区号；当前配置中的
  p18 不能直接假定等于 U-Boot 的设备号。
* 验证 U-Boot 能读取 ext4 中的 FIT 或 `extlinux.conf`，且 FIT 的 load/entry
  地址不与 U-Boot、reserved-memory 重叠。
* 先证明可从 USB 或 TFTP 启动一份独立的已知可用系统。仅有原 `HLOS` 不能恢复
  同分区内损坏的 rootfs，因为原 kernel 仍会尝试挂载该 rootfs。

#### 实施步骤

1. 先在 USB rootfs（p2 ext4）验证单分区启动，保留现有 FAT p1 路径不变。
2. 构建侧只生成试验用 FIT 镜像；经明示批准后再构建，不修改分区表。
3. 在 U-Boot 中手工执行 `ext4load` + `bootm`，确认载入源和内核 root 设备
   是同一个 ext4 分区。
4. 验证模块、NSS firmware、网络、2.4G/5.8G、重启和离线全量更新。
5. USB 路径稳定后，再对 eMMC `rootfs` 分区做同样验证；恢复路径未闭环时只保留
   手工启动，不改 U-Boot 默认环境。
6. FIT 路径确认不可行后，才评估 extlinux；不同时维护两套默认启动方式。

#### 验收与边界

* 验收：U-Boot 明确从目标 ext4 读取 kernel；内核从同一分区挂载 `/`；
  冷启动和重复重启稳定；ART、GPT 其他分区和现有 N9 更新流程不受影响。
* 同分区启动让 kernel 与 rootfs 共享故障域。产品化前必须确定独立的恢复入口，
  否则不切换默认启动。
* N10 不包含 full initramfs、整盘镜像生成、内核在线升级或新分区方案。

---

## 附录

# per-unit 数据开机时从 0:ART 读出（devices/jdcloud-ax6600/art.nix）：
#   art-extract（rc-init.d/05-art，先于 modules）：物化 /lib/firmware/ath11k 为
#     可写目录、写入 cal-ahb-c000000.wifi.bin、导出本机 MAC 到 /run/art/。
#   art-apply（s6 oneshot）：给 lan1..4/wan 设本机 MAC；按 MAC 把 AHB 两个 netdev
#     改名成 wlan24g / wlan58g。
# 因此接口名固定为 wlan24g(2.4G) / wlan58g(5.8G)，无线 MAC 由 ath11k 从 cal 自动设。
