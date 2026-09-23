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

---

## 4. 分阶段计划

### N5 无线：ath11k 三频 * 无线分成两组（2.4g+5.8g）和（5.2g QCN9024)，共三频

#### N5 review（2026-09-22）——落地前对本文的更正

1. **`qcom,ath11k-fw-memory-mode` 不是惰性数据**（2026-09-23 真机更正本文旧说法）。
   `wireless/SOURCES.nix` 里 **903 是打上的**（`default.nix` 的建构期断言专门查
   `core.c` 里存在这个属性名），board dts 给 `&wifi`（AHB）和 PCI 节点写的 `<1>` 因此
   真的生效：AHB 跑 `fw_mem_mode 1 / num_vdevs 8 / num_peers 128`，dmesg 打
   `FW memory mode: 1`。这正是参考实现（fork 的 board dts + 903）自己的组合，真机两个
   pdev 都正常，所以**不做任何 DT 覆盖**；本文原先"驱动内建 mode 0 / 17 vdevs / 512 peers"
   的说法作废（`overrides.dtsi` 里从来没有 mode 覆盖）。mode 1 在 5180↔5500 振荡是旧分支
   QCN9074 的历史包袱，与 AHB 无关，阶段二再定。
2. **wcss 侧走 fork 的独立驱动，不改主线**。本节曾按官方 OpenWrt 的路线做（把 ipq6018 加进
   主线 `qcom_q6v5_wcss.c`）：主线**没有** ipq6018 driver data（6.18.y/6.19.y/master 都查过），
   于是兼容性、firmware 名、安全 PIL、PRNG/QDSS_AT 时钟、BCR reset 可选、auto_boot 关闭
   全要自己补——8 个 OpenWrt 补丁，而且那套**自相矛盾**：`0905` 的 commit message 明说
   ipq6018 的 SSR 名不能是 `"q6wcss"`，却只改了 ipq8074 项，随后 `0136` 新建的 ipq6018 项又把
   `"q6wcss"` 写回去，纠正它需要第 9 个本地补丁。
   **VIKINGYFY 的做法不同**：它**新增一个驱动** `drivers/remoteproc/qcom_q6v5_wcss_sec.c`
   （`0186`+`0188`+`0808`–`0812`），DTS 指到 `qcom,ipq6018-wcss-sec-pil`，firmware 名走 DT 的
   `firmware-name`（`0905`）。ipq6018 只是其中一个 descriptor：`pasid = 6`、`ss_name = "wcnss"`
   （`0812`）——那个纠正在人家那里本来就是对的。主线不动，**全部 15 个补丁都是上游字节、构建期
   fetch，零本地补丁**。清单与理由在 `wireless/SOURCES.nix`。
   连带：内核 config 用 `QCOM_Q6V5_WCSS_SEC=m`（不是 `QCOM_Q6V5_WCSS`），preload 目标
   `qcom_q6v5_wcss_sec`。
3. **`wifi: wifi@c000000` 不在 6.18.52 里，fork 的 `0906` 必须打**（对上文的更正）：
   `qcom,ipq6018-wcss-pil` remoteproc 节点是主线的，但 wifi 节点不是——
   `arch/arm64/boot/dts/qcom/` 下三个 ipq6018 dts 文件连 `wifi` 字符串都没有（解包实测）。
   board dts 的 `&wifi { status = "okay"; ... }` 要这个 label，ath11k 也按
   `qcom,ipq6018-wifi` 匹配（`ath11k/ahb.c` 的 of_match）。已并入 `wireless/SOURCES.nix`
   的 wcss 组、排在 `0905` 之后：`0906` 的尾上下文正是 `0905` 写进去的 `-sec-pil` 兼容串，
   这样它 fuzz 0 干净应用。建构期仍断言该节点唯一。
4. **fork 的 multipd 一串（0801/0804–0807/0813–0815）不需要**：实测最小集
   `0186/0188/0808/0809/0810/0811/0812` 即可，驱动自包含（只用到 `MPD_WCSS_PAS_ID` 常量）。
