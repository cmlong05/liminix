# qca-nss-dp: the netdev driver (qcom,nss-dp) that sits on the EDMA
# rings and the SSDK switch ports.
#
# SoC=ipq60xx selects nss-dp's edma_v1 data path. That path has no
# NSS-core symbols, which is why N2 gets four LAN ports and a WAN port
# while the NSS firmware is still absent: the A53 runs the datapath.
#
# nss-dp's Makefile compiles nss_dp_switchdev.o only when
# CONFIG_NET_SWITCHDEV is set, and that file needs qca-nss-ppe symbols
# (ppe_drv_*) that do not exist until N3+. N2 therefore leaves
# CONFIG_NET_SWITCHDEV off, and nss_dp_main.c's guarded
# nss_dp_switchdev_setup() call simply is not compiled. What is left
# needs only SSDK's fal_* headers and, at link time, its Module.symvers.
{
  kernel-module,
  kernel,
  stdenv,
  fetchgit,
  sources,
  patches,
  qca-ssdk,
}:
let
  inherit (sources) nssDp;
  arch = stdenv.hostPlatform.linuxArch;
  # The fork's NSS_DP_INCLUDE_DIRS, with its STAGING_DIR entry becoming
  # -I${qca-ssdk}/include here. This is the whole list upstream passes.
  includes = [
    "include"
    "exports"
    "hal/include"
    "hal/dp_ops/include"
    "hal/dp_ops/edma_dp/edma_v1/include"
  ];
in
kernel-module {
  name = "qca-nss-dp";
  version = nssDp.date;

  src = fetchgit {
    inherit (nssDp) url rev hash name;
  };

  # already fetched from the pinned fork (see ../PATCHES.nix), in
  # the order they must be applied
  inherit patches;

  # SSDK's fal_* headers, and its Module.symvers for the link.
  dependencies = [ qca-ssdk ];

  buildScript = ''
    # Upstream's Build/Configure step. The header has to be written before
    # the first compile: the sources include it as "nss_dp_arch.h".
    cp -f hal/soc_ops/ipq60xx/nss_ipq60xx.h exports/nss_dp_arch.h

    make V=1 -j$NIX_BUILD_CORES \
      -C ${kernel.modulesupport} M="$PWD" \
      ARCH=${arch} \
      KBUILD_EXTRA_SYMBOLS="${qca-ssdk}/Module.symvers" \
      SoC=ipq60xx \
      NSS_DP_INCLUDE="${builtins.concatStringsSep " " (map (d: "-I$PWD/${d}") includes)} -I${qca-ssdk}/include" \
      EXTRA_CFLAGS="-I${qca-ssdk}/include" \
      modules
  '';

  # nss-drv includes this package's exports/ as <nss_dp_api_if.h>
  # (nss_data_plane/hal/include/nss_data_plane_hal.h:18) and calls the
  # nss_dp_* symbols it declares, so the headers have to leave the build.
  # This is the fork's Build/InstallDev, minus the staging directory.
  postInstall = ''
    mkdir -p $out/include/qca-nss-dp
    cp -a exports/. $out/include/qca-nss-dp/
  '';

  meta.description = "Qualcomm NSS dataplane ethernet driver";
}
