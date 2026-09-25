# The fullSystem half of the radio's firmware delivery. A fullSystem image has
# no kmodloader and preinit's load_modules() runs before activate creates
# /lib/firmware, so the blobs a driver asks for while probing have to be inside
# the image itself, one file per name - which is exactly what
# boot.initramfs.preloadFirmware takes (an attrsOf package, see
# devices/jdcloud-ax6600/wireless/default.nix for the names).
#
# A mounted-root image imports ./rootfs-firmware.nix instead: it has a real
# filesystem by then and puts the same blobs under /lib/firmware.
{ config, ... }:
{
  boot.initramfs.preloadFirmware = config.wireless.firmwareFiles;
}