5. **`preloadFirmware` 支持子目录需要先补建构器**（首版改错，已更正）：`gen_init_cpio`
   不会隐式建父目录；内核 `init/initramfs.c` 的 `do_name()` 对文件走
   `filp_open(..., O_CREAT)`、对目录走 `init_mkdir`→`ksys_mkdir`，**都不建父目录**，
   失败即 `return 0` 静默跳过。首版把原来那句 `dir /lib/firmware` 换成了「按 firmware 名
   生成父目录」的 `firmwareDirs`，而它只算名字自身的各级前缀（纯文件名得空列表），
   于是 `/lib/firmware` 本身没人发——整棵子树连同 `qca-nss0.bin`、`regulatory.db` 一起被丢，
   真机 dmesg 表现为 `qca-nss0.bin` / `regulatory.db` / `IPQ6018/q6_fw.mdt` 全 `-2`
   （NSS 核与 Q6 都起不来；`/lib/modules` 因 `find` 含自身而幸免）。已补回
   `echo "dir /lib/firmware 0755 0 0"`，再发各名字的父目录。
6. **接口名不稳定**：AHB 两个 pdev 的 `wlanN` 取决于注册顺序，所以不给固定名，
   由脚本按频段查找（见下）。
7. **建构期检查的窗口要按块给**：`in_entry` 现在收一个可选的 window（默认 25）——
   两个块比 25 行长：dtsi 的 `q6v5_wcss` 节点里 QDSS_AT 时钟在第 28 行，ipq6018
   hw params 里 `coldboot_cal_mm` 在第 46 行；`951` 原来的整文件 `need` 检查
   （`ath11k_hif_ce_irq_disable(ab)`）在**未打补丁**的树上也成立，已改为锚在
   `ath11k_core_reconfigure_on_crash` 上的 `in_entry`。

#### 阶段一，先起 IPQ6010 核心支持的双频 2.4g 和 5.8g

状态：真机已通（2026-09-23：`CHEN`de hostapd 都 `state=ENABLED`；把 pin 的
Q6 固件与 `CRYPTO_MICHAEL_MIC=y` 一起打进镜像后，2.4G `CHEN` 再次 `state=ENABLED` 且已有
客户端关联，见下）。

* 形态：并入 `ax6600-nss-ram.nix`（`devices/jdcloud-ax6600/wireless`），
  `ath11k_ahb` + `qcom_q6v5_wcss_sec` 进 `preloadModules`；Q6/m3/board-2/ART 校准按
  `preloadFirmware` 嵌进 initramfs（fullSystem 镜像里 `/lib/firmware` 到模块加载时还不存在）。
  节点使能走 `overrides.dtsi`（`&q6v5_wcss { status = "okay"; }`）。
* `qcom,ath11k-fw-memory-mode` = **mode 1**（903 + board dts 的 `<1>`，见 review 1），无覆盖。
* **AHB 的 Q6 固件必须 pin 参考那一版**（2026-09-23 真机定位，本轮唯一的致命项）：
  linux-firmware 的 `ath11k/IPQ6018/hw1.0`（`WLAN.HK.2.7.0.1-02409`，变体
  `6018.wlanfw.evalQ`）在 **5.8G AP 的 BSS peer 建立时直接固件断言**——
  即 phy0 第一次 interface up，还没到 channel/beacon 配置：
  `qcom-wcss-secure-pil: fatal error received ... BADVA = 0x00dcd87c`（正是接口 MAC
  `dc:d8:7c:...`，固件把 peer 地址当指针解引用），hostapd 只看到
  `Could not set interface wlan0 flags (UP): No such file or directory`（`-ENOENT`）。
  2.4G phy1 在同一版固件下一直正常，所以现象是"2.4G 能起、5.8G 一起就崩"。
  改用 `VIKINGYFY/ath11k-firmware-ddwrt@0c817c46` 的 `IPQ6018/hw1.0`
  （q6 + m3 + board-2，`fw_version.txt` = **`WLAN.HK.2.12-01460`**，即本机参考实现跑的
  那一版）后，**热替换 `/lib/firmware` 让 Q6 重新加载即可复现修复**：dmesg 报
  2.12-01460，两个 AP 全部起来、dmesg 零报错。台账在 `wireless/SOURCES.nix` 的
  `q6Firmware` / `boardData`（13 个 q6/m3 文件 + board-2，逐文件 sha256）。
