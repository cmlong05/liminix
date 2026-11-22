# Deferred QCN9074 NSS Initialization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep NSS Wi-Fi offload enabled for both the IPQ6018 AHB radios and QCN9074, while moving QCN9074 probe and NSS initialization until after the PPPoE WAN is ready.

**Architecture:** The early module tree keeps wired drivers and `ath11k_ahb`; a second module tree carries only `mhi`, `qrtr-mhi` and `ath11k_pci`. An s6 longrun waits outside the boot transaction for a PPP default route, loads the late tree, skips modules already present, and reruns the radio rename helper so QCN9074 receives `wlan52g`.

**Tech Stack:** Nix, s6-rc, Linux 6.18.57, ath11k, NSS, PPPoE.

**Spec:** `devices/jdcloud-ax6600/BRINGUP.md`, section N8.

## Global Constraints

- `devices/jdcloud-ax6600` is the only target.
- Keep QCN9074 NSS offload enabled.
- Do not build or run build tests without explicit authorization.
- Do not commit without review.
- Do not modify external source outside an independent patch.

---

### Task 1: Split QCN modules from the early module tree

**Files:**
- Modify: `devices/jdcloud-ax6600/nss/targets.nix`
- Modify: `devices/jdcloud-ax6600/images/ax6600-rootfs.nix`

**Interfaces:**
- Consumes: existing `pkgs.liminix.modules.build`.
- Produces: `earlyTargets` without `qrtr-mhi`/`ath11k_pci`; `qcnTargets` with those two modules in dependency order.

- [ ] **Step 1: Expose separate early and QCN target groups**

Change `wireless` to contain only `qcom_q6v5_wcss_sec` and `ath11k_ahb`, add `qcn = [ "qrtr-mhi" "ath11k_pci" ]`, and make `all` mean wired plus early wireless only.

- [ ] **Step 2: Build the late QCN tree**

Create `qcnModuleTree` from the same module roots and `qcn` targets, with the same ath11k module arguments as the early tree.

### Task 2: Load QCN after PPPoE and rename it

**Files:**
- Modify: `devices/jdcloud-ax6600/images/ax6600-rootfs.nix`
- Modify: `devices/jdcloud-ax6600/art.nix`

**Interfaces:**
- Consumes: `config.services.wan`, `config.services.modules`, `config.wireless.radioRenameScript`.
- Produces: longrun service `qcn-wifi`.

- [ ] **Step 1: Export the existing radio rename script**

Declare an internal package option `wireless.radioRenameScript` and assign the existing `art-apply` script derivation to it.

- [ ] **Step 2: Start QCN only after WAN**

Define `services.qcn-wifi` depending only on the early module service. Its `run` waits in the background for the `ppp0` default route, loops over the late `load-order`, skips modules already in `/sys/module`, and insmods the remainder.

- [ ] **Step 3: Rename the late QCN netdev**

Run `config.wireless.radioRenameScript` after the late modules load so the PCI radio MAC is renamed from `wlan2` to `wlan52g`.

### Task 3: Guard the split at build time

**Files:**
- Modify: `devices/jdcloud-ax6600/nss-wifi/check-built.nix`
- Modify: `devices/jdcloud-ax6600/nss-wifi/check-built.sh`

**Interfaces:**
- Consumes: early `moduleTree` and late `qcnModuleTree`.
- Produces: build failure when QCN modules regress to the early tree or disappear from the late tree.

- [ ] **Step 1: Accept both module trees in the check**

Pass the early and late roots as separate arguments.

- [ ] **Step 2: Assert the boundary**

Require `ath11k` and `ath11k_ahb` in the early tree; require `ath11k_pci`, `qrtr-mhi`, and their modalias entries in the late tree. Fail if `ath11k_pci` is present in the early tree.

### Task 4: Document and statically verify

**Files:**
- Modify: `devices/jdcloud-ax6600/BRINGUP.md`

- [ ] **Step 1: Record the startup contract**

Document that QCN9074 remains on NSS, loads after `ppp0` is ready, and is renamed after probe.

- [ ] **Step 2: Verify without building**

Run `nix-instantiate --parse` on modified Nix files, `sh -n` on modified shell files, the check against existing module trees where possible, and `git diff --check`.
