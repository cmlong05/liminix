# qca-nss-ecm: the Enhanced Connection Manager, the piece that makes this
# "full" NSS. It is not a data-path driver: it watches the kernel's
# connection tracking, decides which connections the NSS front end can
# take over, and pushes them down through nss-drv, so forwarded traffic
# leaves the A53 after the first packet.
#
# What it needs beyond the package itself: CONFIG_NF_CONNTRACK in the
# device kernel config (it registers notifiers and reads nf_conn); nss-drv
# and nss-dp/ssdk for headers and Module.symvers, its NSS front end
# reaching the data plane through nss-dp; and the SoC spelling
# `ipq60xx_64`, which must match the driver's.
#
# The feature set is the fork's qualcommax ECM_MAKE_OPTS for a package
# where only kmod-qca-nss-drv is selected, spelled out rather than left to
# the Makefile defaults: several of those default to "y" and pull in a
# client package this build does not have.
{
  lib,
  kernel,
  kernel-module,
  stdenv,
  fetchgit,
  sources,
  patches,
  qca-nss-drv,
  qca-nss-dp,
  qca-ssdk,
}:
let
  inherit (sources) ecm;
  arch = stdenv.hostPlatform.linuxArch;

  # What the fork passes as EXTRA_CFLAGS: the staging include roots for
  # <nss_api_if.h> and the ssdk headers. 001's
  # `subdir-ccflags-y += $(EXTRA_CFLAGS)` picks them up, so one make-line
  # word is enough - unlike nss-drv, none of it has to survive as a single
  # shell word.
  includes = "-I${qca-nss-drv}/include/qca-nss-drv -I${qca-nss-dp}/include/qca-nss-dp -I${qca-ssdk}/include";

  # The fork's `ifeq ($(CONFIG_TARGET_qualcommax),y)` block, spelled out so
  # nothing depends on a Makefile default staying put: PCC is the one that
  # has to be off, and it is why this list is explicit. Every other
  # ECM_*_ENABLE is left unset - the ones that default to "y" there
  # (advanced stats, AE classifier, ...) are what this build wants, since
  # ECM's own debugfs statistics are the N4 evidence.
  makeFlags = [
    "SoC=${ecm.subtarget}"
    "ECM_NON_PORTED_SUPPORT_ENABLE=y"
    "ECM_INTERFACE_VLAN_ENABLE=y"
    "ECM_CLASSIFIER_MARK_ENABLE=y"
    "ECM_CLASSIFIER_DSCP_ENABLE=y"
    "ECM_CLASSIFIER_PCC_ENABLE=n"
    "ECM_FRONT_END_NSS_ENABLE=y"
    "ECM_IPV6_ENABLE=y"
    "ECM_BRIDGE_VLAN_FILTERING_ENABLE=n"
    "ECM_INTERFACE_PPPOE_ENABLE=y"
    "ECM_INTERFACE_PPP_ENABLE=y"
    "ECM_INTERFACE_IPSEC_ENABLE=n"
    "ECM_INTERFACE_L2TPV2_ENABLE=n"
    "ECM_INTERFACE_PPTP_ENABLE=n"
    "ECM_FRONT_END_PPE_ENABLE=n"
  ];
in
kernel-module {
  name = "qca-nss-ecm";
  version = "${ecm.qsdk}.${ecm.date}";

  src = fetchgit {
    inherit (ecm) url rev hash name;
  };

  # already fetched from the pinned fork (see ../PATCHES.nix), in the
  # order they must be applied
  inherit patches;

  # symvers only: the driver exports what this calls, ssdk what the
  # driver needs. The headers come in through EXTRA_CFLAGS above.
  dependencies = [
    qca-ssdk
    qca-nss-dp
    qca-nss-drv
  ];

  # No `extraMakeFlags`: a make argument cannot carry the spaces in
  # EXTRA_CFLAGS, so the whole invocation is written out.
  buildScript = ''
    make V=1 -j$NIX_BUILD_CORES \
      -C ${kernel.modulesupport} M="$PWD" \
      ARCH=${arch} \
      KBUILD_EXTRA_SYMBOLS="${qca-nss-drv}/Module.symvers ${qca-nss-dp}/Module.symvers ${qca-ssdk}/Module.symvers" \
      EXTRA_CFLAGS="${includes}" \
      ${lib.concatStringsSep " " makeFlags} \
      modules
  '';

  meta.description = "Qualcomm NSS Enhanced Connection Manager (ipq60xx)";
}
