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
          # QCA8081 is matched by its PHY ID (ethernet-phy-id004d.d101):
          # in-kernel that is QCA808X_PHY above, and on the NSS path
          # qca-ssdk runs CPPE with IN_AQUANTIA_PHY=TRUE, which is the
          # driver upstream's ipq60xx config covers with this entry.
          AQUANTIA_PHY = "y";

          # MDIO bus driver for the qcom,ipq6018-mdio/ipq4019-mdio
          # node that carries the QCA8075 package and QCA8081 (the
          MDIO_IPQ4019 = "y";
          OF_MDIO = "y";

          # Kernel facilities qca-ssdk needs and nothing else on this board
          # asks for: I2C, because it compiles its SFP EEPROM bridge
          # unconditionally, and SMEM, because ssdk_plat.c reads the SoC id
          # through qcom_smem_get_soc_id. SMEM needs the HWSPINLOCK framework
          # to build and the tcsr-mutex provider (HWSPINLOCK_QCOM) to probe
          # at all: without the provider, qcom-smem stays deferred and every
          # socid read fails, which makes ssdk_uniphy_valid_check() report
          # the UNIPHYs as absent.
          I2C = "y";
          HWSPINLOCK = "y";
          HWSPINLOCK_QCOM = "y";
          QCOM_SMEM = "y";

          # --- netfilter (N4) ---
          # ECM is built on conntrack (notifiers on it, the connections it
          # tracks), and N2/N3 had no netfilter at all. PPPOE is the other
          # half: modules/ppp turns on PPP but not PPPOE, and the offload
          # client calls pppoe_channel_addressing_get() from 0600-2.
          PPPOE = "y";

          # ECM's VLAN support includes net/8021q/vlan.h, so the 8021q core
          # has to be in the kernel. Unset, vlan.h does not compile; `=m`,
          # ecm.ko links against vlan_dev_* which then live in vlan.ko, so
          # `=y` puts them in vmlinux. No tagged ports today, but the
          # bridge ECM offloads has to be VLAN-aware for N5/N7.
          VLAN_8021Q = "y";

          # NETFILTER has no default, so without that line the whole menu is
          # invisible and olddefconfig drops every option under it. The
          # conntrack modules stay `=m`, loaded by preloadModules.
          # DSCPREMARK_EXT is what 0600-6 adds; the two xt_DSCP symbols are
          # what a DSCP rule needs to reach ECM.
          NETFILTER = "y";
          NETFILTER_ADVANCED = "y";
          NF_CONNTRACK = "m";
          NF_CONNTRACK_EVENTS = "y";
          # ECM reads nf_conn->mark, which exists only under this; OpenWrt
          # gets it through kmod-nf-conntrack, here it has to be named.
          NF_CONNTRACK_MARK = "y";
          NF_CONNTRACK_DSCPREMARK_EXT = "y";
          NF_DEFRAG_IPV4 = "m";
          NF_DEFRAG_IPV6 = "m";
          NF_NAT = "m";
          # The xt_DSCP target needs an xtables path
          # (`IP_NF_MANGLE || IP6_NF_MANGLE || NFT_COMPAT`); the nftables one
          # is taken, so no iptables-legacy core is added. Without these,
          # olddefconfig drops both symbols.
          NETFILTER_XTABLES = "y";
          # Forced because modules/firewall asks for `m`: this must stay
          # built-in, or NFT_COMPAT (below) and NF_TABLES_BRIDGE (further
          # down) lose their `y` and olddefconfig drops them. The rootfs
          # composition is the one that imports that module.
          NF_TABLES = lib.mkForce "y";
          NFT_COMPAT = "y";
          # ECM registers a NFPROTO_BRIDGE/NF_BR_POST_ROUTING hook of its
          # own; 6.18 gates that whole family behind NETFILTER_FAMILY_BRIDGE,
          # which only BRIDGE_NETFILTER, NF_TABLES_BRIDGE and ebtables
          # select. Left unset, the registration WARNs in
          # nf_hook_entry_head() and returns -EINVAL, which aborts ECM's
          # init. The hook is called by the bridge core (br_forward_finish),
          # not by br_netfilter, and the fork's generic config gets the
          # symbol from NF_TABLES_BRIDGE=y with BRIDGE_NETFILTER off.
          NF_TABLES_BRIDGE = "y";
          # `=m`, not `=y`, and forced: 0600-6 makes these call
          # nf_conntrack_dscpremark_ext_set_dscp_rule_valid(), defined in an
          # object of nf_conntrack's own, and nf_conntrack is `=m` here. A
          # built-in caller cannot reference a module's symbol.
          NETFILTER_XT_TARGET_DSCP = "m";
          NETFILTER_XT_MATCH_DSCP = "m";

          # --- cfg80211 (N4) ---
          # Not for the radio (wireless is N5): ECM's VAP test reads
          # net_device->ieee80211_ptr, which struct net_device carries only
          # under `#if IS_ENABLED(CONFIG_CFG80211)`. Preferred over a local
          # patch to ECM, and it becomes live again in N5 anyway, where
          # wireless/default.nix imports modules/wlan.nix - which asks for
          # CFG80211 as a module and is overridden back to `y` there.
          CFG80211 = "y";

          # --- remoteproc (N5) ---
          # ATH11K_AHB depends on this (Kconfig), and the Q6 the AHB radio
          # runs on is a remoteproc. The driver itself is not mainline
          # here: see wireless/SOURCES.nix.
          REMOTEPROC = "y";

          # --- skb recycler (N4) ---
          # 0981-1 brings QCA's skb recycler in (Kconfig defaults it to y),
          # which is where struct sk_buff gets int_pri, the tag ECM reads;
          # the alternative was a local patch substituting 0 for the field.
          # MULTI_CPU is not optional: the fork's skbuff_recycle.c guards
          # skb_recycler_max_spare_skbs_core with it at the top but uses it
          # unguarded further down, so the kernel does not compile without
          # it.
          SKB_RECYCLER_MULTI_CPU = "y";

        };
        # NB: the wireless conditionalConfig block (WLAN -> ATH11K /
        # QCOM_Q6V5_WCSS ...) is not here. It lives in wireless/default.nix,
        # which the N5 image imports; a build that does not import it
        # compiles no wireless stack at all.
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
              # upstreamTree: the board dts and the dtsi it includes. The
              # kernel tree: ipq6018.dtsi plus the NSS-generation dtsi the
              # kernel phase installs there, so the board dtsi's
              # same-directory includes resolve. dt-bindings come from
              # `${kernel.headers}/include`, appended by outputs.nix.
              includePaths = [
                upstreamTree
                "${config.system.outputs.kernel.modulesupport}/arch/arm64/boot/dts/qcom/"
              ];
              # Our complete delta from upstream's tree, as overrides rather
              # than patches so every upstream file stays byte for byte.
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
