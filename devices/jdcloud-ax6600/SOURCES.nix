# Every non-local input of this device. Nothing is committed here: the build
# fetches each entry from the pin below, so the sha256 values are the proof of
# which revision we are on.
#
# The pin is VIKINGYFY/immortalwrt `main`, the NSS generation: 6.18,
# Qualcomm-only, qca-nss-drv/ecm/dp/ssdk, ess-switch-ipq60xx and qcom,nss-dp.
# The fork's other refs and immortalwrt official are PPE generations - same
# paths, different content, different drivers. Never mix them (see
# ppeGeneration).
#
# role: fetched = used as a source file; build-input = installed into the
# kernel tree; reference-only = not used by the build.
#
# Identify an input by blob sha, never by file name; pin by full commit sha,
# never by branch name.
#
# Refreshing: edit the ref, rebuild, take the new sha256 from fetchurl's error.
# Flat hash: nix-hash --flat --type sha256 --sri <file>
let
  vikingyfy = {
    repo = "https://github.com/VIKINGYFY/immortalwrt";
    ref = "683480add1822fdfbbdee77856753d7282d58b71";
    rawBase = "https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/683480add1822fdfbbdee77856753d7282d58b71";
  };
in
{
  upstream = vikingyfy;

  boardDts = {
    role = "fetched";
    path = "target/linux/qualcommax/dts/ipq6010-re-cs-02.dts";
    blob = "bef591b4ef6c421f28a0f0d3aa67817ac7a14799";
    sha256 = "sha256-Y9FlDwOnlwDmxOrIHWofs+N2tqvXykAHBy0//2RWjsg=";
    license = "GPL-2.0-or-later OR MIT";
    note = ''
      ethernet0..4 = &dp1..&dp5 (qca-nss-dp), with switch_lan_bmp/switch_wan_bmp
      and qcom,port_phyinfo for qca-ssdk. Its wifi@0,0 and the dtsi's &wifi
      both carry qcom,ath11k-fw-memory-mode = <1>, which patch 903 in
      wireless/SOURCES.nix makes live; overrides.dtsi does not touch it
      (phase 2 may set the PCI node to 2, see BRINGUP N5 phase 2).
    '';
  };

  boardDtsi = {
    role = "fetched";
    path = "target/linux/qualcommax/dts/ipq6010-re-cs.dtsi";
    blob = "47b87bc05bcbc9e718d99b734b2241473745db90";
    sha256 = "sha256-qP6cc7ghU/80VqiFIh6H0bAqTWX6uwK1iMas8qUnBAI=";
    license = "GPL-2.0-or-later OR MIT";
    note = ''
      Includes ipq6018.dtsi from the kernel tree plus the three dtsi files
      below, so all four must be on the include path. Enables the Bluetooth
      port this board lacks (&blsp1_uart6 on gpio48/49); overrides.dtsi keeps
      it off.
    '';
  };

  essDtsi = {
    role = "build-input";
    path = "target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-ess.dtsi";
    blob = "b54f53f29ce147769d4c2f042fa494c208e74473";
    sha256 = "sha256-bXEhoiC1TObyyln+vQSSqdG4nFSbCds1nQZdjmzozE8=";
    note = "&switch, the ess-uniphy PCS nodes, edma@3ab00000; needs essHeader.";
  };

  # nss@40000000 takes memory-region = <&nss_region>, which patch 0103 adds.
  nssDtsi = {
    role = "build-input";
    path = "target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-nss.dtsi";
    blob = "280a08ba839c21fcde7605f888b918442a257b22";
    sha256 = "sha256-ZFv8urbisIJVBXaysuoPdsI/z2+tb5wOd28YwaT8PDA=";
    license = "GPL-2.0-only";
  };

  # mdio_pins, gpio-reserved-ranges <20 1>, serial_3_pins and &blsp1_uart3 -
  # what the PPE pins kept in their board dtsi. The board dtsi references
  # mdio_pins, so this file is required.
  commonDtsi = {
    role = "build-input";
    path = "target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-common.dtsi";
    blob = "18084f755f9dfac79743861936f0d8a1f6a2e57d";
    sha256 = "sha256-R6oobQUtuw4jvB1qIug7JPSu9JgTLJac2H4D5IVyj+U=";
    license = "GPL-2.0-or-later OR MIT";
  };

  essHeader = {
    role = "build-input";
    path = "target/linux/qualcommax/files/include/dt-bindings/net/qcom-ipq-ess.h";
    blob = "baa7c8956480292d370c2cb7862248177fd33daa";
    sha256 = "sha256-YDgr2GIu9hTtD+ssPaKbUmh9QhB2KQ889troDDdO/F4=";
    license = "GPL-2.0";
    note = "ESS_PORT*/MAC_MODE_* constants used by essDtsi and the board dtsi.";
  };

  # NB: 6.18.52's ipq6018.dtsi carries the qcom,ipq6018-wcss-pil remoteproc
  # node but not the AHB radio's wifi@c000000 node - no ipq6018 dts file in
  # the tarball contains the string "wifi" at all. The board dts' &wifi
  # override needs that label and ath11k matches on its compatible, so the
  # fork's 0906 (wireless/SOURCES.nix, applied after 0905, whose sec-pil
  # compatible is 0906's trailing context) is still required.

  # Applied in this order by the patch phase. The six clock patches are
  # upstream's - identical blob shas in both trees - not the fork's.
  kernelPatches = [    {
      path = "target/linux/qualcommax/patches-6.18/0080-v7.1-dt-bindings-clock-qcom-Add-CMN-PLL-support-for-IPQ6018.patch";
      blob = "0ab8bec21e253e012bd65beaf543d6ee3e68f69b";
      sha256 = "sha256-4bbD0zcxFfJwixaX1hMbrZgBKkLZJ+C8wqC39FFVy/k=";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0082-v7.1-clk-qcom-ipq-cmn-pll-Add-IPQ6018-SoC-support.patch";
      blob = "6b10a62d73232f0139c8afa16e5aef29285226f0";
      sha256 = "sha256-xfht78/LPu0i583hIWa5fP7aGjQj9H8GAm4FUqJRtZg=";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0103-arm64-dts-ipq6018-add-reserved-memory-nodes.patch";
      verify = [
        { kind = "grep"; file = "arch/arm64/boot/dts/qcom/ipq6018.dtsi";
          needle = "nss_region: nss@"; label = "0103: nss_region for ipq6018-nss.dtsi"; }
        { kind = "grep"; file = "arch/arm64/boot/dts/qcom/ipq6018.dtsi";
          needle = "ramoops_region: ramoops@"; label = "0103: ramoops label pstore-pmsg.dtsi extends"; }
      ];
      blob = "8a7ef0da7d8519826d0192b0b2d4c116a4b37524";
      sha256 = "sha256-VkG0vzD8AfvQ46flpS03g/qUq6/a1G7ZZ2XADaCl8J4=";
      note = "Adds nss_region and q6_etr/m3_dump/ramoops; the AHB radio reads the same reserved-memory block.";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0191-clk-qcom-ipq-cmn-pll-keep-the-CMN-block-bus-clocks-enabled.patch";
      blob = "7bc9311ca5bacf5a19a212c1935128f45a413505";
      sha256 = "sha256-zlfxoXpM4hhg39NY34P1WP3QpVW4UBazu5ePiu6BeMU=";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0904-clk-qcom-ipq6018-workaround-networking-clock-parenti.patch";
      blob = "30c6ceced96c05b8bb55bf98c49c886acf2993ee1";
      sha256 = "sha256-8sUh12jv8cg/WYuFuJnu29tlSRQzqOvQcf7HOU2cSpQ=";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0917-clk-qcom-gcc-ipq6018-mark-gcc_xo_clk_src-as-critical.patch";
      blob = "1844803aa000aa51cf19c0aa4875a709f324ef9c";
      sha256 = "sha256-ECNjJj3N+Tu96lxxo5aDVRpsx+vBUMIvnX+aZYxwEy4=";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0920-clk-add-clk_hw_recalc_rate-to-trigger-HW-clk-rate-re.patch";
      blob = "c9d58702830041757a55069af8c67ab2ff6f2e2c";
      sha256 = "sha256-+C+6CDlwvxnThL0xTJ/WWP7KjOjptBWTyEOhYq1axug=";
    }
  ];

  # N4: the NSS kernel side - the fork's patches-6.18/06xx series, in the
  # order it applies. Target patches (they edit mainline net/ and
  # include/linux/), applied after kernelPatches, which is why they are not
  # in nss/PATCHES.nix.
  #
  # Only patches with enabled consumers are applied. 0600-1, 0600-2,
  # 0600-6, 0600-7, 0603-2 and 0981-1 serve ECM/PPPoE; 0603-2 must follow
  # 0600-2. Patches for disabled client managers and ECM features stay in
  # the upstream pin but are not fetched until that feature is enabled.
  #
  # 0600-8 and 0607-1 are deliberately absent - neither applies to a
  # mainline 6.18 tree (0600-8 reverts a qualcommax hack this tree never
  # applies; all six hunks of 0607-1 fail).
  nssEcmPatches = [
    {
      path = "target/linux/qualcommax/patches-6.18/0600-1-qca-nss-ecm-support-CORE.patch";
      blob = "9482d548fa909cc480bfce5d44d921f919cbb7d7";
      sha256 = "sha256-9IekTlCpSYL8gbaxNUwcVESvNgN98FEQgE7vk63aotQ=";
      note = "priv_flags_ext/IFF_EXT_*, NETDEV_BR_JOIN, the fdb/neigh/route notifier exports, nf_conntrack 6.18 adaptation, nf_conntrack_tcp_no_window_check";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0600-2-qca-nss-ecm-support-PPPOE-offload.patch";
      blob = "360f9ef375d5078d52ea899349584b255ce1c421";
      sha256 = "sha256-xKJtbLO72qX9kGTw2L3LI6TMSAcziDF9V5CJc3wS30E=";
      note = "ppp_generic/pppoe: the channel-connection notifier, ppp_update_stats, pppoe_channel_addressing_get";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0600-6-qca-nss-ecm-support-netfilter-DSCPREMARK.patch";
      blob = "04a511093a11f6c0a62cb80143b0062da4ba757d";
      sha256 = "sha256-AAlkSKpBdvcWx/8A4WBNdMJi5CGqXDfye2FL6tbHvKc=";
      note = "adds CONFIG_NF_CONNTRACK_DSCPREMARK_EXT, its Makefile entry and the includes; the .c/.h themselves are target files/ entries, see nss/SOURCES.nix";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0600-7-qca-nss-ecm-fix-IPv6-user-route-change-event-calls.patch";
      blob = "14384963733b6d656e8be7ce9ebd87b5d882116a";
      sha256 = "sha256-Gmdktj/p4ejwofmxTDulsYmAUko0xVolGRArAWpy3vo=";
      note = "needs 0600-1: only call the rt6 notifier for user changes";
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0603-2-qca-nss-clients-add-l2tp-support.patch";
      blob = "de762226253a367f4ccfcbb806a885fea559891c";
      sha256 = "sha256-ohUIK/dFmogEUeVgIAhlphNwB0esTQIWqKtBf3XDWgo=";
      note = ''
        The one that is not optional: ppp_generic.c gains the exported
        lock-free __ppp_is_multilink()/__ppp_hold_channels(), which the
        fork's ECM patch 002 makes the generic PPP path call. The l2tp
        half is dead here (those modules are not built).
      '';
    }
    {
      path = "target/linux/qualcommax/patches-6.18/0981-1-qca-skb_recycler-support.patch";
      blob = "55b472095abae19c55db5eff3d8c7734583ecf15";
      sha256 = "sha256-7onK/EWXJOxky0B2MGXVhqC0Ez+OnxQjz9QrskiBzao=";
      note = ''
        QCA's skb recycler: the SKB_RECYCLER Kconfig (default y, so it is on
        as soon as the patch applies), the struct sk_buff bitfields - int_pri
        is the one ECM reads - and the net/core hooks. Needs the six
        skbRecyclerFiles below, or net/core/Makefile's new
        skbuff_recycle.o breaks the build.
      '';
    }
  ];

  # The skb recycler's implementation, at the paths 0981-1 compiles them
  # from. Fork files/ entries, not patches, so they are fetched by
  # blob-pinned URL and installed by the device's extraPatchPhase.
  skbRecyclerFiles = [
    {
      path = "net/core/skbuff_recycle.c";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_recycle.c";
      blob = "6312abee73a829719591ea464df7427fd6a10648";
      sha256 = "sha256-VN6B4YI3PXjaPnJLVE1h7VqpynCJiHQQXFEFbS5MzPM=";
      license = "GPL-2.0-only";
      note = "the recycler itself; this is where int_pri is set on RX";
    }
    {
      path = "net/core/skbuff_recycle.h";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_recycle.h";
      blob = "9a4bb877a47538b3840935b3017e4d25653afed2";
      sha256 = "sha256-mQqoi0fORtmtzHNBl68oqbRXpICVF71VM+9vl9gWSMc=";
      license = "GPL-2.0-only";
    }
    {
      path = "net/core/skbuff_notifier.c";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_notifier.c";
      blob = "8c59476db7fe38d641055109d91f59edbf42c0ab";
      sha256 = "sha256-aAdYk3lFLlL6yReDgl35wWuw+xyAVL8CIf53EshZm3Y=";
      license = "GPL-2.0-only";
    }
    {
      path = "net/core/skbuff_notifier.h";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_notifier.h";
      blob = "3d8bfa586fc94b8760fa261742d79a7b1357e8ac";
      sha256 = "sha256-bi8qKA/17P06bEHeA3ROD5VdOKPN1VRb60yYKL/AlwY=";
      license = "GPL-2.0-only";
    }
    {
      path = "net/core/skbuff_debug.c";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_debug.c";
      blob = "50d067592109953ed2504808a152261bcd63e631";
      sha256 = "sha256-jd3Zpo8RExBuiSNQhWF4Ibg90VckGxFW2IcvIagBJyk=";
      license = "GPL-2.0-only";
    }
    {
      path = "net/core/skbuff_debug.h";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_debug.h";
      blob = "43e37ba43b645e191a527b7a0a337213b98665c6";
      sha256 = "sha256-2/d5Iek9Sen9BfK1GM+DcO39DN0Hq5UKv2QbeE4XTeE=";
      license = "GPL-2.0-only";
    }
  ];

  kernelDts = {
    role = "build-input";
    version = "6.18.57";
    url = "https://mirrors.ustc.edu.cn/kernel.org/linux/kernel/v6.x/linux-6.18.57.tar.gz";
    sha256 = "sha256-YWnaN2seaHqWoMsqrx7Dl7+1ahUDbT0BYINPObTL9Eg=";
    provides = [
      "arch/arm64/boot/dts/qcom/ipq6018.dtsi"
      "include/dt-bindings/gpio/gpio.h"
    ];
    note = "Mainline: no wifi@c000000 (the fork's 0906 adds it) and no nss_region - hence 0103. It does carry the qcom,ipq6018-wcss-pil node.";
  };

  ppeGeneration = {
    role = "reference-only";
    repo = "https://github.com/VIKINGYFY/immortalwrt";
    refs = {
      owrt = "5e2fa56f8f0d03bd33aef5c3f4014ed86f4d7c1d";
      test = "cee3055ff54b59c74458b7ca85315429f27240ba";
    };
    blobs = {
      "target/linux/qualcommax/dts/ipq6010-re-cs-02.dts" = "0e0804a79ada366067e1903781636a955161df27";
      "target/linux/qualcommax/dts/ipq6010-re-cs.dtsi" = "c4dc690bf1b3e7e88583b8322f19eff66721e098";
      "target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-common.dtsi" = {
        owrt = "2f77e45a94335f3db53889ab3a24782ea0c0bb87";
        test = "9df78f12d94ab0ba76d403f3e958b704aca3a16c";
      };
    };
    note = ''
      PPE generation: its ess.dtsi is ppe@3a000000 (qualcomm,ipq6018-ppe), so
      nothing from here mixes with the NSS pin. Spells the QCA8075 package the
      same way the pin does (@0 / reg 0, children at 24..27); immortalwrt
      official writes it @24 / reg 24.
    '';
  };
}
