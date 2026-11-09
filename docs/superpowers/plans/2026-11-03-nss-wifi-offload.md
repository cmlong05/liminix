# NSS Wi-Fi Offload Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable the IPQ6018 AHB Wi-Fi data path to use Qualcomm NSS Wi-Fi offload while preserving sing-box routing and providing a runtime rollback.

**Architecture:** Fetch the pinned VIKINGYFY NSS patch tree at build time, adapt its `CPTCFG_*` patch syntax to the native 6.18.57 kernel, enable only the basic AP offload feature set, and keep ath11k's control path on mac80211. Explicit module load order plus artifact checks prevent an ath11k image without the matching NSS driver from booting silently.

**Tech Stack:** Nix, Linux 6.18.57, mac80211, ath11k, qca-nss-drv, ECM, nftables, sing-box, iperf3.

**Spec:** `docs/superpowers/specs/2026-11-03-nss-wifi-offload-design.md`

## Global Constraints

- `devices/jdcloud-ax6600` remains the only target.
- Do not build or run build tests until the user explicitly authorizes it.
- Do not commit without user review.
- Do not add external source trees to the repository; fetch and hash them during
  the build.
- Do not modify external source directly. Native-kernel differences must be
  represented as independent compatibility patches.
- Do not enable mesh, WDS, dynamic VLAN, or AP_VLAN offload in the first version.
- Keep `nss_offload=0` as a supported runtime rollback.
- Preserve the existing 80 MHz VHT/HE hostapd configuration.
- Treat 1200.9 Mbit/s as PHY rate, not an iperf3 acceptance target.

## File Structure

- Create `devices/jdcloud-ax6600/nss-wifi/SOURCES.nix` — pins the upstream
  source archive and patch directories.
- Create `devices/jdcloud-ax6600/nss-wifi/default.nix` — materializes the
  native-kernel NSS patch series from the pinned archive.
- Create `devices/jdcloud-ax6600/nss-wifi/check-patches.sh` — verifies patch
  count, filename order, and expected native-kernel symbols.
- Create `devices/jdcloud-ax6600/nss-wifi/compat/` — contains only local
  compatibility patches required by failed upstream hunks.
- Modify `devices/jdcloud-ax6600/default.nix` — applies the NSS patch series
  after the existing wireless patches.
- Modify `devices/jdcloud-ax6600/nss/qca-nss-drv/default.nix` — enables
  `WIFIOFFLOAD` and verifies exported Wi-Fi symbols.
- Modify `modules/kernel/default.nix` and `pkgs/kernel/default.nix` — allow
  ath11k's NSS symbols to remain unresolved until the matching driver loads.
- Modify `devices/jdcloud-ax6600/wireless/default.nix` — enables the ath11k
  NSS Kconfig symbols.
- Modify `devices/jdcloud-ax6600/nss/targets.nix` — documents and enforces the
  required module order.
- Modify `devices/jdcloud-ax6600/images/ax6600-rootfs.nix` — sets ath11k module
  parameters.
- Modify `devices/jdcloud-ax6600/BRINGUP.md` — records implementation status,
  validation commands, and rollback.

---

### Task 1: Pin and prepare the upstream NSS patch series

**Files:**

- Create: `devices/jdcloud-ax6600/nss-wifi/SOURCES.nix`
- Create: `devices/jdcloud-ax6600/nss-wifi/default.nix`
- Create: `devices/jdcloud-ax6600/nss-wifi/check-patches.sh`

**Interfaces:**

- Consumes: `pkgs.pkgsBuildBuild.fetchurl`.
- Produces: a derivation named `vikingyfy-nss-wifi-patches` containing
  `subsys/*.patch` and `ath11k/*.patch`.

- [ ] **Step 1: Write the source preflight test**

```sh
test -f devices/jdcloud-ax6600/nss-wifi/SOURCES.nix
test -f devices/jdcloud-ax6600/nss-wifi/default.nix
grep -q '683480add1822fdfbbdee77856753d7282d58b71' \
  devices/jdcloud-ax6600/nss-wifi/SOURCES.nix
grep -q 'E4q3aND6XXhWXhfiYM/FwY9gWabj9GY5wvOoyzUIdzE=' \
  devices/jdcloud-ax6600/nss-wifi/SOURCES.nix
```

