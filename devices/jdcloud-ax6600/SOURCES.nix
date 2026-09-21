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
      and qcom,port_phyinfo for qca-ssdk. Radio variant: overrides.dtsi changes
      its qcom,ath11k-fw-memory-mode from 1 to 2.
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

  # Adds wifi@c000000 to ipq6018.dtsi (status disabled, no driver), which the
  # board dts' &wifi reference needs in order to compile.
  wifiNodePatch = {
    role = "fetched";
    path = "target/linux/qualcommax/patches-6.18/0906-arm64-dts-qcom-ipq6018-add-wifi-node.patch";
    blob = "0b24a3b74755ab5498bbfabba6bfc4304c1d40a2";
    sha256 = "sha256-J8PmbmQQjAQgBXOEL1l1dLqDb1g///j2iuNR30Jy70M=";
    lines = 120;
    author = "Mantas Pucka <mantas@8devices.com>, 2024-01-16, \"[PATCH 19/19] arm64: dts: qcom: ipq6018: add wifi node\"";
  };

  # Applied in this order by the patch phase. The six clock patches are
  # upstream's - identical blob shas in both trees - not the fork's.
  kernelPatches = [
    {
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

  kernelDts = {
    role = "build-input";
    url = "https://mirrors.ustc.edu.cn/kernel.org/linux/kernel/v6.x/linux-6.18.52.tar.gz";
    sha256 = "sha256-MEZUEBTOu0xnd/HP0DY0ozsOmHreg3tKcYujaAKt72w=";
    provides = [
      "arch/arm64/boot/dts/qcom/ipq6018.dtsi"
      "include/dt-bindings/gpio/gpio.h"
    ];
    note = "Mainline: no wifi@c000000 and no nss_region - hence wifiNodePatch and 0103.";
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
