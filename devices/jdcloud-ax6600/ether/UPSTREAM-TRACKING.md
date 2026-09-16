# 跟踪上游 ESS/PPE 以太网栈：现状与升级策略

这份文档回答一个问题：**这套"把上游驱动当自己代码"的做法怎么才能不烂掉。**
结论写在最前面，后面是核查证据。

> 更新（本分支）：文中的第 3 层 B 方案已经落地——`ether/src` 与
> `ether/patches` 已从仓库移除，29 个上游文件改由 `ether/SOURCES.nix` 的清单
> + `fetchurl` 在构建时取得。因此下文的"vendored"读作"由本仓库的清单钉住
> 的上游字节"，而不再是"抄进本仓库的字节"。

## 结论

1. **风险不是"本地有代码"，而是"本地代码没有身份"。** 现在身份已经有了：
   每个文件在 `ether/SOURCES.nix` 里都有 blob sha 和 sha256，本地不再存字节。
   这些补丁**到今天为止在 mainline 里仍然全都不存在**（连 7.2 都没有），
   所以"要自己承载"短期内不可避免，但承载方式已经从"抄一份"变成"钉住一份"。
2. **一旦上游合并，整套清单可以全部删掉**，只剩板级 dts。这是
   唯一正确的长期出口，应该主动盯着它，而不是被动等。
3. 按下面的三层改造，里程碑是：**升级内核从"手工逐补丁试"变成"一条命令得出
   结论"**。

## 核查证据（2026-09-10，均为实测）

### 上游仍然没有这些东西

对照 `v7.2`（当时最新 stable 为 **7.2.4**）：

| 文件 | mainline v7.2 |
|---|---|
| `drivers/net/ethernet/qualcomm/ppe/ppe.c` | **存在**（PPE 寄存器/配置库） |
| `drivers/net/ethernet/qualcomm/qca_edma.c` | 不存在 |
| `drivers/net/pcs/pcs-qca-uniphy.c` | 不存在 |
| `include/linux/pcs/pcs-provider.h` | 不存在 |
| `net/dsa/tag_oob.c` | 不存在 |

即：**越过 6.18 再升几个版本，也依然绕不开 vendor。** 升内核本身不能解决问题。

`net: pcs: implement Firmware node support for PCS driver`（Christian Marangi）
到 2026-08 还在 **RFC v14**，尚未进入 mainline；DSA out-of-band tagging
（Maxime Chevallier，2022 年首发）也仍未合并。

### OpenWrt 自己也还在带

`openwrt/openwrt@main`：`target/linux/qualcommax/Makefile` 里
`KERNEL_PATCHVER:=6.18`，`patches-6.18/0953-net-ethernet-qca-add-EDMA.patch`
仍然存在（HTTP 200）。

**这其实是好消息**：我们不是唯一维护者，上游有一支队伍在扛 net-core backport。
我们的角色应该是**下游消费者**，而不是独立维护者。

### 我们的本地命名已经跟上游错位了 —— 这就是"无法追踪"的具体形态

以 fwnode-PCS 那个最大的补丁为例：

| | 本地 | OpenWrt main |
|---|---|---|
| 文件名 | `737-04-net-pcs-implement-Firmware-node-…driv.patch` | `737-03-net-pcs-implement-Firmware-node-…driv.patch` |
| patch commit | `a90c644c73bbffd400cd3839fc17ffdfc69ea1e8` | `22774fb22c2338b77208e081d5bacf93582e5bb0` |
| series 标记 | `[PATCH 4/7]` | `[PATCH 03/12]` |
| 改动文件 | 5 个（Kconfig/Makefile/pcs.c/pcs-provider.h/pcs.h） | **同样 5 个** |

语义一致，但**编号和 commit 都变了**：上游把 series 从 7 个扩到 12 个，
我们这份取自更早的一轮（`4/7`）。后果是：

- 想按**文件名**比对本地与上游 → 直接错位，`737-02` 在两边根本不是一回事；
- 想按**行号**判断"这补丁还要不要" → 不知道它对应上游哪一条。

**但是**：`From <sha>` 这个 40 位 commit 是稳定可靠的交叉引用标记
（patch 正文没变，只有编号变了）。所以台账完全可行。

### 顺带查到的结构性问题：部分失败会被静默吞掉

`default.nix` 现在这样打补丁：

```sh
patch -p1 --forward --batch < $p || echo "…partially applied (expected): $p"
```

17 个补丁里任何一个**真的打失败**（不是预期的那两个），都会被这句
`|| echo` 吃掉，只有最后 3 个哨兵 `grep` 兜底。清单里明明列了 19 个补丁，
实际生效几个是**不可知的** —— 这是比"文件在本地"更该先修的问题。

## 建议的做法

### 第 1 层（现在就该做，成本最低）：来源台账 + 机械校验

给 `ether/` 加一个 `MANIFEST.nix`，**每个本地补丁记录它在上游的身份**：

```nix
{
  # 我们 vendored 这一版时，OpenWrt 的哪个 commit / 哪个文件
  upstream = {
    repo = "https://github.com/openwrt/openwrt";
    ref  = "<openwrt commit sha>";        # 取补丁时的上游基点
  };
  patches = [
    { local = "737-04-net-pcs-implement-Firmware-node-support-for-PCS-driv.patch";
      from  = "a90c644c73bbffd400cd3839fc17ffdfc69ea1e8";   # patch 自带 From:
      upstreamPath = "target/linux/generic/pending-6.18/737-03-net-pcs-implement-Firmware-node-support-for-PCS-driv.patch";
      role = "framework"; }        # framework = 上游在建，迟早能删；local = 我们的 workaround
    # ...
  ];
}
```