* **关联需要 `CRYPTO_MICHAEL_MIC`**（2026-09-23 真机，客户端第一次尝试时暴露）：
  `ath11k_peer_rx_frag_setup()`（`dp_rx.c`）对**每个 peer 无条件**
  `crypto_alloc_shash("michael_mic")`，主线把该符号留成 `=m`，而 fullSystem 镜像没有
  kmodloader——preinit 只加载模块树的 `load-order`，`request_module()` 又没有
  `/sbin/modprobe` 兜底，于是 `.ko` 虽在镜像里却永不加载，站加入直接失败：
  `failed to allocate michael_mic shash: -2` → `failed to setup dp for peer` →
  `Failed to add station`（AP 自己起得来，客户端连不上）。已在 `wireless/default.nix`
  的 `kernel.config` 里设 `CRYPTO_MICHAEL_MIC = "y"`；当次开机可 `insmod
  /lib/modules/0.0/michael_mic.ko` 现场验证。其余所需 crypto（AES/CCM/CMAC/GCM/ARC4）
  本来就是 `=y`。**内建进镜像后实测**：`hostapd_cli -p /run/hostapd-2g status` 报
  `num_sta[0]=1`，客户端确实关联上了。
* **`wlan-<band> start` 现在按 pidfile 挡住重复起**（2026-09-23 加固）：AP 已在跑时再
  `start`，第二个 hostapd 会在 `NL80211_CMD_SET_INTERFACE` 上拿到 `-EALREADY`
  （extack `Match already configured`），记 `Could not configure driver mode` 后走错误路径
  deinit 并 SIGSEGV。脚本现在先 `kill -0` 查 `/run/hostapd-<name>.pid`：活着就打印 pid 直接
  返回 0（顺带让 `start` 幂等），pidfile 陈旧（进程已死）则照常起。判据仍是
  `hostapd_cli -p /run/hostapd-<2g|5g> status`。
* **串口上"停在 COUNTRY_UPDATE"是正常样子**（2026-09-23 澄清，别再当故障查）：
  conf 有 `country_code=CN`，冷启动时驱动报的当前 regd 是 `00`，于是
  `hostapd_setup_interface()`（`hostapd.c:2047`）`set_country()` 成功后设
  `wait_channel_update` 并注册 5 秒超时即返回；`main()` 接着进
  `hostapd_global_run()` 的 `os_daemonize()`（`-B` 的 `daemon(0,0)`），
  stdout/stderr 全进 `/dev/null`。这份 hostapd 只有 stdout 一个日志出口
  （overlay.nix 的 defconfig 没有 `CONFIG_DEBUG_SYSLOG`/`CONFIG_DEBUG_FILE`，
  所以 `-f` 也是空转；conf 里的 `logger_syslog` 只管 hostapd_logger 的模块位），
  fork 之后的 `DISABLED`/`ENABLED` 或失败退出**在串口上完全看不见**：成功与失败同形。
  串口上只会出现两行——`rfkill: Cannot open RFKILL control device`（`MSG_INFO`；内核
  `# CONFIG_RFKILL is not set`，没有 `/dev/rfkill`，不影响 AP）与
  `wlanN: interface state UNINITIALIZED->COUNTRY_UPDATE`。
  判据一律用 `hostapd_cli -p /run/hostapd-<2g|5g> status`（`state=ENABLED`）；
  要看全过程则先 `wlan-<band> stop`，再前台跑
  `hostapd -d -i <dev> /nix/store/<hash>-hostapd-<2g|5g>.conf`。
  `wlan-<band> start` 现在起完会轮询控制接口把最终 state 打出来，不是 ENABLED 就返回非 0。
