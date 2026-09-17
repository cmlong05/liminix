# The wifi port's own manifest: every upstream byte it puts into the kernel
# tree, in the order it is applied, and the reference material it is derived
# from. Read this before touching the wireless side of the device.
#
# The rule is ../SOURCES.nix's rule: upstream's bytes are NOT committed to
# this tree. `default.nix`'s extraPatchPhase fetches each entry below by URL
# (from the pin in ../SOURCES.nix, or from one of the secondary pins declared
# here) and applies it. What is left in this directory is only what the port
# genuinely owns: the five patches in `localPatches`, and `README`.
#
# Why the port looks like this: ImmortalWrt's wifi support for this board is
#   upstream Linux 6.18 ath11k
#     + package/kernel/mac80211/patches/ath11k/*.patch      (the `ath11k` list)
#     + target/linux/qualcommax/patches-6.18/*.patch        (the `kernel` list)
#     + target/linux/generic/pending-6.18/790-...patch      (the `kernel` list)
#     + linux-firmware + ipq-wifi board data + ART calibration
# and nothing else: the backports tree OpenWrt builds mac80211 from is
# upstream Linux plus those patches, not vendor code (research/port/ proves
# this byte for byte). So the port is a patch set plus firmware, applied to
# the same 6.18.49 kernel the rest of this device builds.
#
# One class of ImmortalWrt input is deliberately NOT applied: the 21
# mac80211/cfg80211 "subsys" patches, which are listed under `subsys` for
# provenance. They are OpenWrt's wireless-stack enhancements (DFS grace
# periods, AQL, rate-control changes, VHT-on-2G), not driver code this board
# needs, and when applied to this tree they break radio bring-up (both radios
# fail at firmware-ready with a BDF download timeout - see the ax6600
# branch's DEVELOPMENT_LOG 4.13/4.14). They stay one line away from being
# enabled, and the reason they are off is recorded with them.
#
# Every sha256 below is a flat file hash - what fetchurl wants:
#   nix-hash --flat --type sha256 --sri <file>
# and every `blob` is the git blob id of the same file at the pinned ref, so
# an identity can be re-checked even when a file name exists in several forks
# with different content.
pin:
let
  # ── Secondary pins ───────────────────────────────────────────────────
  #
  # These are not alternatives to ../SOURCES.nix's immortalwrt pin: they are
  # the other places a piece of this port comes from, each pinned to a commit
  # or tag, never to a branch.

  # The upstream kernel whose commits this port cherry-picks. ath11k fixes
  # land in mainline after 6.18.49; ImmortalWrt's own 6.18 backports tree
  # (which is where its driver really comes from) carries them, our kernel
  # tarball does not. They are fetched from the commit itself - the patch
  # text and its provenance are then the same object, and `commit` in the
  # `linux` list below is the identity.
  linux = {
    repo = "https://github.com/torvalds/linux";
  };

  # Board data (BDF) for the QCN9074. This is the repository ImmortalWrt's
  # package/firmware/ipq-wifi pins; PROJECT_GIT there is openwrt's, and the
  # file is byte-identical at the commit the pin resolves to and at the
  # earlier f2c37a6b that the ax6600 branch used.
  qcaWireless = {
    repo = "https://github.com/openwrt/firmware_qca-wireless";
    ref = "0c67bbcca45f7fc00255dbb078754cac89d3f40e";
    rawBase = "https://raw.githubusercontent.com/openwrt/firmware_qca-wireless/0c67bbcca45f7fc00255dbb078754cac89d3f40e";
  };

  # IPQ6018 (onboard AHB radio) Q6 firmware. ImmortalWrt takes this from
  # CodeLinaro's ath11k-firmware at the commit below (package/firmware/
  # ath11k-firmware/Makefile, installed to /lib/firmware/IPQ6018/), and that
  # is what the q6v5_wcss driver asks for by name ("IPQ6018/q6_fw.mdt").
  cloAth11k = {
    repo = "https://git.codelinaro.org/clo/ath-firmware/ath11k-firmware";
    ref = "15f050122da5ef5bef2cc8c7c19dfb7f98060a49";
    rawBase = "https://git.codelinaro.org/clo/ath-firmware/ath11k-firmware/-/raw/15f050122da5ef5bef2cc8c7c19dfb7f98060a49/IPQ6018/hw1.0/2.5.0.1/WLAN.HK.2.5.0.1-03982-QCAHKSWPL_SILICONZ-3";
    version = "WLAN.HK.2.5.0.1-03982-QCAHKSWPL_SILICONZ-3";
  };

  # Reference only: OpenWrt master. Its ath11k set is the same as
  # ImmortalWrt's plus two AHB CE-interrupt fixes that ImmortalWrt at our pin
  # does not carry yet. They are listed under `reference.kernelReference`
  # rather than applied, because this port pins immortalwrt; the equivalent
  # protection on this tree is the port's own 961/960.
  openwrt = {
    repo = "https://github.com/openwrt/openwrt";
    ref = "552e617bd0ae18fce68fa1b9add4c4cc50da7d87";
    rawBase = "https://raw.githubusercontent.com/openwrt/openwrt/552e617bd0ae18fce68fa1b9add4c4cc50da7d87";
  };

  # VIKINGYFY's immortalwrt fork, at the revision the working reference unit
  # runs. Its ath11k set is the pinned immortalwrt's plus exactly two
  # patches: a port of the upstream mac_phy_caps stride fix (which this port
  # takes from Linux directly instead) and 950-...-mask-undefined-board-id,
  # which exists only in that fork. The latter is applied here from its
  # source rather than copied, so the fix is not duplicated in this tree.
  viking = {
    repo = "https://github.com/VIKINGYFY/immortalwrt";
    ref = "90448eeb2b8f5d172caedfe6d96ab3bacb058c09";
    rawBase = "https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/90448eeb2b8f5d172caedfe6d96ab3bacb058c09";
  };
