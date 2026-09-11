# Where every non-local input of this device's device tree comes from, and
# how our delta from it is expressed. Read this before touching the board
# device tree.
#
# The goal is: as little local code as possible, and provenance that can be
# re-checked mechanically. So upstream's board description is NOT committed
# to this tree at all - it is fetched at build time from the pin below (with
# fetchurl, so the sha256 values in this file are the proof of which
# revision we are on) and used verbatim, wireless and all. There is no local
# board .dts and no patch to it:
#
#   - upstream's board dts is the radio variant: it enables &pcie_phy, &pcie0
#     with its QCN9074 child and the AHB &wifi node.
#   - the wifi@c000000 node those references point at comes from upstream's
#     own device-tree-only patch, fetched by URL like the dts itself (it
#     adds the node with status = "disabled", no driver): see the
#     wifiNodePatch entry below. Applying it is what lets upstream's board
#     dts compile here.
#   - this branch is wired-only *for now* only in the sense that it builds no
#     wireless drivers or config, so those nodes are declared but nothing
#     probes them. Adding wireless later means adding the driver patches and
#     config, not touching the device tree.
#   - the ax6600 (radio) branch builds the same device tree with those
#     drivers; its only extra is a small fragment enabling &q6v5_wcss for the
#     AHB radio, which is what radio bring-up needs beyond declaration.
#   - the two overrides on this branch are in overrides.dtsi: upstream
#     enables a Bluetooth port this board does not have (leaving it enabled
#     is not inert - it binds a second tty and muxes two pins), and upstream
#     asks for a 600 MHz NSS crypto clock that mainline's nss_crypto_clk_src
#     cannot produce. Both are overrides rather than patches, so every
#     upstream file stays byte for byte; the crypto one used to be a LOCAL
#     CHANGE inside the vendored ipq6018-ess.dtsi, which is now upstream's
#     copy exactly.
#
#
# If a device tree addition or override is ever needed, the place for it is a
# fragment handed to hardware.dts.includes, written in plain "&label { ... }"
# syntax that survives upstream reformatting.
#
# Everything else about the board - the DSA port wiring, the PHY package,
# the QCA8081 node, aliases, sdhc, the LEDs, the gpio-keys, the console
# pinmux, the GPIO20 reservation - stays upstream's, fetched and used as it
# is. Tracking upstream means editing one ref (and the two hashes) here,
# rebuilding, and reading what the compiler says.
#
# Identify sources by blob sha, never by file name: the same path exists in
# several forks with different content, see the VIKINGYFY entries below.
#
# All sha256 values below are flat file hashes - what fetchurl wants, and
# reproducible with
#   nix-hash --flat --type sha256 --sri <file>
# plain "nix-hash" prints the NAR hash instead and will not match.
#
# Include resolution, for reference: the board .dts includes
# "ipq6010-re-cs.dtsi", which resolves because default.nix copies both files
# into one store directory. The dtsi's own includes resolve against the
# kernel tree:
#   "ipq6018.dtsi"      -> ${kernel.modulesupport}/arch/arm64/boot/dts/qcom/
#   "ipq6018-ess.dtsi"  -> the same directory, vendored there by ether/src
#   <dt-bindings/...>   -> ${kernel.headers}/include, added by
#                          modules/outputs.nix:102
# Corollary: never drop an ipq6018.dtsi or ipq6018-ess.dtsi into a
# directory that ends up on includePaths. A quoted include would silently
# prefer the local file and the kernel's copy would not be read at all.
let
  immortalwrt = {
    repo = "https://github.com/immortalwrt/immortalwrt";
    ref = "f50435627d370a1bb07d455d7081207b7b6a744e";
    rawBase = "https://raw.githubusercontent.com/immortalwrt/immortalwrt/f50435627d370a1bb07d455d7081207b7b6a744e";
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
    path = "target/linux/qualcommax/patches-6.12/0906-arm64-dts-qcom-ipq6018-add-wifi-node.patch";
    blob = "3ff649f2a4a883bcbcdbbac00fea44bb6571c5d2";
    sha256 = "sha256-K+QNclrLRtU+Oi6DHDLgc9EAHCguKf6JWN5CDLn0hTQ=";
    lines = 120;
    author = "Mantas Pucka <mantas@8devices.com>, 2024-01-16, \"[PATCH 19/19] arm64: dts: qcom: ipq6018: add wifi node\"";
    note = ''
      Adds wifi@c000000 to ipq6018.dtsi with status = "disabled" - device
      tree only, no driver, and nothing in it enables the radio by itself
      (upstream's board dts does that with "&wifi { status = "okay"; }").
      Applied with --fuzz=3 and without the lenient "|| echo" used for the
      ether patches, so a failure to apply stops the build rather than being
      swallowed; a grep for the node follows it.

      The same patch content is carried by the ax6600 branch as its vendored
      patches/110-ipq6018-wifi-node.patch; the two differ only in the hunk
      header's line numbers (@@ -834 vs @@ -831), body identical. Taking it
      from upstream keeps one source of truth and means following upstream
      is the same one-line ref change as for the dts.
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

  # Vendored in the tree, unlike the files above: ether/src puts it into the
  # kernel tree, and the dtsi above includes it by that name. Now byte for
  # byte upstream's - the one deviation it used to carry (the NSS crypto
  # clock rate) is an override in ../overrides.dtsi instead.
  essDtsi = {
    role = "vendored-verbatim";
    repo = immortalwrt.repo;
    ref = immortalwrt.ref;
    path = "target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6018-ess.dtsi";
    blob = "0de37caf7da1c68224b8f8a2b63141e8f4fd9919";
    sha256 = "sha256-RYyGI0bMXbuytQjU79Avhbr/Lo7bfio0U0CKrEBjIUY=";
    treePath = "devices/jdcloud-ax6600/ether/src/arch/arm64/boot/dts/qcom/ipq6018-ess.dtsi";
    note = ''
      Provides &switch, &edma and the UNIPHY PCS nodes, so the DTS build
      depends on ether/ being applied. Keeping it identical to upstream means
      refreshing it is a copy, and cmp against the blob above is a valid
      assertion.
    '';
  };

  # The SoC dtsi and the dt-bindings headers, from the kernel the device
  # builds; see the fetchurl in default.nix.
  kernelDts = {
    role = "build-input";
    url = "https://mirrors.ustc.edu.cn/kernel.org/linux/kernel/v6.x/linux-6.18.49.tar.gz";
    sha256 = "sha256-TDBEYWCf0nFJHQDQIQ6fQc3xYoSmBplCLaS610x9GfU=";
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
      pulls in ipq6018-nss.dtsi / ipq6018-common.dtsi. That is the driver
      stack ether/ deliberately does not use.
    '';
  };
}