Run the test before creating the files. Expected: the first `test -f` fails.

- [ ] **Step 2: Add the pinned source manifest**

```nix
{
  repo = "VIKINGYFY/immortalwrt";
  rev = "683480add1822fdfbbdee77856753d7282d58b71";
  src = {
    url =
      "https://github.com/VIKINGYFY/immortalwrt/archive/683480add1822fdfbbdee77856753d7282d58b71.tar.gz";
    sha256 = "sha256-E4q3aND6XXhWXhfiYM/FwY9gWabj9GY5wvOoyzUIdzE=";
    root = "immortalwrt-683480add1822fdfbbdee77856753d7282d58b71";
  };
  ath11kPath = "package/kernel/mac80211/patches/nss/ath11k";
  subsysPath = "package/kernel/mac80211/patches/nss/subsys";
}
```

- [ ] **Step 3: Materialize a native-kernel patch tree**

`default.nix` must unpack the pinned archive, copy only `subsys` and `ath11k`,
replace `CPTCFG_` with `CONFIG_` inside the copied patch files, and fail unless
the upstream counts remain 26 subsys and 75 ath11k patches.

```nix
{ pkgsBuildBuild }:
let
  source = import ./SOURCES.nix;
  archive = pkgsBuildBuild.fetchurl {
    name = "vikingyfy-${source.rev}.tar.gz";
    inherit (source.src) url sha256;
  };
in
pkgsBuildBuild.runCommand "vikingyfy-nss-wifi-patches" { } ''
  set -eu
  mkdir -p source $out
  tar -xzf ${archive} -C source
  root=source/${source.src.root}
  cp -a "$root/${source.subsysPath}" $out/subsys
  cp -a "$root/${source.ath11kPath}" $out/ath11k
  find $out -type f -name '*.patch' -exec \
    sed -i 's/CPTCFG_/CONFIG_/g' {} +
  test "$(find $out/subsys -type f -name '*.patch' | wc -l)" -eq 26
  test "$(find $out/ath11k -type f -name '*.patch' | wc -l)" -eq 75
''
```

- [ ] **Step 4: Add the patch-inventory preflight**

`check-patches.sh` takes the produced patch directory as `$1` and checks these
files and symbols before the kernel phase installs the tree:

```sh
#!/bin/sh
set -eu
patches=$1

test -f "$patches/subsys/199-001-mac80211-add-nss-support.patch"
test -f "$patches/ath11k/199-002-ath11k_nss-add-nss-driver-interface.patch"
test -f "$patches/ath11k/199-003-ath11k-add-nss-support.patch"
test -f "$patches/ath11k/999-920-ath11k-add-kernel-6_12.patch"

grep -q 'config ATH11K_NSS_SUPPORT' \
  "$patches/ath11k/199-002-ath11k_nss-add-nss-driver-interface.patch"
grep -q 'config MAC80211_NSS_SUPPORT' \
  "$patches/subsys/199-001-mac80211-add-nss-support.patch"
grep -q 'ath11k_nss_tx' \
  "$patches/ath11k/199-003-ath11k-add-nss-support.patch"
```

- [ ] **Step 5: Verify static syntax without building**

