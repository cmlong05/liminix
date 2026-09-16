{
  system = {
    crossSystem = {
      config = "aarch64-unknown-linux-musl";
    };
  };

  description = ''

    == JDCloud RE-CS-02 (京东云雅典娜 AX6600) - WIRED-ONLY build

    This is the no-wifi variant. All WiFi/PCIe/ath11k material has been
    removed on purpose: no radio kernel patches, no ath11k firmware
    staging service, no PCIe node in the device tree and no wlan
    network interfaces. The Ethernet stack is untouched and complete.
    See the ax6600 branch for the radio bring-up variant.

    === Hardware summary

    * Qualcomm IPQ6010 (4x Cortex-A53 @1.8GHz), 1GiB RAM
    * 128GB/256GB eMMC (GPT), community "dual-boot" GPT layout:
      `+0:HLOS+`/`+0:HLOS_1+` (6MiB kernel FIT slots), `+rootfs+`/
      `+rootfs_1+` (2GiB), `+0:ART+` (calibration, keep a backup)
    * Ethernet: QCA8075 4x 1G switch + QCA8081 2.5G PHY over the
      ESS/PPE/EDMA/UNIPHY stack (see phase E below). This is the only
      network transport in this variant.
    * WiFi: REMOVED (QCN9074 5GHz on PCIe0 and the IPQ6018 AHB radio
      are both absent from the kernel config and the device tree)
    * serial console on BLSP1 UART3 (`+serial@78b1000+`, 115200n8)
    * USB 3.0, tmp1628 status display, 3 LEDs / 3 keys

    === Ethernet (phase E): ESS/PPE/EDMA/UNIPHY

    The SoC-side ESS/EDMA data path is NOT in mainline: mainline 6.18
    ships the PPE register/configuration library (`+QCOM_PPE+`) and the
    IPQ4019 MDIO bus driver, but no EDMA netdev driver, no UNIPHY PCS
    driver and no DSA out-of-band tagging. It also still lacks the
    fwnode-PCS provider framework that the UNIPHY driver needs
    (`+fwnode_pcs_add_provider+`), and the IPQ6018 CMN-PLL clock driver.
    Those pieces are vendored from upstream OpenWrt qualcommax (kernel
    6.18) under `+./ether/+` - the same driver set that immortalwrt /
    OpenWrt use for this board, where it is also built into the kernel
    rather than shipped as a package. Nothing here is wifi-related.

    This is a deliberate copy of an already build-verified and
    hardware-booted configuration; see `+./BRINGUP.md+` for the
    hardware evidence and the known -ENODEV pitfall (MDIO_IPQ4019).

    === Bootloader

    Uses the community "unbrickable" U-Boot
    (`+uboot-JDC_AX1800_Pro-AX6600_Athena-20240510.bin+`), whose web
    UI at http://192.168.1.1 provides:

    * `/` - flash a ROM image
    * `/img.html` - flash a GPT or whole-eMMC image
    * `/uboot.html` - flash U-Boot
    * `/uimage.html` - boot a FIT/initramfs image from RAM

    The stock env has `+bootcmd=bootipq+`, `+ipaddr=192.168.1.1+`,
    `+serverip=192.168.1.2+` and `+fdt_high=0x48500000+`.

    === Development boot

    The easiest way to develop is the full-system ram image (see
    `+ax6600-lan-ram.nix+`): the whole system is embedded in the kernel
    initramfs (`+boot.initramfs.fullSystem+`), producing a single FIT
    image (`+outputs.uimage+`) that the U-Boot web uploader at
    `/uimage.html` can boot directly - no root device, no TFTP.

    `+outputs.tftpboot+` (the default output) loads kernel, dtb and a
    squashfs rootfs into RAM (rootfs exposed via the phram driver as
    `/dev/mtdblock0`) and boots without touching the eMMC. Requires a
    serial console and a TFTP server on 192.168.1.2 serving the
    `+result/+` directory.

  '';

  module =
    {
      pkgs,
      config,
      lib,
      lim,
      ...
    }:
    {
      imports = [
        ../families/ipq6018.nix
        ../../modules/outputs/tftpboot.nix
        # hardware.networkInterfaces (lan1..lan4, wan) is built with the
        # network module's link service, so it must always be present
        ../../modules/network
      ];

      kernel = {
        # url and hash come from SOURCES.nix so the kernel pin lives in one
        # place, next to the blob shas of everything else upstream.
        src =
          let
            kernelSource = (import ./SOURCES.nix).kernelDts;
          in
          pkgs.pkgsBuildBuild.fetchurl {
            name = "linux-6.18.49.tar.gz";
            inherit (kernelSource) url sha256;
          };
        version = "6.18.49";
        # Ethernet only for now. The radio is not driven on this branch -
        # no ath11k, no remoteproc, no PCIe config - but the device tree
        # keeps it: the board dts below is upstream's, which is the radio
        # variant, and the only thing that makes it compile here is
        # upstream's own device-tree-only patch (wifiNodePatch in
        # ./SOURCES.nix, fetched by URL like the dts itself) which adds the
        # wifi@c000000 node those references point at. Adding wireless later
        # means adding drivers and config, not touching the device tree.
        #
        # E phase: Qualcomm ESS/PPE/EDMA/UNIPHY in-tree ethernet
        # (ported from upstream OpenWrt qualcommax; see ./ether/README).
        # Nothing upstream is committed to this tree: the driver files and
        # the patches are fetched here by URL and hash. The pin is in
        # ./SOURCES.nix, the list and its order in ./ether/SOURCES.nix.
        extraPatchPhase =
          let
            sources = import ./SOURCES.nix;
            upstreamFile =
              path: hash:
              pkgs.pkgsBuildBuild.fetchurl {
                name = baseNameOf path;
                inherit hash;
                url = "${sources.upstream.rawBase}/${path}";
              };
            # A driver file's path inside the kernel tree is its upstream
            # path with the target prefix removed - the same layout the
            # old `cp -r ether/src/. .` produced.
            kernelPath = f: lib.removePrefix "target/linux/qualcommax/files/" f.path;
            patchName = p: baseNameOf p.path;
            wifiNodePatch = upstreamFile sources.wifiNodePatch.path sources.wifiNodePatch.sha256;
          in
          ''
          # Sources first: install every file from the store, so what gets
          # compiled is exactly the pinned revision - there is no local copy
          # that could drift out of date.
          ${lib.concatMapStrings (f: ''
            install -D -m644 ${upstreamFile f.path f.sha256} ${kernelPath f}
          '') sources.ether.files}
          # Then patches, staged so the loop below can walk them by name.
          # 737-02 and 0950 both partially apply (their context assumes
          # OpenWrt's cumulative net tree). 0950's missing hunks come from
          # fixups.patch below; 737-02's is deliberately not supplied, see
          # the head of that file. The order is the order of `ether.patches`.
          mkdir -p .ether-patches
          ${lib.concatMapStrings (p: ''
            install -m644 ${upstreamFile p.path p.sha256} .ether-patches/${patchName p}
          '') sources.ether.patches}
          for p in ${lib.concatStringsSep " " (map patchName sources.ether.patches)}; do
            patch -p1 --forward --batch < .ether-patches/$p \
              || echo "ether kernel patch partially applied (expected): $p"
          done
          patch -p1 --forward --batch < ${./ether/fixups.patch} \
            || { echo "ether fixups failed"; exit 1; }
          # The board dts is upstream's radio variant, so the node its &wifi
          # reference needs must exist. Device tree only, no driver; applied
          # strictly (no "|| echo") so a failure to apply stops the build.
          patch -p1 --fuzz=3 < ${wifiNodePatch}
          grep -q "wifi: wifi@c000000" arch/arm64/boot/dts/qcom/ipq6018.dtsi \
            || { echo "wifi node missing after patch"; exit 1; }
          # sanity: the features the ethernet drivers need must exist
          grep -q fwnode_pcs_add_provider drivers/net/pcs/pcs.c || exit 1
          grep -q DSA_TAG_PROTO_OOB_VALUE include/net/dsa.h || exit 1
          grep -q "pl->mac_ops->mac_select_pcs" drivers/net/phy/phylink.c || exit 1
        '';
        config = {
          # pstore/ramoops: persistent kernel log at 0x60000000 so it
          # can be read back from the U-Boot console (no serial cable
          # needed for bring-up).
          PSTORE = "y";
          PSTORE_RAM = "y";
          PSTORE_CONSOLE = "y";
          PSTORE_COMPRESS = "n";
          # CRITICAL: disable KASLR. The aarch64 module sets
          # RANDOMIZE_BASE=y, and if U-Boot injects a kaslr-seed the
          # kernel relocates itself to a random physical address in
          # head.S - before reserved-memory regions (tz/smem) are
          # parsed, so it can land on firmware memory and die
          # silently before any console output. OpenWrt does not
          # enable KASLR on these boards.
          RANDOMIZE_BASE = lib.mkForce "n";

          # --- Ethernet PHYs (QCA8075 4x1G psgmii package + QCA8081
          # 2.5G). Both drivers are mainline; the SoC-side ESS/EDMA
          # MAC driver is not (phase E).
          # built-in: no modprobe auto-load on Liminix, and
          # the ESS/PPE (in-tree) netdevs need their PHYs at boot
          PHYLIB = "y";
          QCA807X_PHY = "y";
          QCA808X_PHY = "y";

          # MDIO bus driver for the qcom,ipq6018-mdio/ipq4019-mdio
          # node that carries the QCA8075 package and QCA8081 (the
          # board dts PHYs; without it DSA ports fail -ENODEV - the
          # first hardware boot hit exactly this).
          MDIO_IPQ4019 = "y";
          OF_MDIO = "y";

          # --- E phase: ESS/PPE/EDMA/UNIPHY in-tree stack (from
          # OpenWrt qualcommax; sources and patches fetched per
          # ./SOURCES.nix + ./ether/SOURCES.nix). Built in so the DSA
          # ports (lan1-4/wan)
          # appear at boot without kmodloader.
          NET_DSA = "y";
          NET_DSA_TAG_OOB = "y";
          PCS_QCA_UNIPHY = "y";
          QCOM_80211AX_PPE = "y";
          QCOM_EDMA = "y";
          IPQ_CMN_PLL = "y";
          # NB: CONFIG_PAGE_POOL (which qca_edma.c needs) cannot be set
          # from here - it is declared "bool" with no prompt, so kconfig
          # ignores a .config line for it and only "select" can turn it
          # on. That is why QCOM_EDMA selects it, in ether/fixups.patch.
        };
        # NB: the wifi conditionalConfig block (WLAN -> ATH11K /
        # QCOM_Q6V5_WCSS / PHY_QCOM_QMP_PCIE ...) is intentionally
        # absent. This build never imports modules/wlan.nix, so no
        # wireless stack is compiled at all.
      };

      boot = {
        commandLine = [
          "console=ttyMSM0,115200n8"
        ];
        tftp = {
          ipaddr = "192.168.1.1";
          serverip = "192.168.1.2";
          # Rootfs is TFTP-loaded at this address. Must stay clear of
          # the kernel decompression area (loadAddress 0x41000000 +
          # ~64MiB) and of U-Boot's fdt_high (0x48500000).
          loadAddress = lim.parseInt "0x70000000";
        };
      };

      hardware =
        {
          defaultOutput = "tftpboot";
          # tftpboot uses phram to expose the RAM rootfs as /dev/mtdblock0
          rootDevice = "/dev/mtdblock0";
          loadAddress = lim.parseInt "0x41000000";
          entryPoint = lim.parseInt "0x41000000";
          # only used by tftpboot (phram mtdparts)
          flash.eraseBlockSize = 65536;
          # The board device tree comes from upstream at build time and is
          # used verbatim, wireless included: ./SOURCES.nix holds the pin and
          # the hashes, and the radio nodes upstream's board dts declares are
          # simply not driven yet on this branch. Nothing upstream wrote is
          # committed to this tree, so following upstream means changing one
          # ref and two hashes in SOURCES.nix.
          dts =
            let
              sources = import ./SOURCES.nix;
              upstreamFile = name: path: hash:
                pkgs.pkgsBuildBuild.fetchurl {
                  inherit name hash;
                  url = "${sources.upstream.rawBase}/${path}";
                };
              # Upstream ships the board .dts and the dtsi it includes as two
              # separate files; they go into one directory so that the quoted
              # include resolves.
              upstreamTree = pkgs.pkgsBuildBuild.runCommand "ipq6010-re-cs-upstream" { } ''
                mkdir -p $out
                cp ${upstreamFile "ipq6010-re-cs-02.dts" sources.boardDts.path sources.boardDts.sha256} $out/ipq6010-re-cs-02.dts
                cp ${upstreamFile "ipq6010-re-cs.dtsi" sources.boardDtsi.path sources.boardDtsi.sha256} $out/ipq6010-re-cs.dtsi
              '';
            in
            {
              src = "${upstreamTree}/ipq6010-re-cs-02.dts";
              includePaths = [
                upstreamTree
                "${config.system.outputs.kernel.modulesupport}/arch/arm64/boot/dts/qcom/"
              ];
              # The complete list of our overrides on upstream's device tree,
              # two of them, both overrides rather than patches so that every
              # upstream file stays byte for byte: see ./overrides.dtsi.
              includes = [ ./overrides.dtsi ];
            };

          networkInterfaces =
            let
              inherit (config.system.service.network) link;
            in
            {
              # E phase: DSA user ports of the ESS/PPE switch, named by
              # their dts 'label' (lan1..lan4, wan). Drivers are built
              # in, so no module-load dependency is needed.
              lan1 = link.build { ifname = "lan1"; };
              lan2 = link.build { ifname = "lan2"; };
              lan3 = link.build { ifname = "lan3"; };
              lan4 = link.build { ifname = "lan4"; };
              wan = link.build { ifname = "wan"; };

              # NB: no wlan0 entry here. The ax6600 branch adds a wlan0
              # link depending on the ath11k kmodloader; this build has
              # neither the module nor the radio.
            };
        };
    };
}
