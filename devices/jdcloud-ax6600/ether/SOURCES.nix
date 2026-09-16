# The ethernet port's own manifest: which upstream files it installs into the
# kernel tree, which upstream patches it applies and in what order, the one
# local patch that is left, and how this port compares to openwrt.
#
# This is not a second ledger. ../SOURCES.nix is still the single place
# that answers "what does this device take from upstream": it holds the ref,
# and it calls this file with it. Move the ref there and everything here
# follows. `files` and `patches` are read by default.nix's extraPatchPhase,
# which builds each URL as <pin.rawBase>/<path> - so every `path` below is
# relative to the upstream repository root, not to this directory.
#
# Keeping it here rather than in ../SOURCES.nix is only about cohesion:
# these are the port's inputs, and the port's other two files (fixups.patch,
# README) are already in this directory.

pin: {
  # ── The ethernet port: ESS/PPE/EDMA/UNIPHY ───────────────────────────
  #
  # Same rule as the device tree: upstream's bytes are not committed here.
  # This replaces ether/src (ten files copied into the kernel tree) and
  # ether/patches (nineteen patches applied in a hard-coded order); the only
  # local file the port still owns is ether/fixups.patch.
  #
  #   files   - installed into the kernel tree, keeping the part of each
  #             path below target/linux/qualcommax/files/. Every one of them
  #             is an addition to 6.18.49; none overwrites a mainline file.
  #             The first entry, ipq6018-ess.dtsi, is the one the board dtsi
  #             in ../SOURCES.nix includes: it provides &switch, &edma, the UNIPHY
  #             PCS nodes, so the device tree build depends on this list too.
  #
  #   patches - applied one at a time, in the order written here, by the
  #             extraPatchPhase in default.nix. That order is load-bearing:
  #             phylink refactors (703-*), the fwnode-PCS framework
  #             (737-01..07), the clocks (0080/0082/0191/0920/0904/0917),
  #             then the drivers themselves (0950..0953). Reordering this
  #             list reorders the build.
  #
  # 737-02 and 0950 do not apply cleanly to plain 6.18.49 - their context
  # assumes OpenWrt's cumulative net tree - so 0950's added lines are
  # re-anchored by the local ether/fixups.patch (see the `fixups` entry
  # below), applied after this list. 737-02's failed hunk is deliberately not
  # supplied. The sentinel greps at the end of the patch phase prove the rest
  # landed.
  #
  # Refreshing: edit the ref in ../SOURCES.nix, rebuild, and take the two hash values out
  # of fetchurl's error message. The blob column is the identity check, and
  # it is worth re-reading: these same file names exist in the VIKINGYFY
  # forks with a completely different stack behind them.
  files = [
    { path = "target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-ess.dtsi";
      blob = "0de37caf7da1c68224b8f8a2b63141e8f4fd9919";
      sha256 = "sha256-RYyGI0bMXbuytQjU79Avhbr/Lo7bfio0U0CKrEBjIUY="; }
    { path = "target/linux/qualcommax/files/drivers/net/ethernet/qualcomm/qca_edma.c";
      blob = "cca6a9e03c9ef92b9d2f450ddfeedc9c680eeb09";
      sha256 = "sha256-hflJ+3U/GoAb8yVmJNWlphtatJRLjDU+5Bo8mXUGJ/k="; }
    { path = "target/linux/qualcommax/files/drivers/net/ethernet/qualcomm/qca_edma.h";
      blob = "6ee508fd5fbe3cdee7686d7c125e0943f9e8e429";
      sha256 = "sha256-R6Y2/aMQP20Gi8KAxd0S63XyZAirLelKv/NThnwhYOM="; }
    { path = "target/linux/qualcommax/files/drivers/net/ethernet/qualcomm/qca_ppe.h";
      blob = "bc31b61486c75c7b3c626b9ef100aec196203d24";
      sha256 = "sha256-KGgY94QLimEmGF7kd9asTklFbP7b4RDmHfNKn/yW/3I="; }
    { path = "target/linux/qualcommax/files/drivers/net/ethernet/qualcomm/qca_ppe_main.c";
      blob = "1613335f07695902679733b9e9b52cff45ebe50a";
      sha256 = "sha256-gfbJFE3TZsOZCJ/J7eRJzZgGax99DDRfevPCDPB0lkE="; }
    { path = "target/linux/qualcommax/files/drivers/net/ethernet/qualcomm/qca_ppe_scheduler.c";
      blob = "00a1c1ae806a1d9d9f32cb68d82dc4553ad6be2d";
      sha256 = "sha256-S7fPCGd7VPB4Ut27m/Zr9pLXhQWO5ga5KQ/AQ3jmPL4="; }
    { path = "target/linux/qualcommax/files/drivers/net/ethernet/qualcomm/qca_ppe_vlan.c";
      blob = "5e003afa0721ab7a08a521b463d3c4f4592900c5";
      sha256 = "sha256-Qq4HmyAEgXWv7CEn6EOW01RqW7aEBYm+h3/0byZuE70="; }
    { path = "target/linux/qualcommax/files/drivers/net/pcs/pcs-qca-uniphy.c";
      blob = "27f6189a33016718ea3ffd7cdfb2a237cefef731";
      sha256 = "sha256-weWVzl+49ideueodQjM26NusdFo27lZ03LfuzoKnjp8="; }
    { path = "target/linux/qualcommax/files/include/dt-bindings/net/qca-uniphy.h";
      blob = "021cd057b043de17ac54b65584d6401a9b89fb36";
      sha256 = "sha256-Ehu53mbWQHY0rKrTXTq/Ci6IkvabhsZC98krHsNe9Dw="; }
    { path = "target/linux/qualcommax/files/include/linux/pcs/pcs-qca-uniphy.h";
      blob = "8611763ac518b154fedec8eff4eda37a451cc02d";
      sha256 = "sha256-zwheBgifVVKawEQDWLP5XoVpamNHF73NIXlDqcht5oY="; }
  ];
  patches = [
    { path = "target/linux/generic/backport-6.18/703-01-v7.0-net-phylink-simplify-phylink_resolve-phylink_major_c.patch";
      blob = "d1cd6f1712a7e1bd9b0f740cb9d5d1240f8d1dfc";
      sha256 = "sha256-oDvLF9qt86yhaotm7YWKCoxwmyXTu5OCaOL5mnYP/FE="; }
    { path = "target/linux/generic/backport-6.18/703-02-v7.0-net-phylink-introduce-helpers-for-replaying-link-cal.patch";
      blob = "a87b10108519a2f710ba48e2553da029b8917cfe";
      sha256 = "sha256-aY+ElxHzWC9UL8G9J5FetkalktAkk2DiZaDBCQAV/9I="; }
    { path = "target/linux/generic/pending-6.18/737-01-net-phylink-keep-and-use-MAC-supported_interfaces-in.patch";
      blob = "fb96432fe55f26599506cc6ae21bf9dab51a7f51";
      sha256 = "sha256-aVsNvR6kPdz/DOt3w2Fgd/CKwyPx5odiTh0Rtbm9ThI="; }
    { path = "target/linux/generic/pending-6.18/737-02-net-phylink-introduce-internal-phylink-PCS-handling.patch";
      blob = "e5dd84332617b5f7eeb69184e394b902570c4dfb";
      sha256 = "sha256-lYU9kZdWfYfCLm6KCvFnFrkFr0QbU01D3a5LFeqSnWk="; }
    { path = "target/linux/generic/pending-6.18/737-03-net-phylink-add-phylink_release_pcs-to-externally-re.patch";
      blob = "5e35f5fece0abf52966511a7dcbb26ba3f5b7b4e";
      sha256 = "sha256-WQjiKn+QUI0fnuhWVIPCJMi2N89G0eFhayjDFPS7cuA="; }
    { path = "target/linux/generic/pending-6.18/737-04-net-pcs-implement-Firmware-node-support-for-PCS-driv.patch";
      blob = "676e23c00194500ad83aab1492dd7e26bc7163dd";
      sha256 = "sha256-H6oGMOXMvVENStlZovtQGwopgs2nTgSxoqzbD6Sd9LI="; }
    { path = "target/linux/generic/pending-6.18/737-05-net-phylink-support-late-PCS-provider-attach.patch";
      blob = "800b8b12113ee01c6c94a5be1287f5918f3c798a";
      sha256 = "sha256-YKapkWemxyjp0rE8A673lA0Y3l+PoO3znwlfKn9jje0="; }
    { path = "target/linux/generic/pending-6.18/737-06-dt-bindings-net-ethernet-controller-permit-to-define.patch";
      blob = "ac4154b857932cf380cb6c187b57a3f4263b5071";
      sha256 = "sha256-fAMRKR2w0jYo/BPuw8xXC8i4Ust3k+kpglol08zBOf0="; }
    { path = "target/linux/generic/pending-6.18/737-07-net-phylink-add-.pcs_link_down-PCS-OP.patch";
      blob = "589635f731c60fb9226ed266882c5172fcd62503";
      sha256 = "sha256-ySRow2ee6Zi0v8k1O6cgtAbJM6VHEsh5VmYu7Oi6Yhg="; }
    { path = "target/linux/qualcommax/patches-6.18/0080-v7.1-dt-bindings-clock-qcom-Add-CMN-PLL-support-for-IPQ6018.patch";
      blob = "0ab8bec21e253e012bd65beaf543d6ee3e68f69b";
      sha256 = "sha256-4bbD0zcxFfJwixaX1hMbrZgBKkLZJ+C8wqC39FFVy/k="; }
    { path = "target/linux/qualcommax/patches-6.18/0082-v7.1-clk-qcom-ipq-cmn-pll-Add-IPQ6018-SoC-support.patch";
      blob = "6b10a62d73232f0139c8afa16e5aef29285226f0";
      sha256 = "sha256-xfht78/LPu0i583hIWa5fP7aGjQj9H8GAm4FUqJRtZg="; }
    { path = "target/linux/qualcommax/patches-6.18/0191-clk-qcom-ipq-cmn-pll-keep-the-CMN-block-bus-clocks-enabled.patch";
      blob = "7bc9311ca5bacf5a19a212c1935128f45a413505";
      sha256 = "sha256-zlfxoXpM4hhg39NY34P1WP3QpVW4UBazu5ePiu6BeMU="; }
    { path = "target/linux/qualcommax/patches-6.18/0920-clk-add-clk_hw_recalc_rate-to-trigger-HW-clk-rate-re.patch";
      blob = "c9d58702830041757a55069af8c67ab2ff6f2e2c";
      sha256 = "sha256-+C+6CDlwvxnThL0xTJ/WWP7KjOjptBWTyEOhYq1axug="; }
    { path = "target/linux/qualcommax/patches-6.18/0904-clk-qcom-ipq6018-workaround-networking-clock-parenti.patch";
      blob = "30c6eced96c05b8bb55bf98c49c886acf2993ee1";
      sha256 = "sha256-8sUh12jv8cg/WYuFuJnu29tlSRQzqOvQcf7HOU2cSpQ="; }
    { path = "target/linux/qualcommax/patches-6.18/0917-clk-qcom-gcc-ipq6018-mark-gcc_xo_clk_src-as-critical.patch";
      blob = "1844803aa000aa51cf19c0aa4875a709f324ef9c";
      sha256 = "sha256-ECNjJj3N+Tu96lxxo5aDVRpsx+vBUMIvnX+aZYxwEy4="; }
    { path = "target/linux/qualcommax/patches-6.18/0950-net-dsa-add-out-of-band-tagging-protocol.patch";
      blob = "595f5a55e6093f08a0ff429787653c2ccd4f4cff";
      sha256 = "sha256-SWRZf6Ezn8Pe9VadrbY0pAT/VGaNDOaeWMHQ8mPAzgo="; }
    { path = "target/linux/qualcommax/patches-6.18/0951-net-pcs-add-uniphy-pcs.patch";
      blob = "479e2d4ad050eb05984a149be712fac9f13d417d";
      sha256 = "sha256-WHuZNFwNGKLIFQ8Hp+3c5w84comB0U1yuDx1LBDnQHc="; }
    { path = "target/linux/qualcommax/patches-6.18/0952-net-ethernet-qca-add-ppe.patch";
      blob = "2ecfac6bdd5c53e9203d5ff36dea5a0976586541";
      sha256 = "sha256-qQBt3QGQFidq69W7HF8XoBT+Ils6LR2x30W2wTCCaSk="; }
    { path = "target/linux/qualcommax/patches-6.18/0953-net-ethernet-qca-add-EDMA.patch";
      blob = "a77f367cac4619b0a111a73ddf7e7f1f18be7fac";
      sha256 = "sha256-xwBz8lGrH6KbyCneOKGIB5TOuT9IKCQRelDf4IZeqeU="; }
  ];


  # The one local file this port still owns, and where it comes from. It is
  # local because it cannot be a reference: upstream's 0950 anchors its
  # include/net/dsa.h hunk on DSA_TAG_PROTO_MXL862_8021Q_VALUE, which
  # mainline 6.18.49 does not have, so no revision of that patch applies
  # here as fetched. The lines it adds are upstream's, the anchors are ours -
  # and an anchor is not something a URL can supply.
  fixups = {
    role = "local";
    treePath = "devices/jdcloud-ax6600/ether/fixups.patch";
    derivedFrom = [
      {
        path = "target/linux/qualcommax/patches-6.18/0950-net-dsa-add-out-of-band-tagging-protocol.patch";
        blob = "595f5a55e6093f08a0ff429787653c2ccd4f4cff";
      }
    ];
    note = ''
      Three of its four hunks are that patch's added lines, re-anchored:
      DSA_TAG_PROTO_OOB_VALUE 32 and the enum member into include/net/dsa.h,
      and the linux/dsa/oob.h include into net/core/skbuff.c (whose sibling
      hunk, SKB_EXT_DSA_OOB, does apply and needs the struct). The fourth is
      ours: QCOM_EDMA selects PAGE_POOL, which qca_edma.c needs and which
      cannot be set from the kernel config at all - PAGE_POOL is declared
      "bool" with no prompt, and kconfig ignores .config for promptless
      symbols, so "select" is the only lever.

      If a future revision of 0950 anchors somewhere 6.18.49 has, the first
      three hunks go away and that patch can be applied as fetched. Nothing
      here can be re-fetched or compared against a URL, so what there is to
      watch is upstream: once the anchors it chose are in mainline, this file
      can be deleted.
    '';
  };

  # Where the same driver sits in the origin of this stack. Checked, not
  # fetched, and NOT interchangeable with the pin in ../SOURCES.nix.
  openwrtMaster = {
    role = "reference-only";
    repo = "https://github.com/openwrt/openwrt";
    ref = "d60def64a187bee1de6e2bb711b2619e4a7fbeca";
    note = ''
      Checked 2026-09-14. openwrt master has moved on from the revision
      immortalwrt@8d9475a carries, and by more than drift:

        qca_edma.c        ours 1418 lines   openwrt 1829
        qca_ppe_main.c    ours 1914         openwrt 2025
        pcs-qca-uniphy.c  ours 1085         openwrt 1120

      plus qca_edma.h, qca_ppe.h, qca_ppe_scheduler.c, qca_ppe_vlan.c and
      pcs-qca-uniphy.h. Only ipq6018-ess.dtsi and qca-uniphy.h are still
      identical. So "immortalwrt and openwrt are the same source" is no
      longer true for this driver: we pin immortalwrt, and moving to openwrt
      would be a driver upgrade to bring up on hardware, not a ref change.

      It also shows why these entries are identified by blob sha and not by
      file name. In the revision we pin, 737-04-net-pcs-implement-Firmware-
      node-... is the fwnode-PCS framework. On openwrt master that patch is
      now 737-03-...; 737-04 is a different patch ("save phylink instance
      fwnode"), 737-05 is "support PCS provider release", and the series has
      grown to 737-10. Same content, different numbers.

      Still true at the same check: include/linux/pcs/pcs-provider.h is in
      none of torvalds/linux master, v6.19 or v7.0, so the fwnode-PCS
      framework is still ours to carry and this port cannot be deleted yet.
      What to watch is that file, not the patch file names.
    '';
  };
}
