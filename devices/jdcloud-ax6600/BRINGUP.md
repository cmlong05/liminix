# JDCloud AX6600 (RE-CS-02) — Liminix **wired-only (no wifi)** bring-up

Branch: `test` (based on `dd65cce0bbc644396a6d7c0e440c4c895a68f944`).

This branch carries the **Ethernet (phase E) work only**. Every trace of
the radio work has been deliberately removed; see
[What was excluded](#what-was-excluded-no-wifi) at the bottom for the
exact list. Peer branch `ax6600` carries the full radio bring-up.

Status: **Ethernet kernel port + board wiring landed and build-verified;
on-hardware validation pending** (the board is not currently reachable
for this branch). The configuration here is a copy of the wired-only
configuration that was built and booted on hardware on the `ax6600`
branch, with the wifi parts taken out — no driver code was modified.

## Background / hardware

- Kernel baseline: **Linux 6.18.49** (kernel.org, fetched from the ustc
  mirror), chosen over 6.12.60 because the Qualcomm in-tree ethernet
  drivers need phylink/PCS features that 6.12 lacks (see below).
- IPQ6010 (4x Cortex-A53), 128 GB eMMC, serial console on BLSP1 UART3
  (`ttyMSM0`, 115200 8N1).
- Community "unbrickable" U-Boot (2016.01-based) with a web UI at
  http://192.168.1.1 (`/uimage.html` uploads and boots a FIT image,
  `/initramfs.html` does the same on some builds).
- Ethernet: QCA8075 4x1G (`lan1`..`lan4`) + QCA8081 2.5G (`wan`),
  driven by the ESS/PPE/EDMA/UNIPHY stack.
- WiFi: **absent** — no PCIe node, no ath11k, no wireless kernel
  config, no `wlan*` interface.

## Why the ethernet driver had to be vendored

The SoC-side ESS/EDMA data path is **not in mainline**, which is why
`./ether/` exists. Verified against `linux-6.18.49.tar.gz`:

mainline 6.18.49 **already provides**:

- `drivers/net/ethernet/qualcomm/ppe/` — the PPE register/configuration
  library (`CONFIG_QCOM_PPE`), used as-is;
- the `mdio@90000` node in `ipq6018.dtsi` (`qcom,ipq6018-mdio`,
  `qcom,ipq4019-mdio`) and its `CONFIG_MDIO_IPQ4019` bus driver;
- `CONFIG_IPQ_CMN_PLL` (the base CMN PLL driver) and the QCA8075/QCA8081
  PHY drivers;
- pinctrl, `clk`, cpufreq, SDHCI, watchdog.

mainline 6.18.49 **does not provide** (hence vendored):

| Missing | Consequence |
|---|---|
| EDMA netdev driver (`qca_edma.c`) | `CONFIG_QCOM_PPE` only registers a platform driver and creates **no netdev**; `CONFIG_QCOM_EMAC` matches only `qcom,fsm9900-emac` (older SoC). IPQ6018 has no usable netdev driver in mainline. |
| UNIPHY PCS driver (`pcs-qca-uniphy.c`) | `lan1..lan4` reach the SoC over QCA8075 **PSGMII**, and `wan` is QCA8081 **2500base-x**; both need the UNIPHY PCS. |
| fwnode-PCS framework + phylink PCS ops (`703-0x`, `737-0x`) | the UNIPHY driver calls `fwnode_pcs_add_provider()`, which 6.18 mainline does not have. Net-core backport, not driver bloat. |
| DSA out-of-band tagging (`NET_DSA_TAG_OOB`) | how the PPE switch exposes `lan1..lan4`/`wan` as individual netdevs. |
| IPQ6018 CMN-PLL driver data + gcc-ipq6018 clock workarounds (`0080/0082/0191/0904/0917`) | networking clocks; still out of tree upstream. |

