# USB-root system, writable ext4 root instead of the read-only squashfs

#
#   outputs.uimage  (kernel + dtb, cmdline embedded)  -> p1, FAT, as fit.itb
#   outputs.rootfs  (ext4, no partition table)        -> p2, GPT name
#                                                        liminix-root
#   (p3, ext4, volume label liminix-persist)          -> /persist, optional:
#                                                        the root is already
#                                                        writable here
#
# The root is mounted by the kernel, not by preinit

{
  lib,
  ...
}:
{
  imports = [
    ./ax6600-usb.nix
    ./modules/outputs/ext4fs.nix
  ];

  boot.rootfs.mount = "kernel";

  rootfsType = lib.mkForce "ext4";
}