配一个 `ether/sync.sh`，能干三件事：

- `--check`：拉上游对当前的 patch，按 **`From <sha>` 匹配**（不信文件名），
  报告每个本地补丁是 `current` / `superseded`（上游有更新版）/ `merged`
  （上游文件消失 = 已进 mainline，可以删）；
- `--verify`：把本地补丁挨个往目标内核树上打，**逐补丁报告 hunk 级结果**，
  而不是像现在这样只靠 3 个哨兵 grep；
- `--refresh`：把上游最新版本拉下来覆盖本地，重排清单顺序。

关键点：**按 `From <sha>` 而不是文件名匹配**。这样即使上游重排编号
（就像 737-04→737-03 这次），也能自动找到对应关系。

### 第 2 层：修掉"静默部分失败"

在 `extraPatchPhase` 里把"期望部分失败"和"真失败"分开：

- 维护一份**期望部分应用**的白名单（目前是 `737-02`、`0950` 两个）；
- 其余补丁若失败 → **直接 `exit 1`**，附上 patch 的 reject 文件；
- 白名单里的补丁，校验"原本该改的文件都改到了"（按 `+++ b/` 清单比对），
  缺文件就报错。

这样"实际生效了几个补丁"变成确定值，`fixups.patch` 也不再是隐形的补丁。

### 第 3 层：用 Nix 的机制承载，而不是 shell 文本

**B 已经做了（见下）。** 这条线现在的形态是：文件本体不在仓库里，
`ether/SOURCES.nix` 只留 "路径 + blob sha + sha256 + 角色"，`default.nix` 用
`fetchurl` 取。剩下的 A 仍然可选：

**A. 让补丁走 Liminix 正规通道而不是 `extraPatchPhase`。**
`pkgs/kernel/default.nix` 已经有 `patches = [ … ]` 和 `patchFlags`，
`stdenv` 的 `patchPhase` 本来就会按序打、逐补丁失败即停。只需在
`modules/kernel/default.nix` 加一个 `extraPatches` 选项（接收 `path` 列表），
转发成 `patches`。好处：

- 按序严格应用，**默认失败即报错**；
- 每个补丁在 Nix 里是独立对象，能单独看、单独替换；
- 不再靠 3 个哨兵 `grep` 猜结果。

顺带一提：`extraPatchPhase` 这个钩子本身就是这条线上加的（commit `141eda3`
前后），所以改动面很小。

**B. 让源码/补丁集内容寻址。 —— 本分支已采用**
原来是把 29 个上游文件抄进 `ether/src` + `ether/patches`；现在整组搬进
`ether/SOURCES.nix` 的 `files` / `patches`，由 `fetchurl` 按
URL + sha256 取，本地一个字节都不留。"我们打的是哪一版"由 sha256 保证，
"这份字节是谁的"由 blob sha 保证，改动会在 diff 里显形而不是悄悄漂移。
代价是构建期需要网络（固定输出派生的 fetch 阶段），且上游一改就要更新
哈希——这正是想要的：漂移会变成构建失败，而不是静默。

做这件事时顺手把 ref 从 `f5043562`（6.12 世代）换到
`8d9475a`（6.18 世代，也就是 drivers vendored 的那一版）：板级 dts/dtsi
在两个 ref 上逐字节相同，只有 wifi-node 补丁从 `patches-6.12/` 挪到了
`patches-6.18/`，hunk 行号 `@@ -834` → `@@ -828`，正文不变。

### 第 4 层：盯"可以删掉"的时刻

这是长期唯一正确的出口。建议：

- 把 fwnode-PCS / PCS-provider 系列记进一个观察清单
  （`pcs-provider.h` 出现在 `torvalds/linux` 即为信号）；
- 一旦 **EDMA + UNIPHY PCS + fwnode-PCS + DSA OOB** 都进 mainline，
  就升级内核 → **清空 `ether/SOURCES.nix` 的清单**，只留板级 dts
  （那时 `ipq6018-ess.dtsi` 也大概率已经 mainline）。因为清单是文件列表，
  删就是删条目，没有遗留源码要清理。
- 判断标准很明确：`qca_edma.c` / `pcs-qca-uniphy.c` / `pcs-provider.h` /
  `tag_oob.c` 四个文件在目标内核里存在。

## 现状记录（本分支）

- 上游来源：`../SOURCES.nix` 的 pin `8d9475a99f03784210ff158f9f27c83a9c93a735`
  （immortalwrt，qualcommax 在 kernel 6.18）
- `ether.files`：10 个文件（qca_edma.c/h、qca_ppe.h、qca_ppe_main.c、
  qca_ppe_scheduler.c、qca_ppe_vlan.c、pcs-qca-uniphy.c、qca-uniphy.h、
  pcs-qca-uniphy.h、ipq6018-ess.dtsi），`install -D` 进内核树
- `ether.patches`：19 个补丁，按清单顺序应用（清单顺序 = 应用顺序）
- `ether/fixups.patch` 1 个（`0950` 打不干净的 hunk + 一行 `select PAGE_POOL`），
  本地文件。`737-02` 也有一个 hunk 打不上，但它的前序 hunk 已经把同样的交接做掉了，
  那个 guard 断言的 `mac_select_pcs` 本栈从不实现，所以**刻意不补**——见该文件抬头。
- 应用位置：`devices/jdcloud-ax6600/default.nix` 的 `kernel.extraPatchPhase`
- 内核基线：`6.18.49`（与 OpenWrt qualcommax `KERNEL_PATCHVER:=6.18` 对齐）
- 仓库里已无 `ether/src` 与 `ether/patches`