This is exactly the same driver set that upstream OpenWrt / immortalwrt
ship for `qualcommax` on kernel 6.18, where it is also **built into the
kernel** (their ethernet is not a package and needs no config switch —
disabling wifi in an upstream build only turns off `kmod-ath11k*`).
Provenance and patch-by-patch notes: `./ether/README`.

## Build

Full-system ram image (single FIT, no root device and no serial console:
uploaded through the U-Boot web UI, and the only image on this branch):

```console
$ nix-build --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-lan-ram.nix -A outputs.uimage -o result-lan-ram
$ md5sum result-lan-ram      # record before flashing
```

## Boot it

1. Put the board in U-Boot web failsafe mode, browse to
   http://192.168.1.1/uimage.html, upload `result-lan-ram`.
2. Click start (or `bootm <addr>` from the serial console at the address
   printed in the upload log).
3. Expect the kernel log followed by a BusyBox shell:

```
Run /init as init process
Running pre-init...
full-system initramfs: activating
s6-linux-init version 1.2.0.2
#
```

No serial console available? The red LED (GPIO 57) comes on at
pinctrl/gpio probe and the userspace service turns it off and green on
once s6 is running — see the dts comments.

## Verify (wired)

```sh
cat /proc/cmdline                  # no root= (full-system mode)
dmesg | grep -iE 'ppe|edma|uniphy|qca8075|qca8081|mdio'
ip link                            # lan1..lan4, wan, int
ip addr show int                   # the deployment's LAN address
```

Then plug a PC into `lan1`: it should get a DHCP lease from the
deployment's pool, be able to `ping` the address above, and reach ssh
(below). The address and pool are set in
`devices/jdcloud-ax6600/config.nix` (currently
`10.10.10.1/24`, pool `10.10.10.50-200`).
The 2.5G `wan` port runs a DHCP client and is expected to negotiate
`2500base-x`.

## SSH

`ax6600-lan.nix` imports `modules/ssh` and starts dropbear, so the board
is reachable over the LAN bridge without a serial console:

```console
$ ssh root@10.10.10.1
```

The credential is the `users.root.passwd` hash in `ax6600-dev.nix`, so
the serial-console login and ssh share it. The listen address is unset
(`address = null`), i.e. all interfaces - on this wired-only build that
is just the `int` LAN bridge and the 2.5G WAN. All `allow*` options in
`modules/ssh` default to `true`, so root may log in with a password; for
key-only auth pass e.g. `svc.ssh.build { allowPasswordLoginForRoot =
false; authorizedKeys = { root = [ "ssh-ed25519 AAAA... " ]; }; }`.

**Prerequisite that is easy to miss:** dropbear does not build on this
nixpkgs without a patch fix. `pkgs/dropbear/add-authkeyfile-option.patch`
is applied by `overlay.nix` to the nixpkgs `dropbear`, and the version in
nixpkgs here is **2026.91**, whose manpage switched from mdoc (`.It Fl`)
to man (`.TP`/`.B`) format. The patch's `manpages/dropbear.8` hunk
therefore only applies after being rewritten for the new format; it is
rewritten on this branch (verified by `patch -p1 --dry-run` against the
real 2026.91 source - all 6 files apply, with only benign offsets).
Without that rewrite, enabling ssh fails the dropbear build. This is why
the `ax6600` branch's own LAN image shipped without ssh.

## Hardware evidence from the `ax6600` branch (same config + wifi)

From a web-uploaded `result-lan-ram` boot log on the real board:

- Kernel 6.18.49 boots from the U-Boot web uploader; 4 CPUs, eMMC
  HS200, ramoops live.
- Ethernet: `qca-ppe`/`edma` probe; the DSA conduit port (`eth0`)
  reports 1G up. `lan1..lan4`/`wan` initially failed with
  `failed to connect to PHY: -ENODEV` — **root cause: `CONFIG_MDIO_IPQ4019`
  was missing**, so the QCA8075 package / QCA8081 never appeared on the
  MDIO bus. It is enabled in `devices/jdcloud-ax6600/default.nix` here,
  which was the fix. If you ever hit `-ENODEV` on the PHYs again, check
  that option first.
