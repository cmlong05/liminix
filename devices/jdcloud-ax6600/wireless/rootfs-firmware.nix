# The mounted-root half of the radio's firmware delivery: images that have a
# real filesystem when the drivers probe (ax6600-rootfs.nix and ax6600-usb.nix)
# get the same blobs as ordinary files under /lib/firmware, at the names the
# kernel asks for, built from the per-name packages in ./default.nix.
#
# Only the tree's top-level directories are symlinked, so /lib/firmware stays a
# directory other modules can add to: modules/wlan.nix puts regulatory.db there
# and ax6600-rootfs.nix the NSS firmware kmodloader's nss-drv asks for while it
# probes.
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
  # The same shape as the other modules that add to /lib/firmware, and it has
  # to be: the squashfs builder writes config.filesystem.contents, so the
  # abbreviated `filesystem.lib.firmware = ...` would land in a stray
  # top-level key that nothing reads and the firmware would silently not ship.
  filesystem = dir {
    lib = dir {
      firmware = dir {
        IPQ6018 = symlink "${tree}/IPQ6018";
        ath11k = symlink "${tree}/ath11k";
      };
    };
  };
}
