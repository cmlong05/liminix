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
            wifiNodePatch = upstreamFile sources.wifiNodePatch.path sources.wifiNodePatch.sha256;

            kernelPatch =
              p:
              pkgs.pkgsBuildBuild.fetchurl {
                name = baseNameOf p.path;
                inherit (p) sha256;
                url = "${sources.upstream.rawBase}/${p.path}";
              };
            kernelPatches = map kernelPatch sources.kernelPatches;

            # N4: the NSS kernel side - the fork's patches-6.18/06xx series,
            # one entry per patch in SOURCES.nix, where each has its own
            # note. 0600-1, 0600-2, 0600-6, 0600-7 and 0603-2 are what ECM
            # needs; the rest is kept so the series stays whole. 0600-8 and
            # 0607-1 are deliberately absent (see SOURCES.nix).
            nssEcmPatches = map kernelPatch sources.nssEcmPatches;

            # The N4 kernel-tree files (see nss/SOURCES.nix), installed
            # below before the dtsi tree.
            nssKernelFiles = pkgs.pkgsBuildBuild.callPackage ./nss/kernel-files {
              sources = import ./nss/SOURCES.nix;
            };

            # The NSS-generation dtsi and the ESS constants header, at the
            # paths OpenWrt keeps them in, so the board dtsi's includes
            # resolve as they do upstream.
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
          in
          ''
          # Needs fuzz: its hunk header claims more context than it gives.
          # Every later patch applies exactly, and is applied that way, so
          # context drift fails the build instead of shifting a hunk.
          patch -p1 --fuzz=3 < ${wifiNodePatch}
          grep -q "wifi: wifi@c000000" arch/arm64/boot/dts/qcom/ipq6018.dtsi \
            || { echo "wifi node missing after patch"; exit 1; }

          # SOURCES.nix order. 0103 is the one that matters here: it defines
          # nss_region, the label ipq6018-nss.dtsi needs.
          for p in ${lib.concatStringsSep " " kernelPatches} ${lib.concatStringsSep " " nssEcmPatches}; do
            patch -p1 --fuzz=0 < $p || { echo "failed to apply $p"; exit 1; }
          done
          grep -q "nss_region: nss@" arch/arm64/boot/dts/qcom/ipq6018.dtsi \
            || { echo "nss_region missing after 0103"; exit 1; }

          # N4: the files 0600-6 refers to but does not create (fork files/
          # entries, not patches). Same list, see nss/SOURCES.nix.
          cp -a --no-preserve=mode ${nssKernelFiles}/. .
          test -f include/net/netfilter/nf_conntrack_dscpremark_ext.h \
            || { echo "dscpremark header not installed"; exit 1; }

          # Preserve the files, not the store's read-only directory modes:
          # -a alone would leave the source root unwritable for the .config
          # write the kernel builder does in its configure phase.
          cp -a --no-preserve=mode ${deviceTreeInputs}/. .
          grep -q "ess-switch@3a000000" arch/arm64/boot/dts/qcom/ipq6018-ess.dtsi \
            || { echo "ESS dtsi not installed correctly"; exit 1; }
          test -f include/dt-bindings/net/qcom-ipq-ess.h \
            || { echo "ESS constants header not installed"; exit 1; }
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
          NF_TABLES = "y";
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
          # patch to ECM, and it becomes live again in N5 anyway.
          CFG80211 = "y";

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