```sh
nix-instantiate --parse devices/jdcloud-ax6600/nss-wifi/SOURCES.nix
nix-instantiate --parse devices/jdcloud-ax6600/nss-wifi/default.nix
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 6: Review checkpoint**

Stop and request review of the pinned source, patch counts, and transform rule.
Do not commit until the user approves.

---

### Task 2: Integrate the NSS patch series into the native kernel

**Files:**

- Modify: `devices/jdcloud-ax6600/default.nix`
- Create: `devices/jdcloud-ax6600/nss-wifi/compat/001-native-kernel-6.18.57.patch`
  only if dry-run application finds a non-mechanical incompatibility.
- Modify: `devices/jdcloud-ax6600/kernel-checks.nix`

**Interfaces:**

- Consumes: the `vikingyfy-nss-wifi-patches` derivation from Task 1.
- Produces: a kernel source tree containing `ATH11K_NSS_SUPPORT`,
  `MAC80211_NSS_SUPPORT`, and `drivers/net/wireless/ath/ath11k/nss.c`.

- [ ] **Step 1: Add failing kernel source checks**

Add checks that fail on the current unmodified kernel:

```nix
{
  file = "drivers/net/wireless/ath/ath11k/Kconfig";
  needle = "config ATH11K_NSS_SUPPORT";
}
{
  file = "net/mac80211/Kconfig";
  needle = "config MAC80211_NSS_SUPPORT";
}
{
  file = "drivers/net/wireless/ath/ath11k/nss.c";
  needle = "ath11k_nss_tx";
}
```

- [ ] **Step 2: Run the checks against the current kernel phase**

Run the checks as part of `extraPatchPhase`. Expected: fail with
`config ATH11K_NSS_SUPPORT` missing.

- [ ] **Step 3: Wire the patch tree into `extraPatchPhase`**

Import `./nss-wifi`, store its output in `NSS_WIFI_PATCHES`, and apply the
patches after the existing wireless patch group:

```nix
nssWifiPatches = pkgs.pkgsBuildBuild.callPackage ./nss-wifi { };
```

```sh
export NSS_WIFI_PATCHES=${nssWifiPatches}
for p in "$NSS_WIFI_PATCHES"/subsys/*.patch; do
  apply_patch 3 "$p"
done
for p in "$NSS_WIFI_PATCHES"/ath11k/*.patch; do
  apply_patch 3 "$p"
done
${./nss-wifi/check-patches.sh} "$NSS_WIFI_PATCHES"
```

- [ ] **Step 4: Resolve only proven native-kernel incompatibilities**

If patch application fails, capture the first failing patch and rejected hunk.
Create `compat/001-native-kernel-6.18.57.patch` containing only the context
adaptation needed for that hunk, apply it after the affected upstream patch,
and rerun from the failing patch. Do not rewrite unrelated upstream hunks.

- [ ] **Step 5: Verify patch order statically**

```sh
find devices/jdcloud-ax6600/nss-wifi -type f -name '*.patch' | sort
grep -n 'NSS_WIFI_PATCHES' devices/jdcloud-ax6600/default.nix
git diff --check
```

Expected: `subsys` patches are applied before `ath11k` patches and the
compatibility patch, if present, is listed explicitly.

- [ ] **Step 6: Review checkpoint**

Stop and report the exact patch-application result. Do not build until the user
explicitly authorizes it.

---

### Task 3: Enable Wi-Fi offload in qca-nss-drv

**Files:**

- Modify: `devices/jdcloud-ax6600/nss/qca-nss-drv/default.nix`

**Interfaces:**

- Consumes: the existing `qca-ssdk` and `qca-nss-dp` package outputs.
- Produces: `qca-nss-drv.ko` with exported `nss_wifi_vdev_*` and
  `nss_wifili_*` symbols.

- [ ] **Step 1: Write a failing symbol check**

Add this to the package's `postInstall`:

```sh
grep -q 'nss_wifili_get_context' $out/Module.symvers
grep -q 'nss_wifi_vdev_tx_msg' $out/Module.symvers
```

Run it against the current package output. Expected: fail because
`WIFIOFFLOAD` is disabled.

- [ ] **Step 2: Enable only the required feature**

Remove `"WIFIOFFLOAD"` from `disabledFeatures`. Keep `"WIFI_LEGACY"`,
`"WIFI_EXT_VDEV"`, `"WIFI_MESH"`, and unrelated feature switches disabled.

- [ ] **Step 3: Verify the feature is no longer forced off**

```sh
! grep -q '"WIFIOFFLOAD"' devices/jdcloud-ax6600/nss/qca-nss-drv/default.nix
grep -q 'NSS_DRV_WIFIOFFLOAD_ENABLE' \
  devices/jdcloud-ax6600/nss/qca-nss-drv/default.nix || true
```

Expected: the first command succeeds; the second may print nothing because the
feature is enabled by omission from `disabledFeatures`.

- [ ] **Step 4: Review checkpoint**

Stop and request review of the feature boundary. No mesh or WDS feature may be
enabled in this task.

---

### Task 4: Build ath11k with NSS support and deferred NSS symbols

**Files:**

- Modify: `modules/kernel/default.nix`
- Modify: `pkgs/kernel/default.nix`
- Modify: `devices/jdcloud-ax6600/wireless/default.nix`
- Modify: `devices/jdcloud-ax6600/nss/targets.nix`

**Interfaces:**

- Consumes: patched kernel source from Task 2.
- Produces: `ath11k.ko` containing `nss_offload` and `frame_mode` parameters;
  module load order with `qca-nss-drv` first.

- [ ] **Step 1: Write the failing configuration assertions**

Add static checks requiring:

```sh
grep -q 'ATH11K_NSS_SUPPORT = "y"' \
  devices/jdcloud-ax6600/wireless/default.nix
grep -q 'ath11k.nss_offload=1' \
  devices/jdcloud-ax6600/images/ax6600-rootfs.nix
```

Expected: fail before implementation.

- [ ] **Step 2: Add explicit kernel options**

Add to `devices/jdcloud-ax6600/wireless/default.nix`:

```nix
ATH11K_NSS_SUPPORT = "y";
MAC80211_NSS_SUPPORT = "y";
ATH11K_MEM_PROFILE_512M = "y";
ATH11K_NSS_MESH_SUPPORT = "n";
```

- [ ] **Step 3: Support unresolved symbols for this kernel only**

Add an option to `modules/kernel/default.nix`:

```nix
allowMissingModuleSymbols = mkOption {
  type = types.bool;
  default = false;
  description = "Pass KBUILD_MODPOST_WARN=1 when building modules";
};
```

Pass it to `liminix.builders.kernel.override`, and in
`pkgs/kernel/default.nix` change the module build to:

```sh
make ${lib.optionalString allowMissingModuleSymbols "KBUILD_MODPOST_WARN=1"} \
  modules
```

Set `allowMissingModuleSymbols = true` only in
`devices/jdcloud-ax6600/default.nix`.

- [ ] **Step 4: Make load order explicit**

Keep `wired` before `wireless` in `nss/targets.nix` and add this comment above
the list:

```nix
# ath11k calls symbols exported by qca-nss-drv; wired loads first.
```

Add a static test:

```sh
awk '/wired = \\[/,/\\];/' devices/jdcloud-ax6600/nss/targets.nix |
  grep -q 'qca-nss-drv'
awk '/wireless = \\[/,/\\];/' devices/jdcloud-ax6600/nss/targets.nix |
  grep -q 'ath11k_ahb'
```

- [ ] **Step 5: Verify static configuration**

```sh
nix-instantiate --parse modules/kernel/default.nix
nix-instantiate --parse pkgs/kernel/default.nix
nix-instantiate --parse devices/jdcloud-ax6600/wireless/default.nix
nix-instantiate --parse devices/jdcloud-ax6600/nss/targets.nix
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 6: Review checkpoint**

Stop and request review. Do not build until explicitly authorized.

---

### Task 5: Activate ath11k NSS offload at boot

**Files:**

- Modify: `devices/jdcloud-ax6600/images/ax6600-rootfs.nix`

**Interfaces:**

- Consumes: ath11k built with `nss_offload` and `frame_mode`.
- Produces: boot parameters `ath11k.nss_offload=1` and
  `ath11k.frame_mode=2`.

- [ ] **Step 1: Write the failing boot-parameter check**

```sh
grep -q 'ath11k.nss_offload=1' \
  devices/jdcloud-ax6600/images/ax6600-rootfs.nix
grep -q 'ath11k.frame_mode=2' \
  devices/jdcloud-ax6600/images/ax6600-rootfs.nix
```

Expected: fail before the boot parameters are added.

- [ ] **Step 2: Add both module parameters**

Append to the rootfs image `boot.commandLine`:

```nix
"ath11k.nss_offload=1"
"ath11k.frame_mode=2"
```

- [ ] **Step 3: Verify static configuration**

```sh
nix-instantiate --parse devices/jdcloud-ax6600/images/ax6600-rootfs.nix
git diff --check
```

Expected: both commands exit 0.

- [ ] **Step 4: Review checkpoint**

Stop and request review. No build is allowed at this checkpoint.

---

### Task 6: Add built-artifact verification

**Files:**

- Create: `devices/jdcloud-ax6600/nss-wifi/check-built.sh`
- Create: `devices/jdcloud-ax6600/nss-wifi/check-built.nix`
- Modify: `devices/jdcloud-ax6600/images/ax6600-rootfs.nix`

**Interfaces:**

- Consumes: a kernel module tree containing `qca-nss-drv.ko` and `ath11k.ko`.
- Produces: exit status 0 only when both modules contain the expected support.

- [ ] **Step 1: Write the checker**

```sh
#!/bin/sh
set -eu
modules=$1
qca="$modules/lib/modules/0.0/qca-nss-drv.ko"
ath="$modules/lib/modules/0.0/ath11k.ko"

modinfo -F parm "$ath" | grep -q '^nss_offload:'
modinfo -F parm "$ath" | grep -q '^frame_mode:'
grep -aq 'nss_wifili_get_context' "$qca"
grep -aq 'nss_wifi_vdev_tx_msg' "$qca"
grep -aq 'ath11k_nss_tx' "$ath"
```

- [ ] **Step 2: Run the checker against the current image modules**

Expected failure: `nss_wifili_get_context` and `ath11k_nss_tx` are absent.

- [ ] **Step 3: Make the checker part of the image build**

Create `check-built.nix` so the check consumes the already assembled
`moduleTree`:

```nix
{ pkgs, moduleTree }:
pkgs.runCommand "check-nss-wifi-offload" {
  nativeBuildInputs = [ pkgs.kmod ];
} ''
  sh ${./check-built.sh} ${moduleTree}
  touch $out
''
```

In `images/ax6600-rootfs.nix`, create the checker derivation from the module
tree and force it into the image closure with a named marker:

```nix
nssWifiCheck = pkgs.callPackage ../nss-wifi/check-built.nix {
  inherit moduleTree;
};
```

```nix
filesystem.etc."liminix-nss-wifi.check" = symlink "${nssWifiCheck}";
```

The authorized build command is then:

```sh
./build.sh
```

Expected: image creation fails if either module lacks the required support. Do
not run the build until the user explicitly authorizes it.

- [ ] **Step 4: Review checkpoint**

Stop and request build authorization.

---

### Task 7: Device bring-up and offload verification

**Files:**

- Modify: `devices/jdcloud-ax6600/BRINGUP.md`

**Interfaces:**

- Consumes: an authorized, built, deployed image.
- Produces: recorded evidence that offload is active and that both radios work.

- [ ] **Step 1: Record module state**

```sh
cat /sys/module/ath11k/parameters/nss_offload
cat /sys/module/ath11k/parameters/frame_mode
lsmod | grep -E 'qca-nss-drv|ath11k'
dmesg | grep -Ei 'nss|ath11k' | tail -n 200
```

Expected: `nss_offload=Y`, `frame_mode=2`, and no ath11k/NSS probe failure.

- [ ] **Step 2: Verify both APs and association**

```sh
iw dev wlan24g info
iw dev wlan58g info
iw dev wlan24g station dump
iw dev wlan58g station dump
```

Expected: both APs beacon; 5.8 GHz remains 80 MHz; clients associate and pass
traffic.

- [ ] **Step 3: Verify an eligible forwarded flow**

Run iperf3 from the Wi-Fi client to a wired LAN host, not to the router itself.
During the test, read the ECM accelerated counters under
`/sys/kernel/debug/ecm`.

Expected: the flow appears in ECM's accelerated count, and throughput is no
worse than the pre-offload baseline.

- [ ] **Step 4: Verify host-terminated traffic remains functional**

Run the existing iPhone-to-`10.10.0.1:5201` test.

Expected: traffic continues to work. Do not require PHY-rate throughput because
the TCP endpoint is on the router CPU.

- [ ] **Step 5: Record results**

Append the exact commands, observed module parameters, offload counters, and
iperf3 summaries to `BRINGUP.md` under N6.

- [ ] **Step 6: Review checkpoint**

Stop and request review of device evidence before enabling this in a default
image.

---

### Task 8: Validate and, if required, enforce sing-box coexistence

**Files:**

- Modify: `devices/jdcloud-ax6600/sing-box.nix`
- Modify: `devices/jdcloud-ax6600/sing-box/config_temp.json`
- Create, only if the no-acceleration assertion fails:
  `devices/jdcloud-ax6600/nss/ecm-mark-guard/default.nix`
- Create, only if the guard is required:
  `devices/jdcloud-ax6600/nss/ecm-mark-guard/ecm_mark_guard.c`

**Interfaces:**

- Consumes: sing-box marks `0x2023`, `0x2024`, and `0x2025`; ECM mark callback
  API from `ecm_classifier_mark_public.h`.
- Produces: a verified invariant that proxied traffic stays out of ECM while
  unproxied forwarded traffic remains eligible.

- [ ] **Step 1: Make the marks explicit**

Set these fields in the TUN inbound:

```json
"auto_redirect_input_mark": "0x2023",
"auto_redirect_output_mark": "0x2024",
"auto_redirect_reset_mark": "0x2025"
```

- [ ] **Step 2: Verify the generated nftables table**

```sh
nft list table inet sing-box
cat /proc/net/nf_conntrack | grep -E 'mark=(8419|8420|8421)'
```

Expected: proxied connections carry one of the configured marks.

- [ ] **Step 3: Run proxied and direct tests**

Request a proxied destination and an excluded/direct destination. Record the
public source address for each and inspect ECM accelerated counters before and
after each request.

Expected:

- Proxied flow: correct proxy path; no increase in ECM accelerated count for
  that five-tuple.
- Direct flow: correct direct path; ECM accelerated count may increase.

- [ ] **Step 4: Add the guard only if proxied traffic is accelerated**

The guard registers one mark callback:

```c
static ecm_classifier_mark_result_t
ecm_mark_guard_get_mark(struct sk_buff *skb, uint32_t *mark)
{
	switch (skb->mark & 0xffffff) {
	case 0x2023:
	case 0x2024:
	case 0x2025:
		return ECM_CLASSIFIER_MARK_RESULT_NOT_YET;
	default:
		return ECM_CLASSIFIER_MARK_RESULT_NOT_RELEVANT;
	}
}
```

Register it under `ECM_CLASSIFIER_MARK_TYPE_L2_ENCAP`, load it after ECM, and
set `/sys/kernel/debug/ecm/ecm_classifier_mark/enabled` to `1` before testing.

- [ ] **Step 5: Re-run coexistence tests**

Repeat Step 3. Expected: proxied flows remain absent from ECM accelerated
counts, while direct flows still accelerate.

- [ ] **Step 6: Review checkpoint**

Stop and request review. Do not disable all ECM acceleration as a workaround.

---

### Task 9: Finalize rollout and rollback documentation

**Files:**

- Modify: `devices/jdcloud-ax6600/BRINGUP.md`

**Interfaces:**

- Consumes: evidence from Tasks 6–8.
- Produces: an operator-facing rollback and verification procedure.

- [ ] **Step 1: Document runtime rollback**

Add the exact temporary boot change:

```text
ath11k.nss_offload=0
```

State that this requires a reboot and returns ath11k to the software path.

- [ ] **Step 2: Document the image rollback**

Record that reverting the N6 commit and rebuilding restores the previous
image. State explicitly that this work does not modify partitions or ART.

- [ ] **Step 3: Document sing-box behavior**

Record:

- Proxied traffic stays in the sing-box/TUN path and is not NSS-accelerated.
- Direct/excluded traffic remains eligible for NSS acceleration.
- Firewall full reload still restarts sing-box because it recreates the
  `inet sing-box` table.

- [ ] **Step 4: Run final static checks**

```sh
nix-instantiate --parse devices/jdcloud-ax6600/default.nix
nix-instantiate --parse devices/jdcloud-ax6600/nss/qca-nss-drv/default.nix
nix-instantiate --parse devices/jdcloud-ax6600/wireless/default.nix
nix-instantiate --parse devices/jdcloud-ax6600/images/ax6600-rootfs.nix
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 5: Final review checkpoint**

Present the complete diff and device evidence. Do not commit or merge until the
user explicitly approves.