- Known benign warnings to expect:
  - `nss_crypto_clk_src: rcg didn't update its configuration` — root
    cause diagnosed and fixed, see "First boot on hardware" below.
  - repeated `notifier callback pcs_provider_notify already registered`
    from `phylink_create` under the backported fwnode-PCS code — an
    idempotency wart of the `737-05` backport, not fatal.

## First boot on hardware (this branch, 2026-09-11)

Booted the full-system ram image (`nix-build … -A outputs.uimage`) via
the U-Boot web uploader and logged in over ssh. **The wired system works
end to end.** Observed:

```
[    2.980] qca-ppe 3a000000.ppe: configuring for fixed/internal link mode
[    2.980] qca-ppe 3a000000.ppe: Link is Up - 1Gbps/Full - flow control off
[    3.148] … lan1 (uninitialized): PHY [90000.mdio-1:18] driver [Qualcomm QCA8075]
[    3.208] … lan2 (uninitialized): PHY [90000.mdio-1:19] driver [Qualcomm QCA8075]
[    3.264] … lan3 (uninitialized): PHY [90000.mdio-1:1a] driver [Qualcomm QCA8075]
[    3.320] … lan4 (uninitialized): PHY [90000.mdio-1:1b] driver [Qualcomm QCA8075]
[    3.378] … wan  (uninitialized): PHY [90000.mdio-1:0c] driver [Qualcomm QCA8081]
[    3.603] … lan2: configuring for phy/psgmii link mode … wan: phy/2500base-x
[    6.598] … lan3: Link is Up - 1Gbps/Full - flow control rx/tx
```

`int` came up on the deployment's address (then `192.168.9.1/24`; the
deployment values in `./config.nix` have since moved to `10.10.10.1/24`),
dnsmasq served a lease to the attached PC, and ssh worked over the
bridge. Two issues were found and resolved:

### 1. `nss_crypto_clk_src: rcg didn't update its configuration` (fixed)

A startup WARNING from `drivers/clk/qcom/clk-rcg2.c:136`, reached via
`qca_ppe_driver_init` → `of_clk_set_defaults` → `clk_set_rate` →
`clk_rcg2_set_rate_and_parent` → `update_config`. It is deterministic,
not a race:

- upstream OpenWrt's `ipq6018-ess.dtsi` asks for **600 MHz** on
  `GCC_NSS_CRYPTO_CLK`, but `ftbl_nss_crypto_clk_src` in mainline
  `gcc-ipq6018.c` only offers 24 MHz and 300 MHz (300 MHz is its max);
- no parent/divider can be configured for 600 MHz, so the `CMD_UPDATE`
  bit never self-clears and `update_config` WARNs and returns `-EBUSY`;
- on hardware the clock nonetheless settles at **300 MHz** (debugfs:
  `nss_crypto_clk_src` `clk_rate` = 300000000, `clk_parent` =
  `nss_crypto_pll`, `clk_enable_count` = 1) — so 600 MHz was never
  achievable and asking for it only produced the warning. The clock is
  genuinely held (enable count 1), so it is not a case of an unused
  clock being disabled.

**Fix:** the board devicetree overrides the crypto clock down to
`300000000`. That override used to be a local edit inside upstream's
`ipq6018-ess.dtsi`; that file is no longer carried here at all (it is
fetched from the pin in `SOURCES.nix` and is byte for byte upstream's),
so the deviation now lives in `overrides.dtsi` as a `&switch` fragment. The value is not invented —
VIKINGYFY's immortalwrt `owrt` branch carries exactly the same change
(`assigned-clock-rates = <300000000>, <300000000>;`).

### 2. `Failed to del … Multicast Database entry … -ENOENT` (not fixed, by choice)

Seen only when a LAN port's link state changes (it fired at t=283 s when
the cable was moved):

