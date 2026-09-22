# The NSS core's firmware blob for ipq60xx (N3).
#
# QCA ships it nested: the release's .tar.zst holds one archive per
# platform, and the ipq60xx one - named .tar.bz2 but xz inside, which is
# why it is decompressed explicitly below rather than left to tar's magic
# detection - holds a single retail image.
#
# Two names are in play and only one of them is what the driver asks for.
# The archive member is retail_router0.bin, which is what OpenWrt installs
# (as /lib/firmware/qca-nss0-retail.bin) and then renames at runtime with
# its hotplug script 10-qca-nss-fw. The driver asks the kernel for
# "qca-nss0.bin" directly (nss_hal/nss_hal.c: NSS_AP0_IMAGE), and Liminix
# has no hotplug fallback (FW_LOADER_USER_HELPER=n), so this package
# produces the file under the requested name.
#
# Flat output: $out *is* the blob, so the pin is the file's own sha256
# rather than a nar hash of a directory containing it. ipq60xx is the CP
# firmware, which has retail_router0.bin only - retail_router1.bin exists
# for ipq807x (HK) alone.
{
  sources,
  pkgsBuildBuild,
}:
let
  inherit (sources) nssFirmware;
  inherit (pkgsBuildBuild) runCommand fetchurl;
in
runCommand "qca-nss0.bin" {
  outputHashMode = "flat";
  outputHash = nssFirmware.blobSha256;
  nativeBuildInputs = with pkgsBuildBuild; [
    xz
    zstd
    gnutar
  ];
} ''
  archive=${fetchurl {
    name = "nss-firmware-${nssFirmware.version}.tar.zst";
    inherit (nssFirmware) url sha256;
  }}

  mkdir -p outer inner
  zstd -dc "$archive" | tar -xf - -C outer
  xz -dc "outer/${nssFirmware.root}/${nssFirmware.inner}" | tar -xf - -C inner
  install -m 0644 "inner/${nssFirmware.member}" $out
''