in
{
  # The secondary pins above, resolved, so a consumer can fetch from them
  # without repeating a URL: `default.nix` reads wifi.pins.viking.rawBase for
  # the fork's patch and wifi.pins.cloAth11k.rawBase for the IPQ6018
  # firmware. Every entry under `patch`/`firmware` below names the pin it
  # belongs to.
  pins = {
    inherit linux openwrt viking qcaWireless cloAth11k;
  };

  # ── Kernel patches: remoteproc/wcss, MHI, PSCI ───────────────────────
  #
  # Applied to the kernel tree, in this order, exactly the order OpenWrt's
  # patch machinery produces from the numeric prefixes (generic before
  # target, then ascending). The order is load-bearing: 0112 adds the PRNG
  # proxy clock, 0113 adds the secure-PIL/QCOM-SCM path to q6v5_wcss, 0114
  # splits q6/m3 firmware, 0115/0116/0119 refine driver data and resets,
  # and 0136 is what actually populates the IPQ6018 entry (with
  # need_mem_protection = true and m3_firmware_name = "IPQ6018/m3_fw.mdt"),
  # which is the whole reason the onboard radio can boot.
  #
  # 0906 (the wifi@c000000 node) is deliberately absent here: ../SOURCES.nix
  # already carries it as `wifiNodePatch` because the board dts cannot
  # compile without it, and it is applied just before this list. 0907 patches
  # the same dtsi (the smp2p node), after it - the same relative order as
  # upstream's 0906 < 0907.
  #
  # All twelve apply to pristine 6.18.49 with zero fuzz, verified in that
  # order; nothing here needs a local fixup.
  kernel = [
    {
      path = "target/linux/generic/pending-6.18/790-bus-mhi-core-add-SBL-state-callback.patch";
      blob = "071627ea7dd0c7a7fa95b437a6c50ee4debb9a6a";
      sha256 = "sha256-0Fy+FhEfifjflmcuMwLH+3MHr/Nj9Zfy80ks0+CzWC4=";
      note = ''
        Notifies clients when the MHI device reaches SBL, fired from
        mhi_process_ctrl_ev_ring() when the device reports the SBL EE
        transition. ath11k patch 100 programs the QCN9074's unique QRTR
        service instance into BHI_ERRDBG2 from that callback, and the timing
        is decisive: with the callback at this site the radio boots and VHT80
        works, whereas the same write from the MHI state machine's
        DEV_ST_TRANSITION_SBL (the ax6600 branch's own 300-...patch) left the
        firmware unable to start QMI at all. This is why this port takes
        upstream's patch instead of keeping ours.
      '';
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0112-remoteproc-qcom-Add-PRNG-proxy-clock.patch";
      blob = "3f8a0217e84d47f69bea9da80c76c38247024227";
      sha256 = "sha256-/FtjHN5HQhTKOtKrECLH7zeOmViB4KxzT0PW1Yfx4m8=";
      note = "WCSS PRNG proxy clock: the Q6 needs it before it will run.";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0113-remoteproc-qcom-Add-secure-PIL-support.patch";
      blob = "b8fb95c92686f8265cdd6df81709c416256b0b52";
      sha256 = "sha256-PPW13yKzSxohq80zaxWMgG1v2A4ec2p3FjSNx9XWiHw=";
      note = ''
        Secure-PIL (QCOM_SCM PAS) support inside q6v5_wcss itself. The board
        uses it: 0136 sets need_mem_protection = true for IPQ6018, which is
        what the ax6600 branch hand-ported as its own 401-...-secure-pil.patch.
        ImmortalWrt applies this even though CONFIG_QCOM_Q6V5_WCSS_SEC is off -
        it is the non-SEC driver that grew the secure path.
      '';
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0114-remoteproc-qcom-Add-support-for-split-q6-m3-wlan-fir.patch";
      blob = "c2d9f3d604926b4a07150cb46a6aa8d35037f911";
      sha256 = "sha256-q7aJEXh7ScSSFAPxZ9MmuXibFCNyKs7F3pmdjsJONtQ=";
      note = "Split q6/m3 firmware loading - the m3 must be running before the Q6 (ax6600's 402-...).";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0115-remoteproc-qcom-Add-ssr-subdevice-identifier.patch";
      blob = "6fa25a35e5b2e86c08688d5cdd1ec9261b8089a8";
      sha256 = "sha256-CATJi4FFRVeB26kt5gsPpXJK5wvnJh4R10KG2q5ZZho=";
      note = "Per-SoC ssr subdevice name, needed by 0905.";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0116-v6.19-remoteproc-qcom_q6v5_wcss-use-optional-reset-fo.patch";
      blob = "a70c292d36f680bea47259f491611988c20bd0df";
      sha256 = "sha256-2WeaqC6/75frxHLuixDc0WDHlttyEFVGI6pKlHlZngc=";
      note = "wcss_q6_bcr_reset is optional on this SoC (ax6600's 105-...).";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0119-remoteproc-wcss-disable-auto-boot-for-IPQ8074.patch";
      blob = "17c8ee2d0da7a8c5c5e2b649e63e482041a563fd";
      sha256 = "sha256-R/Qt/xvwJ1jiD980qjG5XIJBQcfBGnev98ghYQIE69U=";
      note = ''
        auto_boot = false: ath11k_ahb boots the remoteproc itself
        (rproc_boot in ath11k_ahb_power_up), so the rproc must not boot at
        rproc_add. The ax6600 branch wrote the same thing unconditionally in
        its own 100-wcss patch; upstream makes it a wcss_data field.
      '';
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0136-remoteproc-qcom-wcss-populate-driver-data-for-IPQ601.patch";
      blob = "cb65a950a60efd5278d3f8be69ff6739916760ce";
      sha256 = "sha256-yOj39pK42W8rfMFuGE1jnTjvYimuC4SQC9MUZ1+2hFk=";
      note = ''
        The IPQ6018 driver data: q6_firmware_name "IPQ6018/q6_fw.mdt",
        m3_firmware_name "IPQ6018/m3_fw.mdt", need_mem_protection = true,
        requires_force_stop = true, and the of_match entry for
        "qcom,ipq6018-wcss-pil". This plus 0113/0114 is the entire "Stage B"
        secure-boot work the ax6600 branch carried as local 401/402/403.
      '';
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0903-psci-dont-advertise-OSI-support-for-IPQ6018.patch";
      blob = "45ede1ba0fafff17e821320a3cc7ef2f8eb8cbc7";
      sha256 = "sha256-WrQXJv0B4NtPSORN7qy3SHwOKTOC5rBFkizALkL8dR8=";
      note = ''
        IPQ6018's PSCI does not implement OS-initiated mode; advertising it
        makes CPUidle take a path the firmware does not support. This one
        touches a driver the wired-only image also builds, so it is not
        inert there - it is upstream's own fix for this SoC, and the wired
        image is expected to be re-tested after this port.
      '';
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0905-remoteproc-q6v5_wcss-change-ssr-name-for-ipq6018-wif.patch";
      blob = "463a72b4c30270692e7a2af1e93bd9706f7190d6";
      sha256 = "sha256-zmKO79TdgdOBLQ8GEpSa/vtMaw2DdBNPMymxPCX/yBU=";
      note = "The Q6's ssr name on IPQ6018 is \"wcnss\", not \"q6wcss\" (ax6600's 100-wcss).";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0907-soc-qcom-fix-smp2p-ack-on-ipq6018.patch";
      blob = "ae28c4cb92776294e2ec7bc586a1fb51df6d0336";
      sha256 = "sha256-wAfA06OTu9cDaA0PO0hov9BPqyv2cyxCp9IN/dK21r0=";
      note = ''
        Adds the smp2p "ack" interrupt to ipq6018.dtsi and the handling for
        it: without it the Q6's stop-ack never clears and rproc shutdown
        stalls. Touches the device tree the whole device shares.
      '';
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0908-remoteproc-qcom_q6v5_wcss-add-optional-qdss_at-clock.patch";
      blob = "768d7c2397666aa9b53aa03e33c9d031654da34d";
      sha256 = "sha256-fGYIj8w3DsA3UGkkdm0/YXa1A1M+Hx+wtDQaoSHeuRM=";
      note = "Optional qdss_at clock (ax6600's 201/202 pair).";
    }
  ];

  # ── ath11k driver patches (ImmortalWrt) ──────────────────────────────
  #
  # package/kernel/mac80211/patches/ath11k at the pin, minus the entries
  # listed under `ath11kReference`. Every one applies to 6.18.49 with zero
  # fuzz in this order. Notes are only where the patch is not self-evident,
  # or where it matters for this board.
  ath11k = [
    {
      path = "package/kernel/mac80211/patches/ath11k/100-wifi-ath11k-use-unique-QRTR-instance-ID.patch";
      blob = "72c1bd522034b96fa20536a507da778fd744d8b4";
      sha256 = "sha256-LEBsAxpnILWBpfHIMrj/x1OrXe8eP5M5Vg6BjKijA6Y=";
      note = ''
        Programs a per-device QRTR service instance into BHI_ERRDBG2 while
        the firmware is still in SBL, so two ath11k instances (this board has
        the PCIe QCN9074 and the AHB IPQ6018) do not clash on the ATH11K
        QRTR service. Needs the MHI-SBL callback above, and is the reason
        that patch is in this list.
      '';
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/101-wifi-ath11k-fix-wrong-usage-of-resource_size-causing.patch";
      blob = "5278688132f6a356d50546e29d72697852827295";
      sha256 = "sha256-5YZmbXFr26h42BVJqDGKFhFuo74ZWsBztlKv2gDLG9g=";
      note = "resource_size() misuse in the AHB/AON mapping - memory corruption on IPQ60xx.";
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/201-wifi-ath11k-Support-setting-bdf-addr-and-caldb-addr-.patch";
      blob = "ec1905e0b8d544f4eb25ce10f1ff43231073a7e6";
      sha256 = "sha256-hhAFr+bWLH0n2CBjtFC6tM/vn989/Ks9QZGUVFKaFeQ=";
      note = "Lets the device tree place the BDF/caldb in reserved memory instead of the firmware directory.";
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/453-ath11k-add-ath11k_mac_op_flush_sta-to-properly-flush.patch";
      blob = "bcb43829a14b9afe2688c543a931b4a7f7836751";
      sha256 = "sha256-xcEluYEwDMOHVxocQV7hibU4SLRqFcBw7LIBJvowvIQ=";
      note = "Per-station flush op; the reference driver has it, and it changes TX behaviour in AP mode.";
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/903-ath11k-support-setting-FW-memory-mode-via-DT.patch";
      blob = "cedb0345546f150bfde95bffe3e03796d24c0489";
      sha256 = "sha256-u/e7IBdz9U8IDw4fAhBkTGDp23UP4coKWnh4mYQy2Fc=";
      note = ''
        fw_mem_mode via device tree. Nothing in this port sets the property,
        so the mainline default (2) applies - the same mode the known-good
        ImmortalWrt build runs the QCN9074 in. The ax6600 branch found that
        forcing mode 1 made the carrier oscillate between 5180 and 5500 MHz.
      '';
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/906-wifi-ath11k-disable-coldboot-for-ipq6018.patch";
      blob = "031e6eb94ea3944822cca7a488225ecbcc4b8855";
      sha256 = "sha256-u5VC7cp1nM0Va0CsPauyjeBhRhytS02lN8pus9ZhuVw=";
      note = "IPQ6018's cold-boot calibration does not work; skip it.";
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/907-wifi-ath11k-disable-coldboot-calibration-for-ipq5018.patch";
      blob = "f8c3e91a4984bb60d365536d07d3df9673593ca4";
      sha256 = "sha256-R3TJTvVcQljTu+mdcDMg2n4vTdRp7uqhJrKE+3zjVZo=";
      note = "Same for IPQ5018. Not this board, but part of the pinned set and harmless.";
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/910-ath11k-fix-remapped-ce-accessing-issue-on-64bit-OS.patch";
      blob = "624f324a947586989e7dc39ab1c6f41079525f45";
      sha256 = "sha256-aiKQ1O3YhSxD27DrxcbJW9qpLdXKTc0izL5M2dPQeBk=";
      note = "CE remapped-window access on 64-bit - an AHB crash fix.";
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/931-wifi-ath11k-Support-to-assign-m3-dump-memory.patch";
      blob = "35d2572d6603d8ab468063352727ecef0822eb09";
      sha256 = "sha256-Lb6pNkHHQvxATjvaqrDEmNNiXBAU+NcRYD8Q6KHAkgI=";
      note = "m3 dump memory assignment; part of the AHB crash-report path.";
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/948-wifi-ath11k-Fix-the-WMM-param-type.patch";
      blob = "a5c03d2bc50694744602c0a87ad3a21e96885f1b";
      sha256 = "sha256-HeNwgsNRqP4uW/RpGlkfKxBpO035TB6ehTwBP5VqlqU=";
      note = ''
        WMM parameter element type. Without it the firmware asserts when an
        AP starts (the ax6600 branch hit exactly this and called it the AP
        bring-up fix).
      '';
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/949-wifi-ath11k-fix-monitor-rx-pktlen.patch";
      blob = "4d4a6f184b39639780b8d359bc2c5b22d314dbac";
      sha256 = "sha256-dk5hpJr7Oe7lR1KveZOhS1Ucm+7JEyRDjwT93MaeUlk=";
      note = "Monitor-mode RX packet length; in the reference set.";
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/983-ath11k-Enable-VHT-for-2G.patch";
      blob = "605a7b51eb5ebbc93878ebce8a3be29213b15e94";
      sha256 = "sha256-d7iFhlacTHxLJVXaSFFgKvsCp99iD0uGvHeyX59Yykk=";
      note = "VHT on 2.4 GHz, pairs with the mac80211 600 patch (not applied here).";
    }
    {
      path = "package/kernel/mac80211/patches/ath11k/984-ath11k-workaround-for-memory-leak.patch";
      blob = "0efeea139796ab630cb75bedba9ac697db4dfe5a";
      sha256 = "sha256-qfSksATfjN+KulKEu3g9cMUFsh1bJx+3yl9wr7mo+AA=";
      note = "Reference-set memory leak workaround.";
    }
  ];

  # ── ath11k patches from the fork the reference unit runs ─────────────
  #
  # One patch, and only because it exists nowhere else: VIKINGYFY's fork is
  # what the working reference image is built from, and its ath11k set is
  # the pinned immortalwrt's plus this one (its only other extra is a port of
  # the Linux stride fix, which `linux` below takes from Linux itself).
  #
  # Applied through the same machinery as the immortalwrt list, from the
  # fork's own bytes: it is not our code, so it is not committed here.
  ath11kFork = [
    {
      path = "package/kernel/mac80211/patches/ath11k/950-wifi-ath11k-mask-undefined-board-id.patch";
      blob = "7dd8619d3078dcd610ea172dccba36be4eec275e";
      sha256 = "sha256-MloQEmGrXG7UfV/0EkTZdi4iFp6QV/D3h1SpIadg0BI=";
      subject = "wifi: ath11k: mask undefined board id to 0xff";
      note = ''
        Some firmware (the QCN9074 2.15.x the reference runs) reports the
        undefined board id as 0xffffffff instead of 0xff; the driver then
        looks for a BDF keyed qmi-board-id=-1 and fails. Masking it back to
        8 bits restores the default-id lookup. Harmless with firmware that
        reports 0xff already, which is why it is applied unconditionally:
        the ledger keeps the 2.15 firmware as a documented alternative.
      '';
    }
  ];

  # ── ath11k fixes from upstream Linux (cherry-picks) ──────────────────
  #
  # Fixes that are in ImmortalWrt's backports tree and in upstream Linux,
  # but not in the plain 6.18.49 tarball this device builds. Fetched from
  # the commit itself, so there is no local copy to rebase: all seven apply
  # cleanly on top of the ath11k list above. Kept in this order because the
  # three dp_rx hardening fixes build on each other (the first introduces
  # the helper the next one calls).
  #
  # The ax6600 branch carried these as local patches 102 and 1000-1005; this
  # list replaces them, which is why they are gone from localPatches.
  linux = [
    {
      commit = "7a246c72132eb943b5844ba79dad597b47429dba";
      sha256 = "sha256-UOCzyFS4U/6IQ6imoxBhNtOEJVvZqvD0P/QnlugUWGI=";
      subject = "wifi: ath11k: fix stride mismatch in mac_phy_caps_parse()";
      note = ''
        The ax6600 branch's local 102. It is in neither OpenWrt tree, so it
        is taken from Linux directly. Without it the mac_phy_caps parse walks
        a TLV with the wrong stride (heap over-read).
      '';
    }
    {
      commit = "ff49eba595df500e4ddccc593088c8a4ab5f2c27";
      sha256 = "sha256-taf7KVX4wWu6hb8W2Sl0hMDlfLhMS7zmlrk6zyYn+DM=";
      subject = "wifi: ath11k: fix memory leaks in beacon template setup";
      note = "AP mode beacon/EMA template leaks - this board is an AP.";
    }
    {
      commit = "ebad0b48996fd4919c36bbcb07289d37d046de74";
      sha256 = "sha256-Pbv2q75whNs/BtpKfQzNwj3DBzSYEn6YTRDtE8XM5XU=";
      subject = "wifi: ath11k: fix error path leaks in some WMI calls";
      note = "WMI error-path leaks; WMI is where a failing firmware handshake accumulates them.";
    }
    {
      commit = "72b8654e3b83548f64524add2e9145e9b6c8a852";
      sha256 = "sha256-KM4x2LQ72P2BLbNxrv5vjyO1P8a49mOyetQu5v4XqLM=";
      subject = "wifi: ath11k: fix use after free in ath11k_dp_rx_msdu_coalesce()";
      note = "RX hot path; use-after-free on freed rxcb.";
    }
    {
      commit = "6b471e9aefee9ed73278eb1141e0d8530a56fae9";
      sha256 = "sha256-mst4o8uhdVEJYCI6ZV0l5yoBpAFig0dEn+D19/O7fB8=";
      subject = "wifi: ath11k: fix invalid data access in ath11k_dp_rx_check_nwifi_hdr_len_valid()";
      note = "Validates the native-wifi header length on four RX entry points (invalid RBM guard).";
    }
    {
      commit = "4d8af936b4fe377f3d7700540f301d8e45e8759b";
      sha256 = "sha256-96TakjB1nJg7mGVZ0mggy9AfNRuAQKvZ+XOyeHwxVR0=";
      subject = "wifi: ath11k: add MSDU length validation for TKIP MIC error";
      note = "MSDU length bound before skb_put() in the TKIP MIC error path.";
    }
    {
      commit = "8c79aac429b583301f387374ff37c59be671df87";
      sha256 = "sha256-teuxF83zfhSkTCdVTteLNDHj1fwrOrek1fWQxXC+Nd4=";
      subject = "wifi: ath11k: cancel SSR work items during PCI shutdown";
      note = ''
        Cancels reset_work/dump_work in ath11k_pci_shutdown() and takes
        base_lock around the RDDM queue_work in mhi.c. Directly on the
        crash/recovery race this board kept hitting.
      '';
    }
  ];

  # ── Local patches: the part of the port that is ours ─────────────────
  #
  # Files in this directory. Each is here because no revision upstream can
  # supply it: either it guards a Liminix-specific boot shape (an initramfs
  # where the driver is built in and must not probe at kernel init) or it is
  # a defensive fix written against a failure seen on this board. `from`
  # records an upstream commit when the patch is a port of one, so the file
  # can be re-checked against upstream rather than trusted.
  local = [
    {
      file = "960-ath11k-ahb-mask-ce-irqs-before-rproc-shutdown.patch";
      subject = "ath11k: ahb: mask CE IRQs at the GIC before rproc_shutdown";
      from = null;
      note = ''
        With the AHB radio, CE interrupts stay live across rproc_shutdown();
        the register space is gone and the handler takes a synchronous
        external abort in IRQ context (panic). Masks them at the GIC first.
      '';
    }
    {
      file = "961-ath11k-ahb-ce-irq-guard-against-stopped-q6.patch";
      subject = "ath11k: ahb: guard CE IRQ handler against a stopped Q6";
      from = null;
      note = "Belt and braces for the same failure: the handler returns early when the Q6 is not running.";
    }
    {
      file = "970-ath11k-pci-safe-remove-when-fw-not-registered.patch";
      subject = "ath11k: pci: safe remove when firmware never registered";
      from = null;
      note = ''
        The QCN9074's early probe can fail before registration (MHI/SBL);
        tearing that device down must not run the registered-only teardown
        path, which reads a dead endpoint. Needed by the late-probe service,
        which unbinds a failed probe before retrying.
      '';
    }
    {
      file = "999-ath11k-skip-early-probe-until-userspace.patch";
      subject = "wifi: ath11k: skip early probe until userspace is running";
      from = null;
      note = ''
        Liminix-specific, and load-bearing for the ram image. ath11k is built
        in there (a full-system initramfs cannot load modules), so both
        radios would probe during kernel init - before the wifi service has
        staged the firmware and read the board's calibration out of the eMMC
        ART partition, and, for the QCN9074, too early for its MHI boot,
        which can leave it bound-but-dead. The patch returns -ENODEV from
        both probes while the kernel is still booting, so the devices stay
        unbound; the ath11k-probe service attaches them once the system is
        up, which is the ordering a modular ath11k gets for free.

        One patch for both buses on purpose: it is one decision about when
        this device may probe its radios, and a future upstream guard (or a
        return to modules) removes it whole.
      '';
    }
  ];

  # ── Not applied, and why ─────────────────────────────────────────────
  #
  # Kept as data so that "we looked, and chose not to" is reviewable, and so
  # that enabling one later is a one-line change with the hashes already in
  # hand.
  reference = {
    # The mac80211/cfg80211 "subsys" patch set at the pin: 21 patches to
    # net/mac80211, net/wireless and the shared headers. This is the only
    # large difference between our stack and the reference's, and it is off
    # because it breaks bring-up here:
    #   - all 21 + ath11k 453/905/949 -> both radios fail at firmware-ready
    #     (PCI "qmi failed to load bdf file", -110; AHB fails in
    #     ath11k_core_qmi_firmware_ready). Removing 905 changes nothing.
    #   - removing the 21 restores 2.4G and brings 5G back.
    # (ax6600 branch, DEVELOPMENT_LOG 4.13/4.14.) 23 of the 21 apply at
    # fuzz 0; 301 needs a one-line context fix (CPTCFG_ -> CONFIG_) and 304
    # hunk 4/8 needs a rebase - see research/port/.
    subsys = [
      { path = "package/kernel/mac80211/patches/subsys/110-mac80211_keep_keys_on_stop_ap.patch"; blob = "00f15c7ea230e88d4cfb99d06a6a5535a672fec9"; sha256 = "sha256-gM6OWXyJua77rRysW1f/nVXsSPjrUB3RmpgeCB4irvc="; }
      { path = "package/kernel/mac80211/patches/subsys/120-cfg80211_allow_perm_addr_change.patch"; blob = "f315ae5ca2baa210c10061b6ec7f26932a197802"; sha256 = "sha256-U+CJqGlWRLnIbJesYRYqgy/mX7hu78pqLn8VkEK4jlA="; }
      { path = "package/kernel/mac80211/patches/subsys/130-disable_auto_vif.patch"; blob = "84381f9038b8e328401e1ff1ca538ef0ea1ebccd"; sha256 = "sha256-TNp8leYNk5KVe53HnXUB4N5EgMosndnkgONAz0eeBdE="; }
      { path = "package/kernel/mac80211/patches/subsys/210-ap_scan.patch"; blob = "1daee3ae3da51af3b04afe80169395434b8d75c0"; sha256 = "sha256-X5FASySGWup7lH2X0RzHjoLWOd8L8vxmvlZIiPuJQ1Q="; }
      { path = "package/kernel/mac80211/patches/subsys/220-allow-ibss-mixed.patch"; blob = "53d224858d037081d0313583ad76b17d9f99e156"; sha256 = "sha256-n8AaGWj0b2Rzt7Wv1pfNoBOfz+v44HU5J4OVFGhNldo="; }
      { path = "package/kernel/mac80211/patches/subsys/230-avoid-crashing-missing-band.patch"; blob = "cd76db29bd7e7eb658e955a5f037ea5bf9cb8a32"; sha256 = "sha256-b5HFURwMnxrfT4BCG06D7co0Q2xD/pldJ7flAXBcPeg="; }
      { path = "package/kernel/mac80211/patches/subsys/301-mac80211-sta-randomize-BA-session-dialog-token-alloc.patch"; blob = "2396feb1b73d47dde076d53b00a4b6af8186d150"; sha256 = "sha256-bUaLRjJTqZfumOl1h35LvOVYUa7LObkxEoGAeHho8II="; }
      { path = "package/kernel/mac80211/patches/subsys/302-mac80211-minstrel_ht-fix-MINSTREL_FRAC-macro.patch"; blob = "0d475b73297d833ab18155b6c25b26675b0032ee"; sha256 = "sha256-vyGGd22WEiE2AZt7Ea6h8PRpFL8Qeqg8lJ5lQpD37tM="; }
      { path = "package/kernel/mac80211/patches/subsys/303-mac80211-minstrel_ht-reduce-fluctuations-in-rate-pro.patch"; blob = "f26477e8112f2e6f79634d352169a3df5853bc7f"; sha256 = "sha256-eNpcLAEbJnnxMJNmw5ZKkZYH21+ht2o+Qmxa9n7e1aE="; }
      { path = "package/kernel/mac80211/patches/subsys/304-mac80211-minstrel_ht-rework-rate-downgrade-code-and-.patch"; blob = "9b3cc3a664ac4d36e062151ee7028655c3dd7f8b"; sha256 = "sha256-SSn3qAM/NHFcKhm2BsRdDXEecyhFLtGzGlv1KgwacjI="; }
      { path = "package/kernel/mac80211/patches/subsys/305-mac80211-increase-quantum-for-airtime-scheduler.patch"; blob = "dac46ac6717b5752f6a46b0147b625f865b8dd48"; sha256 = "sha256-yh+P8zX4H5BJit3D3I/a3GeBJiIv+W20yiA8m50ZR9A="; }
      { path = "package/kernel/mac80211/patches/subsys/310-cfg80211-allow-grace-period-for-DFS-available-after-.patch"; blob = "0bf326f7c749f187294491ab112b166e622178f4"; sha256 = "sha256-pCiXXqHuelpL6NLWiHR8OHhORgel2vF1j6P8xnhX9N0="; }
      { path = "package/kernel/mac80211/patches/subsys/311-cfg80211-allow-concurrent-AP-operation-on-DFS-channe.patch"; blob = "02966fb7a77b47276b3283cb519cb0b9a00c6d96"; sha256 = "sha256-2U/S+Yzo9eWEOCXy2++PX1xtWLROBT6ICmVrdZsMGNM="; }
      { path = "package/kernel/mac80211/patches/subsys/320-mac80211-add-AQL-support-for-broadcast-packets.patch"; blob = "e3e654007cfcd6cd390a2d8a50226defc0950611"; sha256 = "sha256-qcRcpKae/3958cyoJhWrFxSir7Ke4Nhr6MlIYnq6RD0="; }
      { path = "package/kernel/mac80211/patches/subsys/321-wifi-mac80211-add-ieee80211_txq_aql_pending.patch"; blob = "f76cf085e7d503d78eee7e0c6a65f713b9d2d5eb"; sha256 = "sha256-2BLw+r4LBbNAA+6714GJn9aSZKU9zhxMkBP7LTFe6RU="; }
      { path = "package/kernel/mac80211/patches/subsys/360-mac80211-factor-out-part-of-ieee80211_calc_expected_.patch"; blob = "f3655b4404dcac5d7c284de2b9abccf8285d296f"; sha256 = "sha256-pjQDKakaJT0x1sXFckBEEcSEYfOEFYdMBhzzbjq/y9c="; }
      { path = "package/kernel/mac80211/patches/subsys/361-mac80211-estimate-expected-throughput-if-not-provide.patch"; blob = "953a35e164e7bfcaaef0cd61702ad967827ed03c"; sha256 = "sha256-+h0G1GVe6nQMubNxHzJodN+hRf8Qn69OatPglXD3/Ho="; }
      { path = "package/kernel/mac80211/patches/subsys/390-wifi-mac80211-notify-driver-on-airtime-weight-change.patch"; blob = "78d951d869d134ee7725d53d81ef8eb953973f4d"; sha256 = "sha256-wr3gtl4rzGJwqdyYZSf8mnQhf8fhtGQ15RHqYcLmIz8="; }
      { path = "package/kernel/mac80211/patches/subsys/391-wifi-mac80211-skip-default-WMM-setup-for-AP_VLAN-lin.patch"; blob = "7806a82381219a41b63008dd74e6d26b095e8c59"; sha256 = "sha256-W32FS4uTj8nKTPjT30CF18uK604tmkUgUXKvoK2NiHU="; }
      { path = "package/kernel/mac80211/patches/subsys/392-wifi-mac80211-fix-station-lookup-for-management-fram.patch"; blob = "3567ae34274a99f7b2b0764ab703024c45d986c4"; sha256 = "sha256-jTsLJBq48W0rLB0V/uYagvlrVSFo5fRrTCxGahQZqlk="; }
      { path = "package/kernel/mac80211/patches/subsys/600-mac80211-allow-vht-on-2g.patch"; blob = "9595e11c390cb4a274c1b4c2478b432df0409817"; sha256 = "sha256-7ZfHh+3+XOpVGR7t/IjdI4ptl2KZWBEfrU8VnE8Cuuk="; }
    ];

    # ath11k patches at the pin that the port does not apply.
    ath11k = [
      { path = "package/kernel/mac80211/patches/ath11k/900-ath11k-control-thermal-support-via-symbol.patch"; blob = "33b2885f94f75c84f9ef55abb633aadbb0a0bef8"; sha256 = "sha256-oon50HHGQvUWqdHcKPR1pVr0YvsbkzPXyIIeVchzzOg="; why = "backports-only plumbing: it rewrites thermal.h to IS_REACHABLE(CPTCFG_ATH11K_THERMAL). Applied to an in-tree CONFIG_ tree it collides with thermal.c."; }
      { path = "package/kernel/mac80211/patches/ath11k/905-ath11k-remove-intersection-support-for-regulatory-ru.patch"; blob = "40ba0a29654e7dad195b73f73dcc28453b5f6977"; sha256 = "sha256-wG3b2FTrXgSMVoD/sn028eixorqHiHonBWV5u6H29Is="; why = "Regulatory-rule intersection removal. It looks like the highest-value single delta (it changes which channel widths the driver advertises), but applying it on this tree made both radios fail at firmware-ready. Kept as the first candidate for a future A/B."; }
      { path = "package/kernel/mac80211/patches/ath11k/920-wifi-ath11k-add-hw-params-for-QCN6122.patch"; blob = "76ae6698a8db297ba931471a9acdb3c716d7a9ec"; sha256 = "sha256-oIeCO1jvJuSh6kI+vQuObL64gQPJrHpNoEbrwFhXvjI="; why = "QCN6122 (IPQ5018) support; this board has no QCN6122. Also changes ATH11K_QMI_CALDB_SIZE for every chip via qmi.h."; }
      { path = "package/kernel/mac80211/patches/ath11k/921-wifi-ath11k-add-hal-regs-for-QCN6122.patch"; blob = "b67bf811ecbdfb8343998579ce424bcd2c660e24"; sha256 = "sha256-SSAghWCFGYKAy4AMvojQY4bhh9ABh5kDSSYxYlNRV7w="; why = "QCN6122."; }
      { path = "package/kernel/mac80211/patches/ath11k/922-wifi-ath11k-add-hw-ring-mask-for-QCN6122.patch"; blob = "57ae8af613805454dbef4d6accd0191943281749"; sha256 = "sha256-8IbNOLJoYyljKIdDtBfTCEXWNPsEESaDDD30mNJ5X7w="; why = "QCN6122."; }
      { path = "package/kernel/mac80211/patches/ath11k/923-wifi-ath11k-update-hif_and-pci_ops-for-QCN6122.patch"; blob = "9ae50b9f3d15b84fe97990d875001e81e6d4e6ec"; sha256 = "sha256-XTMxQV8U9MFb7TyPKBXWUoUoUc8khMwAKgeMIqlcbOw="; why = "QCN6122 - but it is also what adds service_ins_id += userpd_id to pci.c, so it is a candidate if the QRTR instance ever needs revisiting."; }
      { path = "package/kernel/mac80211/patches/ath11k/924-wifi-ath11k-add-multipd-support-for-QCN6122.patch"; blob = "c545abc9781555c4353f07f8617bba049d8f2591"; sha256 = "sha256-ulzwP07GHFE156kO2ZF7XMHOwohNuyad3tdtTJcDqIw="; why = "QCN6122 multipd."; }
      { path = "package/kernel/mac80211/patches/ath11k/925-wifi-ath11k-add-QCN6122-device-support.patch"; blob = "06d7e9648455bfceb492b3075421d49221e9d790"; sha256 = "sha256-X8+oR68fiJT73ziBNop6fSntwNsDSjTLri7uHMKqDP8="; why = "QCN6122."; }
      { path = "package/kernel/mac80211/patches/ath11k/947-wifi-ath11k-fix-rssi-station-dump-for-IPQ5018-and-QC.patch"; blob = "1caac8620765281b52a879dda7dedb26dac4b568"; sha256 = "sha256-n1G9Uprq23FXEJjuNbYVSe2vLzuA32ALxtj1uOMROyI="; why = "IPQ5018/QCN6122 station dump only; this board is IPQ6010 + QCN9074."; }
    ];
  };

  # Reference only: two AHB CE-interrupt fixes that OpenWrt master carries
  # and immortalwrt at our pin does not. This port pins immortalwrt, so it
  # does not apply them; the local 960/961 cover the same failure on this
  # tree. If the pin ever moves to a ref that has them, drop the local pair
  # and move these into `ath11k`.
  kernelReference = {
    pin = openwrt;
    patches = [
      { path = "package/kernel/mac80211/patches/ath11k/950-wifi-ath11k-implement-CE-interrupt-enable-disable-for-AHB.patch"; blob = "61fc21fc9a4a833ca60699e1630308bdc54ec8a2"; sha256 = "sha256-WJq+FosIE9CETVdqF9Y9cq9GgJIxB2Ui8d2C/MK8K8g="; }
      { path = "package/kernel/mac80211/patches/ath11k/951-wifi-ath11k-disable-interrupts-during-firmware-crash-recovery.patch"; blob = "996ce9b5b00bf65ce43cd7264db5dff3aef7797c"; sha256 = "sha256-zTl1gUbRrrOR6MshMYFXizjiY+UQvX8FPshMaBwHz8A="; }
    ];
  };

  # ── Firmware and board data ──────────────────────────────────────────
  firmware = {
    # The QCN9074 board data file, matched by the device tree's
    # qcom,ath11k-calibration-variant = "JDC-RE-CS-02".
    qcn9074Board = {
      role = "fetched";
      repo = qcaWireless.repo;
      ref = qcaWireless.ref;
      path = "board-jdcloud_re-cs-02.qcn9074";
      blob = "618048550e670b0fbe7fe55ff82cddf20c3617b2";
      sha256 = "sha256-xdAGkAARrL1URNFg5ySFs74DfhNZ2t+MU24DjbcQBFU=";
      installedAs = "ath11k/QCN9074/hw1.0/board-2.bin";
      note = ''
        One packed ath11k board container whose single entry is keyed by the
        variant above. Byte-identical at the pinned commit and at the earlier
        f2c37a6b the ax6600 branch fetched, and byte-identical to the BDF on
        the working reference unit (md5 0e37c82b...).
      '';
    };

    # Driver firmware for the two radios. ImmortalWrt splits these between
    # two packages: ath11k-firmware-qcn9074 (which is the kernel.org
    # linux-firmware package) and ath11k-firmware-ipq6018 (CodeLinaro's
    # ath11k-firmware), with the IPQ6018 BDF coming from linux-firmware.
    qcn9074Firmware = {
      role = "nixpkgs";
      package = "linux-firmware";
      files = [
        "ath11k/QCN9074/hw1.0/amss.bin"
        "ath11k/QCN9074/hw1.0/m3.bin"
      ];
      upstreamPackage = "package/firmware/linux-firmware/qca_ath11k.mk";
      upstreamBlob = "a373cf5774abdde2312f8cf260b3e98c9aa87a2c";
      upstreamPin = {
        source = "https://cdn.kernel.org/pub/linux/kernel/firmware/linux-firmware-20260810.tar.xz";
        sha256 = "sha256-rBfDT+c3VpJqlh+6+t+NjwejvS3S9OoxoPtdUMcUpJo=";
        hashFrom = "package/firmware/linux-firmware/Makefile at the pin (PKG_VERSION 20260810, PKG_HASH ac17c34f...a49a), converted to SRI; the files themselves were not downloaded here.";
      };
      note = ''
        ImmortalWrt's ath11k-firmware-qcn9074 installs the kernel.org
        linux-firmware tree, version 20260810 at the pin (PKG_SOURCE_URL
        @KERNEL/linux/kernel/firmware). This port uses nixpkgs'
        linux-firmware instead of fetching that tarball: it is the same
        upstream project, already a build input of the kernel, and the
        QCN9074 files it carries are the ones this board's PCIe radio asks
        for. The upstreamPin above is recorded so the exact ImmortalWrt
        revision can be swapped in later (compute-verify the hash from the
        tarball before relying on it: it comes from upstream's Makefile,
        not from a download made here).

        Known alternative, and the only firmware with hardware evidence on
        this unit: VIKINGYFY's ath11k-firmware-ddwrt (commit 0c817c4656)
        QCN9074 WLAN.HK.2.15.0.1.r2 (amss sha256-EsYUWYqVTffOYuJJTP9nDamsM6wziXT2onjR8Q5cCkE=,
        m3 sha256-HiOMwMM4tHLLaEUmnBKSvmlr21k/4T8JG7SQfBsziCk=,
        board-2 sha256-PSVpnYwdfuob1rjy1+2ogDINC8Ht6NXIZRC3Bc3SWsw=). The
        ax6600 branch measured it clearly better than the older firmware
        under sustained 80 MHz load. It is not the reference's source, so it
        is not the default here.
      '';
    };

    ipq6018Firmware = {
      role = "fetched";
      repo = cloAth11k.repo;
      ref = cloAth11k.ref;
      basePath = "IPQ6018/hw1.0/2.5.0.1/WLAN.HK.2.5.0.1-03982-QCAHKSWPL_SILICONZ-3";
      installedInto = "IPQ6018";
      version = cloAth11k.version;
      files = [
        { name = "m3_fw.mdt"; blob = "f9edcc9fcef93c4534e1f77f4e978214669f5b7e"; sha256 = "sha256-vOhIbr8nytHC9/MTUxZ4VV1eiRp0CLGG78kG8PvT4+Q="; }
        { name = "m3_fw.b00"; blob = "b000539b79c8220d5563324a73cae0233d3b21e6"; sha256 = "sha256-K/awGmLNLIhYYjnn+CC8jNquNIBawC4iftwBZYgJA5A="; }
        { name = "m3_fw.b01"; blob = "567ad54c3a4983e17447e481d1cf051c2a357d79"; sha256 = "sha256-wI/BWHlpKrLLr2oGb85n+R68hHV+kNiAqiwObt1mdQU="; }
        { name = "m3_fw.b02"; blob = "e45c10de1ba957643d14a590450f47184367c589"; sha256 = "sha256-NPMTCcmdSpBo9OYy/fyD7r4hVEsb1tabhmf+ZhnVeIQ="; }
        { name = "q6_fw.mdt"; blob = "9eab89ecf93c56b750da090fdc882ba8579333e9"; sha256 = "sha256-U/A7c81Jj+11JOKdaOmTTiIeT/aMHM93OgNIU1NaEgc="; }
        { name = "q6_fw.b00"; blob = "8754aa5ac8607f36d49858046f1e4bf74365a164"; sha256 = "sha256-U9HVa2PbCxniE8bXacYhWKqquNyiMGHsBCMtjXmz/3A="; }
        { name = "q6_fw.b01"; blob = "55d8f39a18cffe932a5838a96a613682fc59d2aa"; sha256 = "sha256-qN7XpWLAaI2TG1DpcxSJrb0y9eKwPTgTWTeYFrA/BA4="; }
        { name = "q6_fw.b02"; blob = "1c2ff496315fae55ac528403f06b1d649e5ae676"; sha256 = "sha256-7mlCLz/axtLA86N+JjXVTCwbyDMV3V++pvBJl6E782Y="; }
        { name = "q6_fw.b03"; blob = "130370a71bdd7d4d671cd4c979f947bc3f0389d1"; sha256 = "sha256-7LTfL4DYNWLkCdwH/2+SItgt3eeFiRnl6dAsRaWmyeg="; }
        { name = "q6_fw.b04"; blob = "0852c3da1b673709511104c5527d7c4a0bebbb2f"; sha256 = "sha256-qf43xSioX/wDZi6M7zwPk9ZrnBURtyl+d88haEA440k="; }
        { name = "q6_fw.b05"; blob = "3353616d7a31d4f6674a3ba7d41f35b3d48243c7"; sha256 = "sha256-nag20tvGFX2C0OeH6TkgsqNWGMbfwQk8V3j5o9388oQ="; }
        { name = "q6_fw.b07"; blob = "a3e2f0b1b5b60a92ecdc6052f5c981257966798b"; sha256 = "sha256-Qn+xwmn06KBMt1hhmKwdkIQdjNMX3Nl/fuftQy4uALE="; }
        { name = "q6_fw.b08"; blob = "6953337fbc89e478668bfac0dced873e61ad6cda"; sha256 = "sha256-ZstUdbBp9eYe6KJakNpmbQsKzKCKIBcTeP65PPFVsfU="; }
      ];
      note = ''
        The q6v5_wcss driver asks for "IPQ6018/q6_fw.mdt" and
        "IPQ6018/m3_fw.mdt" (0136's driver data), so these are installed
        under /lib/firmware/IPQ6018/ with those names, exactly as
        ImmortalWrt's ath11k-firmware-ipq6018 package does.

        The CLO tree also carries Notice.txt and the two .flist files; the
        kernel's mdt loader does not read them, so they are not fetched.
      '';
    };

    ipq6018Board = {
      role = "nixpkgs";
      package = "linux-firmware";
      files = [ "ath11k/IPQ6018/hw1.0/board-2.bin" ];
      installedAs = "ath11k/IPQ6018/hw1.0/board-2.bin";
      note = ''
        The AHB radio's board data. ImmortalWrt's ath11k-firmware-ipq6018
        does not ship it; the driver requests it from the ath11k firmware
        directory and gets it from linux-firmware.
      '';
    };

    regulatory = {
      role = "nixpkgs";
      package = "wireless-regdb";
      installedAs = "regulatory.db";
      note = ''
        Same file modules/wlan.nix already puts in the image's filesystem
        tree. A full-system ram image boots before that tree is activated,
        so the wifi image embeds it in the initramfs as well.
      '';
    };

    # The per-unit pre-calibration data. Not a file we can fetch: it is a
    # slice of this board's own eMMC ART partition, so the service in
    # default.nix extracts it at boot. The offsets are the ones ImmortalWrt's
    # caldata hook uses for jdcloud,re-cs-02 - which is the data, and the
    # only thing here that is upstream's; the code that reads it is ours.
    caldata = {
      role = "derived";
      upstreamPath = "target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata";
      upstreamBlob = "1d002b15becbfd0d17a0819b3646647740abe21e";
      upstreamBoard = "jdcloud,re-cs-02";
      # The helpers that define what the call above means: find_mmc_part()
      # matches the string "0:ART" against a partition's PARTNAME, and
      # caldata_dd() reads `count` bytes at byte offset `offset` from that
      # partition's device node. The port's service reproduces both.
      upstreamHelpers = [
        { path = "package/base-files/files/lib/functions.sh"; blob = "8adf1b8fb2c0022cd76041c195c5663c4a451a73"; }
        { path = "package/base-files/files/lib/functions/caldata.sh"; blob = "f0fc907aeff1a204c0fa62396aaee1ad785f2ce4"; }
      ];
      entries = [
        {
          firmware = "ath11k/QCN9074/hw1.0/cal-pci-0000:01:00.0.bin";
          source = "0:ART";
          offset = "0x26800";
          size = "0x20000";
          upstream = ''caldata_extract_mmc "0:ART" 0x26800 0x20000'';
          note = "PCIe QCN9074 5 GHz radio. ath11k derives the name from the bus address; if the board's PCIe address ever changes, dmesg says which name it wanted.";
        }
        {
          firmware = "ath11k/IPQ6018/hw1.0/cal-ahb-c000000.wifi.bin";
          source = "0:ART";
          offset = "0x1000";
          size = "0x10000";
          upstream = ''caldata_extract_mmc "0:ART" 0x1000 0x10000'';
          note = "AHB IPQ6018 radio, platform device c000000.wifi.";
        }
      ];
      note = ''
        ImmortalWrt reads ART from the eMMC (caldata_extract_mmc): on this
        board 0:ART is a GPT partition, not an mtd, and "0:ART" is its
        literal GPT name - find_mmc_part() matches that string against
        PARTNAME exactly, and the dd it then does is byte-relative to the
        partition device. There is no MAC patching and no regdomain removal in
        the jdcloud,re-cs-02 branch of the hook, so extraction is the whole of
        it. The upstream shell around that call assumes OpenWrt's
        /lib/functions/caldata.sh and procd hotplug, so the port reimplements
        it as a service (ax6600-wifi.nix, services.firmware-ath11k): mount a
        tmpfs over /lib/firmware, copy the static firmware in, find the
        partition whose PARTNAME is 0:ART (or ART), and dd the two slices
        below out of it. Nothing is baked into the image - the calibration
        stays on the device, which is what the partition is for.
      '';
    };
  };

  # ── Kernel configuration ─────────────────────────────────────────────
  #
  # Where each symbol's requirement comes from, so the config can be
  # re-derived rather than inherited:
  #   - QCOM_Q6V5_WCSS / QCOM_SMEM / QCOM_SMP2P / QCOM_APCS_IPC / MAILBOX /
  #     HWSPINLOCK(_QCOM) / RPMSG_QCOM_GLINK(_SMEM) / QCOM_SCM /
  #     QCOM_MDT_LOADER / REMOTEPROC: target/linux/qualcommax/config-6.18
  #     (blob cf51b111f363735c30c0e8eb4b94b2990f356b6d).
  #   - QRTR_SMD / QRTR_MHI: kmod-ath11k-ahb and kmod-ath11k-pci depend on
  #     kmod-qrtr-smd / kmod-qrtr-mhi (package/kernel/mac80211/ath.mk, blob
  #     a6f2719a10ab4cce81bbb6efbdc0144cf426fe89), which set those symbols
  #     plus CONFIG_QRTR.
  #   - PCI/PCIE_QCOM/PHY_QCOM_QMP(_PCIE): the QCN9074 is on PCIe0.
  #   - ATH11K*: ImmortalWrt builds them as kmods (kmod-ath11k,
  #     kmod-ath11k-ahb, kmod-ath11k-pci); the module form is `wlan` below
  #     and the wifi image turns it into the built-in form, because a
  #     full-system ram image cannot load modules.
  kconfig = {
    # Infrastructure, built in either way. QCOM_Q6V5_WCSS must be =y for the
    # same reason it is =y in ImmortalWrt's config: ath11k_ahb's qcom,rproc
    # phandle has to resolve before ath11k_ahb probes.
    infra = {
      REMOTEPROC = "y";
      QCOM_SCM = "y";
      QCOM_MDT_LOADER = "y";
      QCOM_Q6V5_COMMON = "y";
      QCOM_Q6V5_WCSS = "y";
      QCOM_SMEM = "y";
      QCOM_SMP2P = "y";
      QCOM_APCS_IPC = "y";
      MAILBOX = "y";
      HWSPINLOCK = "y";
      HWSPINLOCK_QCOM = "y";
      RPMSG = "y";
      RPMSG_QCOM_GLINK = "y";
      RPMSG_QCOM_GLINK_SMEM = "y";
      QRTR = "y";
      QRTR_SMD = "y";
      QRTR_MHI = "y";
      PCI = "y";
      PCIE_QCOM = "y";
      PHY_QCOM_QMP = "y";
      PHY_QCOM_QMP_PCIE = "y";
    };
    # The wireless stack itself, as modules (what modules/wlan.nix plus this
    # block produce when the device's conditionalConfig is in play).
    wlan = {
      WLAN_VENDOR_ATH = "y";
      ATH_COMMON = "m";
      ATH11K = "m";
      ATH11K_AHB = "m";
      ATH11K_PCI = "m";
    };
  };

  # ── Reference material (checked, not fetched) ────────────────────────
  #
  # The pieces of ImmortalWrt's handling that are data rather than bytes we
  # install: recorded so the port can be audited against its source.
  reference = {
    board = {
      repo = "https://github.com/immortalwrt/immortalwrt";
      ref = pin.ref;
      deviceDefinition = {
        path = "target/linux/qualcommax/image/ipq60xx.mk";
        blob = "964fca411c72160f67fd99d5115100696399da2d";
        device = "Device/jdcloud_re-cs-02";
        packages = "ath11k-firmware-qcn9074 ipq-wifi-jdcloud_re-cs-02 kmod-ath11k-pci";
      };
      defaultPackages = {
        path = "target/linux/qualcommax/ipq60xx/target.mk";
        blob = "06a85ab5e4fbbcc4bc318f5555ae81b20e88e899";
        adds = "ath11k-firmware-ipq6018 (plus kmod-ath11k-ahb from the target's DEFAULT_PACKAGES)";
      };
      targetDefaults = {
        path = "target/linux/qualcommax/Makefile";
        blob = "8ffa7397c3b2d551a032b2e42ae5f265d2b5de76";
        note = "kmod-ath11k-ahb and wpad-openssl are target defaults, so the onboard AHB radio is enabled for this board even though DEVICE_PACKAGES does not name it.";
      };
      kernelConfig = {
        path = "target/linux/qualcommax/config-6.18";
        blob = "cf51b111f363735c30c0e8eb4b94b2990f356b6d";
      };
      firmwarePackages = [
        { path = "package/firmware/ath11k-firmware/Makefile"; blob = "18d7bac08154fc0241ead96ff72686aa63cdc7a2"; note = "ath11k-firmware-ipq6018: CLO ath11k-firmware, IPQ6018/hw1.0/2.5.0.1/WLAN.HK.2.5.0.1-03982-QCAHKSWPL_SILICONZ-3/* installed into /lib/firmware/IPQ6018/."; }
        { path = "package/firmware/linux-firmware/qca_ath11k.mk"; blob = "a373cf5774abdde2312f8cf260b3e98c9aa87a2c"; note = "ath11k-firmware-qcn9074: linux-firmware's ath11k/QCN9074/hw1.0/*."; }
        { path = "package/firmware/ipq-wifi/Makefile"; blob = "04f649935392f5d9dad318c5cccbc82d5b202a40"; note = "ipq-wifi-jdcloud_re-cs-02, from firmware_qca-wireless at 0c67bbcc."; }
      ];
      # How the calibration is obtained at runtime: not by a file the image
      # ships, but by procd running a hotplug script when the driver asks for
      # a file that is not there. The four upstream pieces of that chain,
      # recorded because the port reproduces its *effect*, not its mechanism
      # (Liminix has no procd and no firmware user-helper fallback).
      firmwareHotplug = {
        kernelConfig = {
          path = "target/linux/generic/config-6.18";
          blob = "cf51b111f363735c30c0e8eb4b94b2990f356b6d";
          symbols = [
            "CONFIG_FW_LOADER_USER_HELPER=y"
            "CONFIG_FW_LOADER_USER_HELPER_FALLBACK=y"
            "CONFIG_UEVENT_HELPER=y"
            "CONFIG_UEVENT_HELPER_PATH=\"/sbin/hotplug\""
          ];
          note = "The direct /lib/firmware lookup fails first; the fallback then asks userspace for the file.";
        };
        procdRule = {
          path = "package/system/procd/files/hotplug.json";
          blob = "9fecddae6be1f088e6ec5e7ab68a1d186cf5251c";
          rule = ''[ "if", [ "has", "FIRMWARE" ], [ [ "exec", "/sbin/hotplug-call", "%SUBSYSTEM%" ], [ "load-firmware", "/lib/firmware" ], [ "return" ] ] ]'';
          note = "Runs every /etc/hotplug.d/firmware/* script, then hands the file the script just wrote back to the request_firmware() that is still waiting.";
        };
        dispatcher = {
          path = "package/base-files/files/sbin/hotplug-call";
          blob = "f595b9e75fa958ca6ade484134e625050bd8c7d5";
          note = "Sets HOTPLUG_TYPE and sources /etc/hotplug.d/\$HOTPLUG_TYPE/*.";
        };
        hook = {
          path = "target/linux/qualcommax/ipq60xx/base-files/etc/hotplug.d/firmware/11-ath11k-caldata";
          blob = "1d002b15becbfd0d17a0819b3646647740abe21e";
        };
      };
    };
    # The other tree this port was measured against: VIKINGYFY's immortalwrt
    # fork, at the revision the working reference unit runs. Same calibration
    # mechanism (its procd rule and its caldata entries for jdcloud,re-cs-02
    # are byte-for-byte the same as upstream's), but it fork-replaced both
    # ath11k firmware packages with its own repository, which is where the
    # QCN9074 2.15.0.1.r2 firmware comes from.
    vikingFork = {
      repo = "https://github.com/VIKINGYFY/immortalwrt";
      ref = "90448eeb2b8f5d172caedfe6d96ab3bacb058c09";
      sameCaldataAsUpstream = true;
      devicePackages = "ipq-wifi-jdcloud_re-cs-02 ath11k-firmware-qcn9074-ddwrt luci-app-athena-led luci-i18n-athena-led-zh-cn";
      targetDefaults = "kmod-ath11k kmod-ath11k-ahb kmod-ath11k-pci ... plus ath11k-firmware-ipq6018-ddwrt in the ipq60xx target.mk";
      firmwarePackage = {
        path = "package/firmware/ath11k-firmware/Makefile";
        repo = "https://github.com/VIKINGYFY/ath11k-firmware-ddwrt";
        ref = "0c817c46568ef6871042c7e2efc95ac24a1f02e6";
        date = "2026-08-21";
        installs = [
          "Package/ath11k-firmware-qcn9074-ddwrt: QCN9074/hw1.0/* -> /lib/firmware/ath11k/QCN9074/hw1.0/"
          "Package/ath11k-firmware-ipq6018-ddwrt: IPQ6018/hw1.0/* -> /lib/firmware/IPQ6018/"
        ];
        contents = [
          "QCN9074/hw1.0/amss.bin 4128520 bytes, m3.bin 340108, board-2.bin 811180, regdb.bin, fw_version.txt"
          "IPQ6018/hw1.0/q6_fw.* + m3_fw.* + board-2.bin 787208 + regdb.bin + fw_version.txt"
        ];
        note = ''
          The QCN9074 amss.bin here is the 2.15.0.1.r2 image the ax6600 log
          identified as the reference's, and it is 4 128 520 bytes (the
          linux-firmware one this port ships by default is 4 227 408) - so the
          two are different builds, not just different pins.

          Two things worth knowing if the fork is ever taken as the source
          instead of upstream immortalwrt: its QCN9074 board-2.bin (811 180
          bytes, the generic one) is installed to the same path as
          ipq-wifi-jdcloud_re-cs-02's board-specific file (131 176 bytes), and
          its IPQ6018 board-2.bin lands in /lib/firmware/IPQ6018/ whereas
          ath11k asks for ath11k/IPQ6018/hw1.0/board-2.bin (hw.dir is
          "IPQ6018/hw1.0", core.c). This port places each file where the
          driver looks.
        '';
      };
    };
  };
}
