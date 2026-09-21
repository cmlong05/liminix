


let
  immortalwrt = {
    repo = "https://github.com/immortalwrt/immortalwrt";
    ref = "8d9475a99f03784210ff158f9f27c83a9c93a735";
    rawBase = "https://raw.githubusercontent.com/immortalwrt/immortalwrt/8d9475a99f03784210ff158f9f27c83a9c93a735";
  };
in
{
  # The pin default.nix fetches from. Change this ref, then update the two
  # sha256 values below from the fetch error message, then rebuild.
  upstream = immortalwrt;

  boardDts = {
    role = "fetched";
    path = "target/linux/qualcommax/dts/ipq6010-re-cs-02.dts";
    blob = "8594ea7bf0013a7b5384b2c3413db2648cac36c8";
    sha256 = "sha256-HfqowfB/ZW3tSg/W4Quk9Ac6lXlVBU3v7h1iM8E6jwk=";
    license = "GPL-2.0-or-later OR MIT";
    note = ''
      Upstream's board dts, used verbatim on both branches - it is the radio
      variant, enabling &pcie_phy, &pcie0 with its QCN9074 child and the AHB
      &wifi node. Its one non-obvious dependency is the wifi@c000000 node
      those references resolve to; see wifiNodePatch below.

      Its other quirk is the Bluetooth port it enables on gpio48/49 (the pin
      group is even named btuart_pins), which this board does not have, and
      which no sibling board upstream writes the block for does either
      (ipq6010-re-cs-07.dts has none of it). That one thing is overridden,
      not patched, in no-bluetooth.dtsi - see the note there for what
      leaving it enabled would cost.
    '';
  };

  # Fetched like the two files above, not vendored: this is upstream's own
  # device-tree-only patch, and it is what makes the board dts above
  # compile.
  wifiNodePatch = {
    role = "fetched";
    path = "target/linux/qualcommax/patches-6.18/0906-arm64-dts-qcom-ipq6018-add-wifi-node.patch";
    blob = "084663312980aee6a56c4b65b73cc3611fc3f777";
    sha256 = "sha256-Pb1jRTQ4FzgcUiyjUqD3/BRdmc9+/RkXgGdG/ppWeOc=";
    lines = 120;
    author = "Mantas Pucka <mantas@8devices.com>, 2024-01-16, \"[PATCH 19/19] arm64: dts: qcom: ipq6018: add wifi node\"";
    note = ''
      Adds wifi@c000000 to ipq6018.dtsi with status = "disabled" - device
      tree only, no driver, and nothing in it enables the radio by itself
      (upstream's board dts does that with "&wifi { status = "okay"; }").

      The same patch content is carried by the ax6600 branch as its vendored
      patches/110-ipq6018-wifi-node.patch, and by the 6.12-era ref this pin
      used to point at; the three differ only in the hunk header's line
      numbers (@@ -828 here, @@ -834 there, @@ -831 there), body identical.
      Taking it from upstream keeps one source of truth and means following
      upstream is the same one-line ref change as for the dts.
    '';
  };

  boardDtsi = {
    role = "fetched";
    path = "target/linux/qualcommax/dts/ipq6010-re-cs.dtsi";
    blob = "bd971145c8c753fcb11e03caf0dce0a88c485f03";
    sha256 = "sha256-znEYZsGML/PGRd9KuSradXTwQyNlL+cRTAUh83a2LW0=";
    license = "GPL-2.0-or-later OR MIT";
    note = ''
      The shared board description the board dts includes: LEDs, chosen/
      stdout-path, uart3 with its serial3 pinmux, sdhc, the GPIO20
      reservation, mdio pins, the qca8075 package and uniphy0. Carries the
      board-level detail that a hand-written version would have to retype -
      and did retype, losing the serial3 pinmux once.
      Identical bytes in immortalwrt and openwrt, which share this history;
      still the same blob on immortalwrt master as of 2026-09-09. Upstream
      last changed it in the PPE conversion commit, where the only edit was
      appending a trailing &uniphy0 enablement.
    '';
  };


  kernelDts = {
    role = "build-input";
    url = "https://mirrors.ustc.edu.cn/kernel.org/linux/kernel/v6.x/linux-6.18.52.tar.gz";
    sha256 = "sha256-TDBEYWCf0nFJhwDQIQ6fQc3xYoSmBplCLaS610x9GfU=";
    provides = [
      "arch/arm64/boot/dts/qcom/ipq6018.dtsi"
      "include/dt-bindings/gpio/gpio.h"
    ];
    note = ''
      Its ipq6018.dtsi is the unpatched mainline one: no wifi@c000000 node.
      That node comes from patches/110-ipq6018-wifi-node.patch on this branch
      as well as on ax6600 - see wifiNodePatch above - and it is what
      upstream's "&wifi" reference needs in order to compile.
    '';
  };

  # Reference only. Kept because it is what caught the serial3 pinmux that
  # an earlier hand-inlined version of this board dts had lost: the fork sets
  # it in its ipq6018-common.dtsi rather than in the board dtsi, which is how
  # we learned to check. Its serial/tmp1628/PHY-package choices are not used
  # here; the revision we fetch already carries all of it.
  vkOwrt = {
    role = "reference-only";
    repo = "https://github.com/VIKINGYFY/immortalwrt";
    ref = "owrt (cee3055ff54b)";
    blobs = {
      "target/linux/qualcommax/dts/ipq6010-re-cs-02.dts" = "0e0804a79ada366067e1903781636a955161df27";
      "target/linux/qualcommax/dts/ipq6010-re-cs.dtsi" = "c4dc690bf1b3e7e88583b8322f19eff66721e098";
      "target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-common.dtsi" = "9df78f12d94ab0ba76d403f3e958b704aca3a16c";
    };
    note = ''
      Same PPE lineage as the revision we fetch, but it keeps the fork's own
      PHY package spelling (ethernet-phy-package@0, reg 0, qca8075_24..27).
      Do not swap our source for this one: the package node's reg is the
      base address the driver adds the COMBO/PQSGMII offsets to
      (base + 4 / base + 5), so reg 0 and reg 24 address different registers.
    '';
  };

  # Reference only, and the reason this ledger says "identify by blob sha":
  # same file names as the entries above, different stack and different bytes.
  vkMain = {
    role = "do-not-use";
    repo = "https://github.com/VIKINGYFY/immortalwrt";
    ref = "main (90448eeb2b8f)";
    blobs = {
      "target/linux/qualcommax/dts/ipq6010-re-cs-02.dts" = "bef591b4ef6c421f28a0f0d3aa67817ac7a14799";
      "target/linux/qualcommax/dts/ipq6010-re-cs.dtsi" = "47b87bc05bcbc9e718d99b734b2241473745db90";
    };
    note = ''
      Pre-PPE generation: ethernet0..4 = &dp1..&dp5 (qca-nss-dp) with
      switch_lan_bmp / qcom,port_phyinfo on &switch (qca-ssdk), and its dtsi
    '';
  };
}
