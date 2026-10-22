# USB-root system: the root is a writable ext4 on the stick
#
#   outputs.uimage  (kernel + dtb, cmdline embedded)  -> p1, FAT, as fit.itb
#   outputs.rootfs  (ext4, no partition table)        -> p2, GPT name
#                                                        liminix-root

{
  lib,
  modulesPath,
  pkgs,
  ...
}:
let
  deploymentJson = import ../deployment-json.nix { inherit lib; };
  inherit (deploymentJson) deployment;
in
{
  imports = [
    ./ax6600-rootfs.nix
  ];

  hardware.rootDevice = lib.mkForce deployment.hardware.usbRootDevice;

  kernel.config = {
    PARTITION_ADVANCED = "y";
  };
}
