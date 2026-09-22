# qca-nss-drv: the NSS core driver (nss@40000000). It loads the uBI32
# firmware into the core's reserved-memory region, brings the core up and
# registers the data-path handlers. N2's nss-dp runs on the A53 without
# it; from here the core can take over.
#
# Two things make this package's build differ from nss-dp's:
#
#   * SoC is `ipq60xx_64`, not `ipq60xx`. The fork derives it as
#     NSS_DRV_SUBTARGET + "_64"; the driver's Makefile branches on it to
#     pick nss_hal/ipq60xx, nss_data_plane/hal/nss_ipq60xx.o and
#     -DNSS_MULTI_H2N_DATA_RING_SUPPORT. The `_64` value is the one whose
#     exports/arch/nss_ipq60xx_64.h macro file is linked in below.
#   * The firmware is a separate package that has to be in the image
#     before this module is loaded; the driver asks for "qca-nss0.bin" by
#     name and fails its probe if it is absent.
#
# Kernel config: nothing extra. The driver needs only core kernel APIs
# (clk, of, dma, procfs/sysctl) and the two dependencies below; the
# NSS_DRV_* options are compile-time feature switches, not Kconfig.
{
  lib,
  kernel,
  kernel-module,
  stdenv,
  fetchgit,
  sources,
  patches,
  qca-ssdk,
  qca-nss-dp,
}:
let
  inherit (sources) nssDrv;
  arch = stdenv.hostPlatform.linuxArch;

  # What the fork passes as NSS_DRV_INCLUDE_DIRS - the nss-dp and ssdk
  # staging include roots. nss-drv includes nss-dp as <nss_dp_api_if.h>
  # (nss_data_plane/hal/include/nss_data_plane_hal.h:18), which is why
  # qca-nss-dp exports its headers, and both are also needed as
  # Module.symvers.
  includes = "-I${qca-nss-dp}/include/qca-nss-dp -I${qca-ssdk}/include";

  # Every feature whose client package is absent from this build, spelled
  # out rather than left to the driver's defaults. It is the fork's own
  # DRV_MAKE_OPTS for a build with no kmod-qca-nss-* clients selected:
  # the FORCE_DISABLED set, the config-only set, and the without-packages
  # set, minus one entry - IPV6.
  #
  # The fork disables IPV6 in this situation and its package selection
  # never reaches that state (kmod-qca-nss-drv-netlink and kmod-qca-nss-ecm
  # both force it back on), but the driver does not actually compile
  # without it: nss_rps_hash_bitmap_cfg_handler() in nss_rps.c is
  #
  #   #if !defined(NSS_DRV_IPV4_ENABLE) || !defined(NSS_DRV_IPV6_ENABLE)
  #           /* whole body is "not supported" */
  #   #else
  #           nss_rps_ipv4_hash_bitmap_cfg(...)
  #   #endif
  #
  # so with either one off, that helper is a static function with no
  # caller and the driver's own -Wall -Werror fails the build. IPV6 stays
  # on here to match what the fork actually builds.
  #
  # What remains on is IPV4, IPV6, ETH_RX and the SoC-selected PPE/EDMA
  # path, plus frequency scaling. N4 turned BRIDGE, PPPOE and VLAN back on:
  # the board dts declares all three, and nss_hal registers a handler for a
  # declared feature only when its NSS_DRV_*_ENABLE is compiled in, so
  # leaving them off would silently drop LAN bridging, the PPPoE WAN and
  # tagged traffic from the offload path. Further entries come back only
  # with the client packages that use them.
  disabledFeatures = [
    "C2C"
    "CAPWAP"
    "CLMAP"
    "DTLS"
    "IPSEC"
    "PVXLAN"
    "QVPN"
    "TLS"
    "WIFI_LEGACY"
    "GRE_REDIR"
    "GRE_TUNNEL"
    "IPV4_REASM"
    "IPV6_REASM"
    "LSO_RX"
    "QRFS"
    "RMNET"
    "SJACK"
    "TRUSTSEC"
    "TRUSTSEC_RX"
    "UDP_ST"
    "WIFI_EXT_VDEV"
    "CRYPTO"
    "GRE"
    "IGS"
    "L2TP"
    "LAG"
    "MAPT"
    "MATCH"
    "MIRROR"
    "PPTP"
    "SHAPER"
    "TUN6RD"
    "TUNIPIP6"
    "VIRT_IF"
    "VXLAN"
    "WIFI_MESH"
    "WIFIOFFLOAD"
  ];

  # The fork's EXTRA_CFLAGS. -DNSS_FIRMWARE_VERSION_12_5 selects the
  # 12.5 message/stat layouts, so it has to agree with the firmware
  # package's version; the -Wno-* entries exist because the driver's own
  # Makefile ends with -Wall -Werror and 6.18 warns where 6.6 did not.
  extraCflags = "${includes} -DNSS_FIRMWARE_VERSION_12_5 -Wno-missing-declarations -Wno-missing-prototypes -Wno-empty-body -Wno-unused-variable";
in
kernel-module {
  name = "qca-nss-drv";
  version = "${nssDrv.qsdk}.${nssDrv.date}";

  src = fetchgit {
    inherit (nssDrv) url rev hash name;
  };

  # already fetched from the pinned fork (see ../PATCHES.nix), in the
  # order they must be applied
  inherit patches;

  # symvers only: nss-dp exports what this driver calls, ssdk what nss-dp
  # needs. The headers come in through NSS_DRV_EXTRA_INCLUDES below.
  dependencies = [
    qca-ssdk
    qca-nss-dp
  ];

  # The fork's Build/Configure. The link is relative on purpose: it
  # resolves to exports/arch/nss_ipq60xx_64.h, which is where the driver
  # keeps its per-arch macro file, and exports/ is on the include path.
  preBuild = ''
    ln -sf arch/nss_ipq60xx_64.h exports/nss_arch.h
  '';

  # The fork's Build/Compile. Written out rather than assembled from
  # `extraMakeFlags` because a make argument cannot carry the space in
  # EXTRA_CFLAGS: the include list has to stay one shell word.
  buildScript = ''
    make V=1 -j$NIX_BUILD_CORES \
      -C ${kernel.modulesupport} M="$PWD" \
      ARCH=${arch} \
      KBUILD_EXTRA_SYMBOLS="${qca-nss-dp}/Module.symvers ${qca-ssdk}/Module.symvers" \
      SoC=ipq60xx_64 \
      NSS_DRV_EXTRA_INCLUDES="${includes}" \
      EXTRA_CFLAGS="${extraCflags}" \
      ${lib.concatMapStringsSep " " (f: "NSS_DRV_${f}_ENABLE=n") disabledFeatures} \
      modules
  '';

  # The fork's Build/InstallDev: ECM (N4) and the client managers include
  # these as <nss_api_if.h>, whose "nss_arch.h" is one of the per-arch
  # files behind a relative symlink, so the whole exports/ tree is copied.
  # nss_ipsecmgr.h is dropped as upstream drops it for this SoC.
  postInstall = ''
    mkdir -p $out/include/qca-nss-drv
    cp -a exports/. $out/include/qca-nss-drv/
    rm -f $out/include/qca-nss-drv/nss_ipsecmgr.h
  '';

  meta.description = "Qualcomm NSS core driver (ipq60xx)";
}
