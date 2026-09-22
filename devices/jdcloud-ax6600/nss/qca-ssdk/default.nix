# qca-ssdk: the ESS switch (ess-switch@3a000000), the UNIPHY/PCS
# instances and the port MAC configuration for the NSS path.
#
# The one package in this stack that does NOT use kbuild: QSDK's
# mk/Makefile is its own build system (MODULE_TYPE=KSLIB, its own
# feature/chip/cflags/obj include sequence), and the fork's OpenWrt
# package drives exactly that. Reimplementing it as a kernel-tree Kbuild
# fragment would mean duplicating its per-chip object list, so the build
# below is a transcription of the fork's `Build/Compile` with the OpenWrt
# variables replaced by ours.
#
# The IN_*/_FEATURE assignments are command-line overrides for
# feature.mk, exactly as the fork passes them; SoC=ipq60xx plus
# CHIP_TYPE=CPPE is its ipq60xx case and implies SUPPORT_CHIP="HPPE CPPE".
{
  lib,
  kernel-module,
  kernel,
  stdenv,
  fetchgit,
  fetchurl,
  bash,
  gnumake,
  sources,
  patches,
  # the kernel's version string. Taken as an argument rather than read off
  # the derivation: that is a multi-output one with an output literally
  # named "version", which collides with `.version`.
  kernelVersion,
  qca-nss-phy,
}:
let
  inherit (sources) ssdk;

  # OpenWrt's swconfig API: mainline 6.18 dropped it with swconfig itself,
  # but SSDK still includes it as <linux/switch.h>. The fork carries both
  # headers under target/linux/generic/files, a tree that mirrors the kernel
  # include layout - its `files/` overlay is what puts them into the kernel
  # it builds - so the same relative path works as the fetch URL and as the
  # destination under our include/ root (blobs 4e6238470d30 and
  # ea449653fafa; the first includes uapi/linux/switch.h, the second).
  #
  # Unused code either way: with SWCONFIG_FEATURE=disable (-DIN_SWCONFIG
  # absent) every switch_dev/switch_val use sits inside an IN_SWCONFIG block
  # - the fork's own patch 007 has already guarded the last unguarded
  # functions in ref_misc.c - and no register_switch()/unregister_switch()
  # reference gets compiled, so the declarations are all that is needed.
  switchHeader =
    path: hash:
    fetchurl {
      name = builtins.replaceStrings [ "/" ] [ "-" ] path;
      url = "${sources.upstream.rawBase}/target/linux/generic/files/${path}";
      inherit hash;
    };
  switch-h = switchHeader "include/linux/switch.h" "sha256-2a5VNZDT2LpUidqF8aU7cjLEa/nlQyQqgs/r3Q+t1Ts=";
  switch-uapi-h = switchHeader "include/uapi/linux/switch.h" "sha256-KPIxegDK5tjZBemeweb2MhiGUlQfuVyII56gdhmEdZY=";

  # The fork's SSDK_MAKE_FLAGS for the ipq60xx branch. cflags.mk reads a
  # few CONFIG_* straight out of the kernel's autoconf; the rest of the
  # feature set is chosen here.
  flags = [
    "SoC=ipq60xx"
    "CHIP_TYPE=CPPE"
    "KVER=${kernelVersion}"
    "GCC_VERSION=${lib.versions.major stdenv.cc.version}"
    "PTP_FEATURE=disable"
    "SWCONFIG_FEATURE=disable"
    "ISISC_ENABLE=disable"
    "IN_QCA803X_PHY=FALSE"
    "IN_QCA808X_PHY=FALSE"
    "IN_MALIBU_PHY=FALSE"
    "IN_MP_PHY=FALSE"
    "IN_AQUANTIA_PHY=TRUE"
    # cflags.mk adds -I<kernel>/drivers/net/phy itself; the nss_phy
    # headers it includes as "qca-nss-phy/..." are qca-nss-phy's.
    "EXTRA_CFLAGS=-I${qca-nss-phy}/include -I${kernel.modulesupport}/drivers/net/phy"
  ];
in
kernel-module {
  name = "qca-ssdk";
  version = ssdk.date;

  src = fetchgit {
    inherit (ssdk) url rev hash name;
  };

  # already fetched from the pinned fork (see ../PATCHES.nix), in
  # the order they must be applied, plus 013, which is ours: it can be
  # deleted once the pin declares ssdk_switch_set_standby_status
  # outside its CONFIG_NET_DSA guard.
  patches = patches ++ [ ./patches/013-fix-standby-status-decl.patch ];

  nativeBuildInputs = [
    bash
    gnumake
  ];

  # mk/Makefile's `modules` target already does `make -C $(SYS_PATH)
  # M=$(MK_PATH) ... modules`; LNX_MAKEOPTS is what the fork leaves empty
  # so that its own KERNEL_MAKEOPTS are not appended.
  #
  # MK_PATH must be given explicitly: it is only assigned inside the
  # Makefile's `ifndef PRJ_PATH`, and we pass PRJ_PATH on the command line.
  buildScript = ''
    # cflags.mk appends -Werror after chipping in its own ccflags-y, so
    # 6.18's -Wmissing-prototypes (ref_port_ctrl.c declares its non-static
    # helpers nowhere) becomes fatal. Appending to the same ccflags-y puts
    # the exception last, on the same word level as -Werror.
    sed -i 's|-DFALLTHROUGH -Werror -Wall|-DFALLTHROUGH -Werror -Wno-error=missing-prototypes -Wall|' mk/cflags.mk

    # ref_uci.c dereferences val->value.ext_val, a member only QSDK's own
    # switch.h had, and its callers (ref_athtag/ref_mapt/ref_pktedit/
    # ref_tunnel/ref_vport) are all behind a non-CPPE chip filter. For this
    # SoC the object is dead weight that cannot compile; the fork's own 6.18
    # patch drops it from OBJ-COMMON the same way.
    sed -i 's|src/ref/ref_uci.o ||' mk/obj.mk

    # MODULE_INC's first -I is $(PRJ_PATH)/include, so the fetched headers
    # go in at the relative paths they have in the kernel tree: SSDK's
    # <linux/switch.h> is found, and the <uapi/linux/switch.h> it includes
    # resolves through the same root.
    mkdir -p include/linux include/uapi/linux
    cp ${switch-h} include/linux/switch.h
    cp ${switch-uapi-h} include/uapi/linux/switch.h

    # Each flag has to stay one shell word: EXTRA_CFLAGS carries two -I's,
    # and a split would hand make the second one as an option of its own.
    make -j$NIX_BUILD_CORES -C mk \
      PRJ_PATH="$PWD" \
      MK_PATH="$PWD/mk" \
      SYS_PATH="${kernel.modulesupport}" \
      MODULE_TYPE=KSLIB \
      LNX_MAKEOPTS="" \
      ${lib.concatStringsSep " " (map lib.escapeShellArg flags)} \
      modules
  '';

  # nss-dp includes <fal/fal_vsi.h> and <fal/fal_port_ctrl.h>, so export
  # the header tree the way upstream's Build/InstallDev does: the whole
  # tree, plus common/ and sal/os/ flattened into the root, which is where
  # the fal headers include "sw.h" and the aos_* headers from.
  postInstall = ''
    mkdir -p $out/include
    cp -a include/. $out/include/
    cp include/common/*.h include/sal/os/*.h include/sal/os/linux/*.h $out/include/
  '';

  meta.description = "QCA SSDK switch/UNIPHY driver for the NSS datapath";
}