```
qca-ppe 3a000000.ppe lan3: Failed to del Host Multicast Database entry (object id=3) with error: -ENOENT (-2).
qca-ppe 3a000000.ppe lan3: Failed to del Port Multicast Database entry (object id=2) with error: -ENOENT (-2).
```

The bridge tears down multicast state that was never installed, and the
driver reports the resulting `-ENOENT` as an error. Harmless — ssh
survived the same link event — and it is upstream's own behaviour.

Deliberately **not** patched: `qca_ppe_*` is vendored verbatim so it can
be diffed mechanically against upstream, and the whole point of the
`test` branch is to stay aligned. Fixing it would trade a cosmetic log
line for that ability. Revisit only if multicast misbehaves.

### 3. Memory: 3 GiB correctly visible (dts node already removed)

`dmesg` reports `Memory: 2938036K/3145728K available`, i.e. the full
3 GiB, although this board is the upgraded unit. **No `memory` node is
declared in the dts**, and that is deliberate and load-bearing: adding
one back would be *worse* than useless, because U-Boot's
`fdt_fixup_memory_banks()` finds its node by name (`/memory`) and thus
will not match a unit-addressed `memory@40000000` — it creates a second
node, and `early_init_dt_scan_memory()` ADDS UP every `device_type =
"memory"` root node. A stale node would not be corrected, it would be
summed into a block of non-existent RAM. OpenWrt, immortalwrt and
VIKINGYFY likewise ship no memory node for this board.

Diagnostic if RAM is ever under-reported: check the `Memory:` line. If it
reads 1 GiB, the bootloader fixup did not happen, and the thing to add is
a **bare `/memory` node** (not `memory@…`), which the fixup will then
overwrite rather than duplicate.

## What was excluded (no wifi)

Relative to the `ax6600` branch (`ca25acc`), the following were **not**
brought over:

- `devices/jdcloud-ax6600/patches/100-wcss-ipq6018.patch` — `q6v5_wcss`
  remoteproc driver data for the AHB radio.
- `devices/jdcloud-ax6600/patches/110-ipq6018-wifi-node.patch` — the
  `wifi@c000000` ath11k AHB node added to `ipq6018.dtsi`.
- The whole ath11k firmware staging service (`firmware-ath11k`), the
  QCN9074 `board-2.bin` fetch, the ART pre-cal extraction and the
  `ath11k` kmodloader target in `devices/jdcloud-ax6600/default.nix`.
- The `filesystem.lib.firmware.ath11k` mount point.
- PCIe/PHY/REMOTEPROC kernel config (`PCI`, `PCIE_QCOM`, `PHY_QCOM_QMP*`,
  `REMOTEPROC`) and the entire wireless `conditionalConfig` block
  (`WLAN`, `ATH_COMMON`, `ATH11K*`, `QCOM_Q6V5_WCSS`, `QCOM_SMP2P`, ...).
- `wlan0` from `hardware.networkInterfaces`, and the `iw` package from
  `ax6600-lan.nix`.
- The `pcie_phy`, `wifi` and `pcie0` (with its ath11k child) nodes from
  the board dts, plus the PCIe comment block.
- The wifi-only top-level configs `ax6600-wifi.nix`, `ax6600-wifi-ram.nix`
  and `ax6600-ram.nix`.

`modules/wlan.nix` itself still exists in the tree (it is an upstream
base file at this commit), but **nothing in this branch imports it**, so
no wireless kernel code or config is pulled in. The kernel's `WLAN`
symbol therefore stays `n`.

## Next steps

1. Build `result-lan-ram`, verify the md5, boot it, and capture the
   ethernet probe lines.
2. Confirm a DHCP lease on `lan1` and `2500base-x` on `wan`.
3. Read the label MAC from the eMMC `0:ART` GPT partition and set it on
   the interfaces (`mtd_get_mac_binary` equivalent) — not done yet.