* SSID 与频段：`CHEN`（AHB 2.4G，ch6）、`CHEN_5g`（AHB 5.8G，ch149）。
* **不开机启动**：`wlan-2g` / `wlan-5g [start|stop|status]` 手动起（hostapd `-B` 守护）；
  两个 radio 不加入 `int` 网桥，本阶段只验关联，不做转发。
  这两个脚本以前打成 `writeShellScript`（单个裸文件，`defaultProfile.packages` 的 PATH
  指向不存在的 `<store>/bin`，于是 `wlan-2g: not found`），已改为 `writeShellScriptBin`。
* **验证**：`iw dev` 两个 pdev、`dmesg | grep -iE 'wcss|ath11k'` 出现 `FW memory mode: 1`
  与 `WLAN.HK.2.12-01460`；`hostapd_cli -p /run/hostapd-<2g|5g> status` 为 `state=ENABLED`。
* 未纳入的第一方补丁：旧分支的 `960`/`961`（AHB CE IRQ 在 Q6 停止后的守卫）本轮**不进**，
  先只跑上游补丁；若真机出现 CE IRQ 的 synchronous external abort 再补。

* **风险**：AHB 无线与 NSS 的 QRTR/固件加载时序、保留内存冲突；QCN9074 的
  `fw_mem_mode`/MHI-790 等历史坑（阶段二）。

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
| N5 | ✅ 真机：`iw dev` 两个 AHB pdev、`FW memory mode: 1`、Q6 跑 `WLAN.HK.2.12-01460`；9-23 热替换固件那一版 `CHEN`/`CHEN_5g` 两个 hostapd 都 `state=ENABLED`；固件与 `CRYPTO_MICHAEL_MIC=y` 都进镜像这一版，2.4G `CHEN` `state=ENABLED` 且客户端已关联（`num_sta[0]=1`），5.8G 待起。**Q6 固件必须 pin fork 那一版**，linux-firmware 的 2.7.0.1 让 5.8G 必崩（见 N5 阶段一） |

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
7. **ath11k fw-memory-mode**（*N5 真机更正*）：没有 DT 覆盖，903 生效，AHB 实际跑 mode 1
   （8 vdevs / 128 peers）——正是参考实现 fork board dts + 903 的组合，两个 pdev 实测正常。
   旧文"`overrides.dtsi` 设成 mode 0"是错的，未实测的 mode 0 也不再是目标。
   QCN9074（阶段二）节点同样是 `<1>`，而旧分支实测那里要 mode 2 才不振荡
   （见 ax6600 分支 `DEVELOPMENT_LOG` 4.7/4.8），阶段二定稿时再改 PCI 节点。
8. **AHB 固件版本**（*N5 真机*）：`linux-firmware` 的 `IPQ6018/hw1.0` 2.7.0.1-02409 在 5.8G
   AP 的 peer create 上必断言；`ath11k-firmware-ddwrt@0c817c46` 的 2.12-01460 正常。
   台账在 `wireless/SOURCES.nix`。注意 `/lib/firmware` 是 RAM 镜像里的，热替换只在当次
   开机有效，必须落进构建。
9. **止损**：任何阶段失败都能回到 `re-cs-02` 的 PPE 有线镜像（已硬件验证）。

---

## 7. 待确认决策（已按推荐值写在上面，可改）

1. 基线：**6.18.52 + VIKINGYFY main 的 NSS 代**（备选：6.12 + LibWrt）。
2. 形态：**kmod + `pkgs/kmodloader` + tftpboot 镜像**（备选：fullSystem + `=y` graft）。
3. fork 派生补丁：**以独立补丁 + sha256 收录并标注来源**（备选：只作参考、自行重写）。
4. 文档语言与粒度：中文正文、每阶段单独确认后实施。

---

## 附录 

### QEMU 这条验证路径正式关闭（不要再试）



