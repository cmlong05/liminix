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
  放哪儿另有一层约束，见 N3：fullSystem 镜像里 `filesystem.lib.firmware` 到模块加载时
  还不存在（`activate` 在 `preinit` 的 `load_modules()` 之后才跑），要用
  `boot.initramfs.preloadFirmware` 嵌进镜像。

---

## 4. 分阶段计划

### N5 无线：ath11k 三频 * 无线分成两组（2.4g+5.8g）和（5.2g QCN9024)，共三频
* 注意 qcom,ath11k-fw-memory-mode 0,1,2的可选值，先设置为0，本机器有足够多的内存。
* 2.4g wifi ssid 设置为'CHEN', 5.8g ssid 设置成'CHEN_5g' 单独外挂的QCN9024是5.2g, ssid设置成 'CH'
# 阶段一，先起IPQ6010核心支持的双频2.4g和5.8g
* 不要设置开机启动，由我手动开启
* **验证**：`CHEN`（AHB 2.4G）与 `CHEN_5g`（AHB 5.8G）出现，hostapd AP 可关联；

* **风险**：AHB 无线与 NSS 的 QRTR/固件加载时序、保留内存冲突；QCN9074 的
  `fw_mem_mode`/MHI-790 等历史坑（见 `ax6600:DEVELOPMENT_LOG.md` §4.13–4.18）（任需要验证）

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
| N4 | 首启：ECM init `-22`，缺 `NETFILTER_FAMILY_BRIDGE`（见 D.20）；修好后待验 ECM offload 命中（`ecm_db` 计数增长）+ 转发热路径 A53 占用显著下降 + PPPoE/2.5G 吞吐基准 |
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

## 附录 

### QEMU 这条验证路径正式关闭（不要再试）



