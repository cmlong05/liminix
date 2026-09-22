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
  # the order they must be applied
  inherit patches;

  nativeBuildInputs = [
    bash
    gnumake
  ];

  # mk/Makefile's `modules` target already does `make -C $(SYS_PATH)
  # M=$(MK_PATH) ... modules`; LNX_MAKEOPTS is what the fork leaves empty
  # so that its own KERNEL_MAKEOPTS are not appended.
  buildScript = ''
    make -j$NIX_BUILD_CORES -C mk \
      PRJ_PATH="$PWD" \
      SYS_PATH="${kernel.modulesupport}" \
      MODULE_TYPE=KSLIB \
      LNX_MAKEOPTS="" \
      ${builtins.concatStringsSep " " flags} \
      modules
  '';

  # nss-dp includes <fal/fal_vsi.h> and <fal/fal_port_ctrl.h>, so export
  # the header tree the same way upstream's Build/InstallDev does.
  postInstall = ''
    mkdir -p $out/include
    cp -a include/. $out/include/
  '';

  meta.description = "QCA SSDK switch/UNIPHY driver for the NSS datapath";
}
