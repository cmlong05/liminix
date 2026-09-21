
## 0. 结论摘要

NSS 全称 Network Subsystem（网络子系统）
ESS 全称 Ethernet Switch Subsystem（以太网交换子系统）
PPE 全称 Packet Processing Engine（数据包处理引擎）

需要区分三个常被混用的层次：

| 名称 | 是什么 | 谁在驱动它 |
|---|---|---|
| **NSS** | SoC 内 uBI32 子系统 + 闭源固件（= NPU） | `qca-nss-drv` + `qca-nss-*`（QSDK 模块） |
| **PPE** | ESS 里的包处理硬件（datapath 引擎） | NSS 固件在满血路径下拥有它；in-tree 路径下由 `qca_ppe`（DSA）驱动 |
| **ESS/EDMA/UNIPHY** | SoC 内的以太交换、DMA、PCS/PHY 通道 | NSS 路径：`qca-ssdk` + `qca-nss-dp`；in-tree 路径：`CONFIG_QCOM_EDMA` + `PCS_QCA_UNIPHY` |

所以：**「NPU 是否就是负责 NSS 的部分」——是。** NSS 就是这颗 SoC 的 offload 引擎，
「NSS 满血」= 让 NSS 固件接管 datapath（而不是让 A53 用 in-tree PPE 驱动软件转发）。

### 0.2 以太交换芯片是否需要单独驱动？—— 需要的是 **SoC 内 ESS 交换**的驱动，不是外置交换芯片

* **需要单独驱动的是 SoC 内部的 ESS/PPE 交换**（`ess-switch@3a000000`）。NSS 路径下它是
  `compatible = "qcom,ess-switch-ipq60xx"`，由 **`qca-ssdk`**（Qualcomm Solomon SSD SDK）驱动，
  同一个驱动还负责 `ess-uniphy@7a00000`（UNIPHY/PCS）和端口 MAC 配置。
  MAC netdev 由 **`qca-nss-dp`** 提供（只 match `qcom,nss-dp`，EDMA 节点按名字 `"edma"` 查找，
  不是绑定 EDMA 节点）。
* **外置的 QCA8075 / QCA8081 不是受管交换芯片**，本板上它们以 **PHY package** 的方式使用：
  QCA8075 是 4×1G PHY 包（`ethernet-phy-package@0`，`qcom,qca8075-package`，PSGMII，
  PHY 地址 **24–27**），QCA8081 是 2.5G PHY（mdio 地址 12）。因此**不需要**额外的交换芯片驱动，
  只需要 MDIO 总线 + PHY 层（`qca-ssdk` 的 PHY 层，`IN_AQUANTIA_PHY=TRUE`、
  `IN_QCA808X_PHY=FALSE`；或 mainline `qca807x`/`qca808x` PHY 驱动）。

### 0.3 DTS 必须先解决，而且必须**整代切换**（NSS 代与 PPE 代不能共存）

当前分支的 DTS 是 **PPE 代**（immortalwrt `8d9475a99f` 的 board dts + `ipq6018-ess.dtsi`），
NSS 代是另一套**同名不同内容**的文件，两边互斥：

| | PPE 代（当前 pin，re-cs-02 已验证） | NSS 代（本计划要换到的） |
|---|---|---|
| ESS 交换 | `switch: ppe@3a000000 { compatible = "qualcomm,ipq6018-ppe" }` | `switch: ess-switch@3a000000 { compatible = "qcom,ess-switch-ipq60xx" }` |
| MAC/DMA | `edma { compatible = "qualcomm,ipq6018-edma" }` | `edma@3ab00000 { compatible = "qcom,edma" }` + `dp1..dp5 { compatible = "qcom,nss-dp" }` |
| 用户端口 | DSA 子节点 `swport1..swport5`（`pcs-handle = <&uniphy0 N>`、`ethernet = <&edma>`） | `aliases ethernet0..4 = &dp1..&dp5`，板级写 `switch_lan_bmp` / `switch_wan_bmp` / `qcom,port_phyinfo` |
| NSS 核 | 无 | `ipq6018-nss.dtsi`：`nss-common` / `nss@40000000` / `nss_crypto` / `nss-macsec0` |
| 内核 config | `QCOM_EDMA=y`、`QCOM_80211AX_PPE=y`、`NET_DSA=y`、`NET_DSA_TAG_OOB=y`、`PCS_QCA_UNIPHY=y` | 上述**全部关掉**，改用 kmod（SSDK/NSS 本身不进内核 config） |

旁证：上游 OpenWrt 已用 commit `16d110aee39a`（"qualcommax: replace NSS-DP DTSI with
PPE DTSI"）把 NSS 代从官方树里删掉，所以 NSS 代只能来自 QSDK/fork；而 openwrt issue
**#24423** 记录了同一块 jdcloud RE-CS-02：官方 PPE snapshot「绿灯亮但 LAN/WiFi 全无」，
而 NSS-DP+SSDK 栈正常 —— 这正是我们要走的路。

还有一个必须一起决定的点：`ipq6018-nss.dtsi` 依赖 `nss_region`（16 MiB）并引用了
`q6_region`/`m3_dump` 等保留内存，而 **AHB 无线**（N5）也用 q6/m3 区域，两者必须在 N1
一次性定好布局（见 4.1 的补丁 `0103`）。
