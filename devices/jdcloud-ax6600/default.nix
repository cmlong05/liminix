{
  system = {
    crossSystem = {
      config = "aarch64-unknown-linux-musl";
    };
  };

  description = ''
    == JDCloud RE-CS-02 (京东云雅典娜 AX6600)
  '';

  module =
    {
      pkgs,
      config,
      lib,
      lim,
      ...
    }:
    let
      sources = import ./SOURCES.nix;
      wifi = sources.wifi;
    in
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
            name = "linux-6.18.49.tar.gz";
            inherit (kernelSource) url sha256;
          };
        version = "6.18.49";
        # Two ports live here, and neither keeps upstream's bytes in this
        # tree: the radio (./wifi/SOURCES.nix) and the ethernet switch
        # (./ether/SOURCES.nix). Both are fetched by URL and hash from the
        # pin in ./SOURCES.nix and applied below.
        #
        # The board dts is upstream's radio variant, so both ports are
        # patch-only: upstream's own device-tree-only wifi-node patch
        # (wifiNodePatch in ./SOURCES.nix) is what lets that dts compile
        # here, and the wifi port's kernel patches then extend the same
        # tree - 0906 before 0907, the order upstream applies them in.
        extraPatchPhase =
          let
            # A driver file's path inside the kernel tree is its upstream
            # path with the target prefix removed - the same layout the
            # old `cp -r ether/src/. .` produced.
            kernelPath = f: lib.removePrefix "target/linux/qualcommax/files/" f.path;
            patchName = p: baseNameOf p.path;
            upstreamFile =
              path: hash:
              pkgs.pkgsBuildBuild.fetchurl {
                name = baseNameOf path;
                inherit hash;
                url = "${sources.upstream.rawBase}/${path}";
              };
            # The wifi port's inputs come from several places; each helper
            # fetches from the pin that owns the entry, so the sha256 in
            # wifi/SOURCES.nix is the whole proof of which revision it is.
            patchFrom =
              base: p:
              pkgs.pkgsBuildBuild.fetchurl {
                name = baseNameOf p.path;
                inherit (p) sha256;
                url = "${base}/${p.path}";
              };
            linuxPatch =
              p:
              pkgs.pkgsBuildBuild.fetchurl {
                name = "${p.commit}.patch";
                inherit (p) sha256;
                url = "${wifi.pins.linux.repo}/commit/${p.commit}.patch";
              };
            wifiNodePatch = upstreamFile sources.wifiNodePatch.path sources.wifiNodePatch.sha256;
            wifi = sources.wifi;
            # Every wifi patch is staged by name first, then applied in the
            # order the manifest lists: files fetched from the store are
            # exactly the pinned revision, and the loop can walk them.
            wifiPatchFiles =
              map (patchFrom sources.upstream.rawBase) wifi.kernel
              ++ map (patchFrom sources.upstream.rawBase) wifi.ath11k
              ++ map linuxPatch wifi.linux;
            # Local patches are named as *paths* (dir + file), not as strings:
            # Nix then copies only those files into the store, so editing a
            # document in wifi/ does not invalidate the kernel.
            wifiLocalFiles = map (f: ./wifi + "/${f.file}") wifi.local;
          in
          ''
          # ── WiFi (see ./wifi/README and ./wifi/SOURCES.nix) ─────────────
          # The board dts is upstream's radio variant, so the node its &wifi
          # reference needs must exist. Device tree only, no driver; applied
          # strictly (no "|| echo") so a failure to apply stops the build.
          patch -p1 --fuzz=3 < ${wifiNodePatch}
          grep -q "wifi: wifi@c000000" arch/arm64/boot/dts/qcom/ipq6018.dtsi \
            || { echo "wifi node missing after patch"; exit 1; }
          # Then the port's own patches. Unlike the ethernet set below, none
          # of these is expected to apply partially: a failure is a real
          # failure, and the .rej check after the last one proves it.
          mkdir -p .wifi-patches
          ${lib.concatMapStrings (p: ''
            install -m644 ${p} .wifi-patches/${baseNameOf p}
          '') (wifiPatchFiles ++ wifiLocalFiles)}
          for p in ${
            lib.concatStringsSep " "
              (map baseNameOf wifiPatchFiles ++ map (f: baseNameOf f.file) wifi.local)
          }; do
            patch -p1 --forward --batch < .wifi-patches/$p \
              || { echo "wifi patch failed: $p"; exit 1; }
          done
          if find . -name '*.rej' | grep -q .; then
            echo "wifi patch phase left reject files:"; find . -name '*.rej'
            exit 1
          fi
          # sanity: what the port is for must be in the tree
          grep -q "qcom,ipq6018-wcss-pil" drivers/remoteproc/qcom_q6v5_wcss.c || exit 1
          grep -q "IPQ6018/m3_fw.mdt" drivers/remoteproc/qcom_q6v5_wcss.c || exit 1
          grep -q MHI_CB_EE_SBL_MODE include/linux/mhi.h || exit 1
          grep -q "wifi@c000000" arch/arm64/boot/dts/qcom/ipq6018.dtsi || exit 1
          # ── Ethernet (see ./ether/README) ────────────────────────────────
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
        # The radio's configuration, applied only when modules/wlan.nix is
        # imported (it sets WLAN = "y", which is what arms this block), so
        # the wired-only images carry none of it and are exactly what they
        # were before this port. The symbols and the reason each is needed
        # are in ./wifi/SOURCES.nix's `kconfig`: the wireless stack itself
        # as modules, which is how the reference builds it, plus the
        # remoteproc/QRTR/PCIe infrastructure the two radios sit on.
        conditionalConfig.WLAN = wifi.kconfig.infra // wifi.kconfig.wlan;
      };

      boot = {
        commandLine = [
          "console=ttyMSM0,115200n8"
        ];
      };

      hardware =
        {
          # The full-system ram image is the only output on this branch
          # (see the Development boot note above).
          defaultOutput = "uimage";
          # Not used by the ram image, which overrides boot.commandLine
          # with no root= at all (see ax6600-lan-ram.nix): this is what a
          # non-initramfs build would put on the kernel command line, and
          # wants revisiting once phase 3 gives the board a rootfs on the
          # eMMC.
          rootDevice = "/dev/mtdblock0";
          loadAddress = lim.parseInt "0x41000000";
          entryPoint = lim.parseInt "0x41000000";
          # Used by the flash image outputs (jffs2/mtdimage), not by the
          # ram image.
          flash.eraseBlockSize = 65536;
          # The board device tree comes from upstream at build time and is
          # used verbatim, wireless included: ./SOURCES.nix holds the pin and
          # the hashes. Nothing upstream wrote is committed to this tree, so
          # following upstream means changing one ref and two hashes in
          # SOURCES.nix.
          #
          # Upstream's board dts is already radio-complete - it enables
          # &pcie_phy, &pcie0 with its QCN9074 child and the AHB &wifi node -
          # so this port adds no device-tree fragment at all. The only
          # device-tree input the wifi side needs is wifiNodePatch, which
          # defines the wifi@c000000 node those references resolve to, and
          # which the wired-only images need too just to compile.
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

              # NB: no wlan* entry here, on purpose. The radio's netdev names
              # are not stable: with two ath11k instances the AHB pdevs and
              # the PCIe radio register in probe order, so the wifi image
              # finds them by phy/device and renames them before anything
              # else touches them (see devices/jdcloud-ax6600/ax6600-wifi.nix).
              # Putting a wlan link here would race that rename.
            };
        };
    };
}
