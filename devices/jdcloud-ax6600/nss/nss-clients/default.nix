# The NSS client managers (N4). One CLO tree, one manager per directory,
# built only when its make variable is set, so this package is the pppoe
# one: qca-nss-pppoe.ko, which watches for PPPoE sessions on the WAN port
# and tells ECM to take them over.
#
# Deliberately not the fork's kmod-qca-nss-clients, which builds eighteen
# managers at once; each of those needs another client package or kernel
# feature, and N4 only needs the WAN offload. Its Makefile reads the
# tree's own exports/, but the headers it includes (nss_api_if.h,
# nss_dynamic_interface.h) come from nss-drv, where its undefined symbols
# live too.
{
  lib,
  kernel,
  kernel-module,
  stdenv,
  fetchgit,
  sources,
  patches,
  qca-nss-drv,
}:
let
  inherit (sources) nssClients;
  arch = stdenv.hostPlatform.linuxArch;

  # The fork's EXTRA_CFLAGS minus the unbuilt managers, plus its warning
  # suppressions: the tree adds -Wall -Werror and 6.18 warns where the
  # kernel this was written for did not.
  includes = "-I${qca-nss-drv}/include/qca-nss-drv -Wno-missing-prototypes -Wno-missing-declarations -Wno-empty-body";
in
kernel-module {
  name = "qca-nss-clients";
  version = "${nssClients.qsdk}.${nssClients.date}";

  src = fetchgit {
    inherit (nssClients) url rev hash name;
  };

  # already fetched from the pinned fork (see ../PATCHES.nix), in the
  # order they must be applied
  inherit patches;

  # nss-drv's exports as headers and its Module.symvers for the link.
  dependencies = [ qca-nss-drv ];

  # `pppoe=y` selects pppoe/ in the top Makefile; the rest of the tree
  # stays out. KBUILD_EXTRA_SYMBOLS and EXTRA_CFLAGS carry spaces, so the
  # invocation is written out rather than assembled from extraMakeFlags.
  buildScript = ''
    make V=1 -j$NIX_BUILD_CORES \
      -C ${kernel.modulesupport} M="$PWD" \
      ARCH=${arch} \
      KBUILD_EXTRA_SYMBOLS="${qca-nss-drv}/Module.symvers" \
      EXTRA_CFLAGS="${includes}" \
      SoC=${nssClients.subtarget} \
      pppoe=y \
      modules
  '';

  meta.description = "Qualcomm NSS PPPoE offload manager (ipq60xx)";
}
