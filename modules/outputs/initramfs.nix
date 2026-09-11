{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    mkEnableOption
    mkOption
    mkIf
    types
    ;
  inherit (pkgs) runCommand;
  cfg = config.boot.initramfs;
  o = config.system.outputs;
in
{
  imports = [ ./system-configuration.nix ];
  options = {
    boot.initramfs = {
      enable = mkEnableOption "initramfs";
      # "full system" mode: embed the entire system (nix store, s6,
      # filesystem contents) into the initramfs itself, so no root
      # device is needed at all. This produces a single-file kernel
      # image containing everything, which can be booted by a U-Boot
      # that loads an initramfs image (e.g. /uimage.html on some
      # boards), or embedded in a FIT image.
      #
      # The command line must NOT contain a root= parameter when this
      # is enabled: preinit treats a missing root device as "we are
      # already running the whole system".
      fullSystem = mkEnableOption "embed the whole system in the initramfs";
    };
    system.outputs = {
      initramfs = mkOption {
        type = types.package;
        internal = true;
        description = ''
          Initramfs image capable of mounting the real root
          filesystem
        '';
      };
      fullinitramfs = mkOption {
        type = types.package;
        internal = true;
        description = ''
          Compressed cpio archive containing the whole system
          (nix store, activate, s6 init), for use as an embedded
          initramfs with no external root device.
        '';
      };
    };
  };
  config = mkIf cfg.enable {
    kernel.config = {
      BLK_DEV_INITRD = "y";
      INITRAMFS_SOURCE =
        builtins.toJSON (
          if cfg.fullSystem then
            "${o.fullinitramfs}"
          else
            "${o.initramfs}"
        );
      #      INITRAMFS_COMPRESSION_LZO = "y";
    };

    system.outputs = {
      initramfs =
        let
          inherit (pkgs.pkgsBuildBuild) gen_init_cpio;
        in
        runCommand "initramfs.cpio" { } ''
          cat << SPECIALS | ${gen_init_cpio}/bin/gen_init_cpio /dev/stdin > $out
          dir /proc 0755 0 0
          dir /dev 0755 0 0
          nod /dev/console 0600 0 0 c 5 1
          dir /target 0755 0 0
          dir /target/persist 0755 0 0
          dir /target/nix 0755 0 0
          file /init ${pkgs.preinit}/bin/preinit 0755 0 0
          SPECIALS
        '';
      fullinitramfs = mkIf cfg.fullSystem (
        runCommand "fullinitramfs.cpio.gz"
          {
            nativeBuildInputs = with pkgs.pkgsBuildBuild; [
              gzip
            ];
          }
          ''
            # Build the cpio from a spec so we can also create /proc,
            # /dev and a /dev/console node: preinit mounts /proc and
            # /dev first thing, and the kernel opens /dev/console for
            # init's stdio - without these preinit fails silently.
            # /init must be preinit (it populates the root filesystem
            # via activate); rootdir's /init symlink (s6 init) is
            # moved to /init.s6.
            (
              cd ${o.rootdir}
              find . -mindepth 1 | sort | while read -r p; do
                p=''${p#./}
                if [ "$p" = "init" ]; then
                  echo "slink /init.s6 $(readlink "$p") 0755 0 0"
                  echo "file /init ${pkgs.preinit}/bin/preinit 0755 0 0"
                elif [ -d "$p" ]; then
                  echo "dir /$p 0755 0 0"
                elif [ -L "$p" ]; then
                  echo "slink /$p $(readlink "$p") 0755 0 0"
                elif [ -f "$p" ]; then
                  echo "file /$p $(pwd)/$p 0755 0 0"
                fi
              done
              echo "dir /proc 0755 0 0"
              echo "dir /dev 0755 0 0"
              echo "nod /dev/console 0600 0 0 c 5 1"
            ) | ${pkgs.pkgsBuildBuild.gen_init_cpio}/bin/gen_init_cpio /dev/stdin | gzip -9 > $out
          ''
      );
    };
  };
}
