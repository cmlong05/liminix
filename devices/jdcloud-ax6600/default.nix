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
    * Ethernet: QCA8075 4x 1G switch + QCA8081 2.5G PHY
    * WiFi:  (QCN9074 5GHz on PCIe0 and the IPQ6018 AHB radio
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
            wirelessPatches = lib.concatMapStrings (
              p:
              "${toString p.fuzz} ${
                pkgs.pkgsBuildBuild.fetchurl {
                  name = baseNameOf p.path;
                  inherit (p) url sha256;
                }
              }\n"
            ) wirelessSources.patches;

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
          in
          ''
          # The wcss remoteproc node is mainline's and 0905 needs it. The
          # wifi@c000000 node is not: 6.18.52 does not have it (checked -
          # no ipq6018 dts file contains the string), the board dts'
          # &wifi override needs the label and ath11k matches on its
          # compatible, so the fork's 0906 below adds it after 0905.
          grep -q "qcom,ipq6018-wcss-pil" arch/arm64/boot/dts/qcom/ipq6018.dtsi \
            || { echo "ipq6018 wcss compatible missing from ipq6018.dtsi"; exit 1; }

          # SOURCES.nix order. 0103 is the one that matters here: it defines
          # nss_region, the label ipq6018-nss.dtsi needs.
          for p in ${lib.concatStringsSep " " kernelPatches} ${lib.concatStringsSep " " nssEcmPatches}; do
            patch -p1 --fuzz=0 < $p || { echo "failed to apply $p"; exit 1; }
          done
          grep -q "nss_region: nss@" arch/arm64/boot/dts/qcom/ipq6018.dtsi \
            || { echo "nss_region missing after 0103"; exit 1; }

          # N5: the wcss remoteproc and the ath11k AHB fixes, in the
          # order wireless/SOURCES.nix lists them, each with the fuzz its
          # group allows. The wcss half applies exactly (fuzz 0): it is
          # OpenWrt's own 6.18 set, and a hunk that stops matching there
          # means the tree moved, which must fail rather than drift.
          while read -r fuzz p; do
            patch -p1 --fuzz="$fuzz" < "$p" || { echo "failed to apply $p"; exit 1; }
          done <<'PATCHES'
          ${wirelessPatches}PATCHES

          # What the radio needs, checked rather than assumed - a fuzzed
          # hunk that landed in the wrong place has to be caught here,
          # because it is a compile error or a silent misbehaviour later.
          # One check per patch that has something to show for itself.
          need() { grep -q "$2" "$1" || { echo "N5: $3 ($1)"; exit 1; }; }
          # `anchor` onward, `window` lines: the sec driver's descriptors
          # and ath11k's hw params are short braced blocks that end in a
          # way not worth matching, and their needles ("WCSS_PAS_ID",
          # "coldboot_cal_mm = false") occur elsewhere in the same file,
          # so a whole-file grep would prove nothing. 25 lines covers
          # those blocks; the dtsi's wcss node and the ipq6018 hw params
          # entry are longer and say so.
          in_entry() {
            awk -v anchor="$2" -v win="$5" \
              'BEGIN { if (win == "") win = 25 } index($0, anchor) { hit = 1 } hit { print; if (++n > win) exit }' "$1" \
              | grep -q "$3" || { echo "N5: $4"; exit 1; }
          }
          wcss=drivers/remoteproc/qcom_q6v5_wcss_sec.c
          dtsi=arch/arm64/boot/dts/qcom/ipq6018.dtsi
          ath=drivers/net/wireless/ath/ath11k

          # the wifi node is still the only one, still points at the Q6,
          # and the node now speaks the sec driver's binding
          test "$(grep -c 'wifi: wifi@c000000' $dtsi || true)" = 1 \
            || { echo "N5: wifi node missing or duplicated"; exit 1; }
          need $dtsi "qcom,rproc = <&q6v5_wcss>" "wifi node lost its remoteproc"
          in_entry $dtsi "q6v5_wcss: remoteproc@cd00000" 'qcom,ipq6018-wcss-sec-pil' "0905: secure WCSS compatible"
          in_entry $dtsi "q6v5_wcss: remoteproc@cd00000" 'firmware-name = "IPQ6018/q6_fw.mdt", "IPQ6018/m3_fw.mdt"' "0905: firmware names in DT"
          in_entry $dtsi "q6v5_wcss: remoteproc@cd00000" 'GCC_QDSS_AT_CLK' "0905 0811: qdss_at clock" 30
          need $dtsi "qcom,smp2p-feature-ssr-ack" "0907: smp2p ssr ack"

          # 0184's only effect here is the TME-L QMP protocol header 0188
          # includes; the driver it also adds stays out of the build.
          test -f include/linux/mailbox/tmelcom-qmp.h \
            || { echo "N5: 0184: 0188's tmelcom-qmp header missing"; exit 1; }
          need drivers/mailbox/Kconfig 'config QCOM_TMEL_QMP_MAILBOX' "0184: mailbox Kconfig symbol"

          # the driver: exists, is registered for ipq6018, and loads the
          # Q6 the secure way with the firmware names it was handed
          test -f $wcss || { echo "N5: 0188: $wcss missing"; exit 1; }
          need drivers/remoteproc/Makefile 'qcom_q6v5_wcss_sec.o' "0188: driver in the Makefile"
          need drivers/remoteproc/Kconfig 'config QCOM_Q6V5_WCSS_SEC' "0188: driver Kconfig symbol"
          in_entry $wcss 'wcss_sec_ipq6018_res_init = {' 'WCSS_PAS_ID' "0812: ipq6018 PAS id"
          in_entry $wcss 'wcss_sec_ipq6018_res_init = {' 'ss_name = "wcnss"' "0812: ipq6018 ssr name"
          need $wcss 'qcom,ipq6018-wcss-sec-pil' "0812: ipq6018 compatible"
          need $wcss 'firmware-name' "0188 0808: firmware from DT"
          need $wcss '"prng"' "0809: PRNG clock"
          need $wcss '"qdss"' "0811: QDSS clock"

          need $ath/qmi.c 'IORESOURCE_UNSET' "101: resource_size misuse"
          need $ath/core.c 'qcom,ath11k-fw-memory-mode' "903: FW memory mode from DT"
          in_entry $ath/core.c 'ATH11K_HW_IPQ6018_HW10' 'coldboot_cal_mm = false' "906: coldboot disabled" 50
          need $ath/hw.h 'ATH11K_REG_TYPE_CE' "910: CE register window"
          need $ath/wmi.c 'WMI_WMM_PARAM_TYPE_LEGACY' "948: WMM param type"
          need $ath/ahb.c 'ce_irq_enable = ath11k_ahb_ce_irqs_enable' "950: AHB CE irq ops"
          need $ath/qmi.c 'target.board_id &= 0xFF' "950: board id masked to 8 bits"
          # both disable calls are in that file already; what 951 adds is
          # a second pair inside the crash-reconfigure path
          in_entry $ath/core.c 'ath11k_core_reconfigure_on_crash' 'ath11k_hif_ce_irq_disable(ab)' "951: interrupts off on crash recovery"

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
