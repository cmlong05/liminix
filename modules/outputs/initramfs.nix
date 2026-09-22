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
      # Loadable modules to put in the image, as a `pkgs/liminix-tools/modules`
      # tree. preinit loads every entry of its load-order through
      # finit_module before it hands over to s6, so a fullSystem image can
      # carry modules even though a kmodloader *service* cannot: that
      # service needs kernel.modulesupport, and fullSystem embeds the
      # whole rootdir into that same kernel derivation.
      #
      # Only meaningful together with fullSystem: the non-fullSystem
      # initramfs is preinit alone and has no module tree to load from.
      preloadModules = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = ''
          A module tree (see `liminix.modules.build`) whose modules
          preinit loads before starting s6. Requires
          `boot.initramfs.fullSystem`.
        '';
      };
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
      # A constant, not the image itself: `kernel.config` is
      # `attrsOf nonEmptyStr` and the option type checks every value, so an
      # entry naming an image built from this same kernel's modulesupport
      # would be forced at type-check time - a cycle. The image goes in
      # through `kernel.initramfsSource` below instead.
      INITRAMFS_SOURCE = "\"\"";
    };

    # The image to embed. It is a plain string option, deliberately not a
    # `kernel.config` entry, and `pkgs/kernel` appends it after
    # olddefconfig (see initramfsSource there).
    kernel.initramfsSource = mkIf cfg.enable (
      if cfg.fullSystem then "${o.fullinitramfs}" else "${o.initramfs}"
    );

    # The flag, not the path: modules-kernel.nix must be able to ask
    # whether an image is embedded without forcing it.
    kernel.embedsInitramfs = mkIf cfg.enable true;

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
              ${
                if cfg.preloadModules == null then
                  ""
                else
                  ''
                    # preinit's load-order names paths below /lib/modules,
                    # so the image must keep that layout. Only .ko and the
                    # modules.* metadata are needed: load.sh/unload.sh want
                    # a shell and insmod, which do not exist this early.
                    # Every directory has to be listed before the files in
                    # it: gen_init_cpio does not imply parents, and the
                    # kernel silently skips an entry whose parent is absent.
                    echo "dir /lib 0755 0 0"
                    (cd ${cfg.preloadModules} && find lib/modules -type d) | while read -r d; do
                      echo "dir /$d 0755 0 0"
                    done
                    echo "file /lib/modules/load-order ${cfg.preloadModules}/load-order 0644 0 0"
                    (cd ${cfg.preloadModules} && find lib/modules -type f) | while read -r f; do
                      case "$f" in
                        *.ko|*/modules.*)
                          echo "file /$f ${cfg.preloadModules}/$f 0644 0 0" ;;
                      esac
                    done
                  ''
              }
            ) | ${pkgs.pkgsBuildBuild.gen_init_cpio}/bin/gen_init_cpio /dev/stdin | gzip -9 > $out
          ''
      );
    };
  };
}
