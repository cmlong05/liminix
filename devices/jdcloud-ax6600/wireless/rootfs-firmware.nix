# The mounted-root half of the radio's firmware delivery: images that have a
# real filesystem when the drivers probe (ax6600-rootfs.nix and ax6600-usb.nix)
# get the same blobs as ordinary files under /lib/firmware, at the names the
# kernel asks for, built from the per-name packages in ./default.nix.
#
# Only the tree's top-level directories are symlinked, so /lib/firmware stays a
# directory other modules can add to: modules/wlan.nix puts regulatory.db there
# and ax6600-rootfs.nix the NSS firmware kmodloader's nss-drv asks for while it
# probes. The fullSystem images import ./preload-firmware.nix instead.
{ pkgs, lib, config, ... }:
let
  inherit (pkgs.pseudofile) dir symlink;

  tree = pkgs.runCommand "ax6600-radio-firmware" { } ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: file: "install -D -m 0644 ${file} $out/${name}") config.wireless.firmwareFiles
    )}
  '';
in
{
  filesystem.lib.firmware = dir {
    IPQ6018 = symlink "${tree}/IPQ6018";
    ath11k = symlink "${tree}/ath11k";
  };
}
