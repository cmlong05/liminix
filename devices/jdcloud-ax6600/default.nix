{
  system = {
    crossSystem = {
      config = "aarch64-unknown-linux-musl";
    };
  };

  description = ''

    == JDCloud RE-CS-02 (京东云雅典娜 AX6600) - 


    === Hardware summary

    * Qualcomm IPQ6010 (4x Cortex-A53 @1.8GHz), 1GiB RAM
    * 128GB/256GB eMMC (GPT), community "dual-boot" GPT layout:
      `+0:HLOS+`/`+0:HLOS_1+` (6MiB kernel FIT slots), `+rootfs+`/
      `+rootfs_1+` (2GiB), `+0:ART+` (calibration, keep a backup)
    * Ethernet: QCA8075 4x 1G switch + QCA8081 2.5G PHY over the

    * WiFi: REMOVED (QCN9074 5GHz on PCIe0 and the IPQ6018 AHB radio
      are both absent from the kernel config and the device tree)
    * serial console on BLSP1 UART3 (`+serial@78b1000+`, 115200n8)
    * USB 3.0, tmp1628 status display, 3 LEDs / 3 keys

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
            name = "linux-6.18.52.tar.gz";
            inherit (kernelSource) url sha256;
          };
        version = "6.18.52";
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
            kernelPath = f: lib.removePrefix "target/linux/qualcommax/files/" f.path;
            wifiNodePatch = upstreamFile sources.wifiNodePatch.path sources.wifiNodePatch.sha256;
          in
          ''
          ${lib.concatMapStrings (f: ''
            install -D -m644 ${upstreamFile f.path f.sha256} ${kernelPath f}
          ${lib.concatMapStrings (p: ''
          # The board dts is upstream's radio variant, so the node its &wifi
          # reference needs must exist. Device tree only, no driver; applied
          # strictly (no "|| echo") so a failure to apply stops the build.
          patch -p1 --fuzz=3 < ${wifiNodePatch}
          grep -q "wifi: wifi@c000000" arch/arm64/boot/dts/qcom/ipq6018.dtsi \
            || { echo "wifi node missing after patch"; exit 1; }
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
          PHYLIB = "y";
          QCA807X_PHY = "y";
          QCA808X_PHY = "y";

          # MDIO bus driver for the qcom,ipq6018-mdio/ipq4019-mdio
          # node that carries the QCA8075 package and QCA8081 (the
          MDIO_IPQ4019 = "y";
          OF_MDIO = "y";

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
      };

      hardware =
        {

          defaultOutput = "uimage";

          rootDevice = "/dev/mtdblock0";
          loadAddress = lim.parseInt "0x41000000";
          entryPoint = lim.parseInt "0x41000000";

          flash.eraseBlockSize = 65536;

          dts =
            let
              sources = import ./SOURCES.nix;
              upstreamFile = name: path: hash:
                pkgs.pkgsBuildBuild.fetchurl {
                  inherit name hash;
                  url = "${sources.upstream.rawBase}/${path}";
                };

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
