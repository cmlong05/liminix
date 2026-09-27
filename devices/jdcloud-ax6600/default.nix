{
  system = {
    crossSystem = {
      config = "aarch64-unknown-linux-musl";
    };
  };

  description = ''

    == JDCloud RE-CS-02 (京东云雅典娜 AX6600) - 
    === Hardware summary

    * Qualcomm IPQ6010 (4x Cortex-A53 @1.8GHz), 原厂 1GiB RAM，改成后4GiB,可用3GiB，
    * 64GB/128GB/256GB eMMC (GPT), community "dual-boot" GPT layout:
      `+0:HLOS+`/`+0:HLOS_1+` (6MiB kernel FIT slots), `+rootfs+`/
      `+rootfs_1+`, `+0:ART+` (calibration, keep a backup)
    * Ethernet: QCA8075 4x 1G switch + QCA8081 2.5G PHY
    * WiFi:  (QCN9074 5.2GHz on PCIe0 and the IPQ6018 AHB radio (2.4+5.8Ghz)
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
        ../../modules/network
      ];

      kernel = {
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
            kernelPatch =
              p:
              pkgs.pkgsBuildBuild.fetchurl {
                name = baseNameOf p.path;
                inherit (p) sha256;
                url = "${sources.upstream.rawBase}/${p.path}";
              };
            kernelPatches = map kernelPatch sources.kernelPatches;
            nssEcmPatches = map kernelPatch sources.nssEcmPatches;
            wirelessSources = import ./wireless/SOURCES.nix;
            checks = import ./kernel-checks.nix { inherit lib; };

            # Each wireless patch with the fuzz its group allows, kept as a
            # list: the phase applies them one call at a time.
            wirelessPatch =
              p:
              {
                inherit (p) fuzz;
                file = pkgs.pkgsBuildBuild.fetchurl {
                  name = baseNameOf p.path;
                  inherit (p) url sha256;
                };
              };
            wirelessPatches = map wirelessPatch wirelessSources.patches;

            nssKernelFiles = pkgs.pkgsBuildBuild.callPackage ./nss/kernel-files {
              sources = import ./nss/SOURCES.nix;
            };

            deviceTreeInputs = pkgs.pkgsBuildBuild.runCommand "ipq6010-nss-devicetree" { } ''
              mkdir -p $out/arch/arm64/boot/dts/qcom $out/include/dt-bindings/net
              cp ${upstreamFile sources.essDtsi.path sources.essDtsi.sha256} \
                 $out/arch/arm64/boot/dts/qcom/ipq6018-ess.dtsi
              cp ${upstreamFile sources.nssDtsi.path sources.nssDtsi.sha256} \
                 $out/arch/arm64/boot/dts/qcom/ipq6018-nss.dtsi
              cp ${upstreamFile sources.commonDtsi.path sources.commonDtsi.sha256} \
                 $out/arch/arm64/boot/dts/qcom/ipq6018-common.dtsi
              cp ${upstreamFile sources.essHeader.path sources.essHeader.sha256} \
                 $out/include/dt-bindings/net/qcom-ipq-ess.h
            '';

            applyPatch = fuzz: p: "apply_patch ${toString fuzz} ${p}";
            verify = entries: checks.lines (lib.concatMap (e: e.verify or [ ]) entries);

            baseChecks = verify (sources.kernelPatches ++ sources.nssEcmPatches);
            wirelessChecks = verify wirelessSources.patches;
          in
          ''
          export NSS_KERNEL_FILES=${nssKernelFiles}
          export DT_INPUTS=${deviceTreeInputs}

          . ${./extra-patch-phase.sh}

          require_wcss_pil_in_tarball

          # The two base lists, in SOURCES.nix order, at fuzz 0: a hunk
          # that stops matching means the tree moved, which must fail
          # rather than drift.
          ${lib.concatMapStringsSep "\n" (p: applyPatch 0 p) (kernelPatches ++ nssEcmPatches)}
          ${baseChecks}

          # wcss and ath11k sets, each at the fuzz its group allows.
          ${lib.concatMapStringsSep "\n" (p: applyPatch p.fuzz p.file) wirelessPatches}
          ${wirelessChecks}

          install_overlay "$NSS_KERNEL_FILES"
          install_overlay "$DT_INPUTS"
          ${checks.lines checks.installed}
        '';
        config = {
          # pstore/ramoops: persistent kernel log at 0x60000000 so it
          # can be read back from the U-Boot console (no serial cable
          # needed for bring-up).
          PSTORE = "y";
          PSTORE_RAM = "y";
          PSTORE_CONSOLE = "y";
          PSTORE_COMPRESS = "n";

          RANDOMIZE_BASE = lib.mkForce "n";

          # --- Ethernet PHYs (QCA8075 4x1G psgmii package + QCA8081
          PHYLIB = "y";
          QCA807X_PHY = "y";
          QCA808X_PHY = "y";
          AQUANTIA_PHY = "y";

          MDIO_IPQ4019 = "y";
          OF_MDIO = "y";  
          I2C = "y";
          HWSPINLOCK = "y";
          HWSPINLOCK_QCOM = "y";
          QCOM_SMEM = "y";

          PPPOE = "y";
          VLAN_8021Q = "y";

          NETFILTER = "y";
          NETFILTER_ADVANCED = "y";
          NF_CONNTRACK = "m";
          NF_CONNTRACK_EVENTS = "y";
          NF_CONNTRACK_MARK = "y";
          NF_CONNTRACK_DSCPREMARK_EXT = "y";
          NF_DEFRAG_IPV4 = "m";
          NF_DEFRAG_IPV6 = "m";
          NF_NAT = "m";

          NETFILTER_XTABLES = "y";
          NF_TABLES = lib.mkForce "y";
          NFT_COMPAT = "y";
          NF_TABLES_BRIDGE = "y";
          NETFILTER_XT_TARGET_DSCP = "m";
          NETFILTER_XT_MATCH_DSCP = "m";

          CFG80211 = "y";

          REMOTEPROC = "y";


          SKB_RECYCLER_MULTI_CPU = "y";

        };
      };

      boot = {
        commandLine = [
          "console=ttyMSM0,115200n8"
        ];
      };

      hardware =
        {

          defaultOutput = "uimage";

          # A placeholder, not a fact about the board: the fullSystem image
          # never mounts a root device, and ax6600-rootfs.nix names the real
          # partition. mkDefault so that composition can just say so.
          rootDevice = lib.mkDefault "/dev/mtdblock0";
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
            };
        };
    };
}
