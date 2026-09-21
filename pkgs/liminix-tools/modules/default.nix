# The one place that turns a set of `.ko` trees into a loadable module
# tree. Both consumers in the repo go through it:
#
#   * `pkgs/kmodloader` - the oneshot that insmods after s6 is up
#     (TFTP/phram images, wlan.module)
#   * `modules/outputs/initramfs.nix` - the tree `pkgs/preinit` loads
#     before it hands over to s6, which is how a fullSystem image with
#     loadable modules works at all (a kmodloader *service* cannot: it
#     needs kernel.modulesupport, and a fullSystem image embeds the whole
#     rootdir into that same kernel derivation)
#
# Reached as `pkgs.liminix.modules.build pkgs { roots = ...; targets = ...; }`.
# `roots` is a list of trees containing `*.ko` somewhere (the `modulesupport`
# output of a kernel, or a `pkgs/kernel-module` output) and `targets` are
# modprobe names - `qca-ssdk`, not `qca-ssdk.ko`.
#
# Output:
#   lib/modules/0.0/*.ko   plus the modules.* metadata
#   load-order             one path relative to lib/modules per line,
#                          e.g. "0.0/qca-ssdk.ko", dependencies first
#   load.sh / unload.sh    insmod/rmmod those from $O, where $O defaults
#                          to <tree>/lib/modules
{
  lib,
  runCommand,
  pkgsBuildBuild,
  # the caller's business. The defaults are what make partial application
  # work at all: Nix refuses to apply a function whose required arguments
  # are not all present, so `pkgs.liminix.modules.build pkgs` can only
  # return a builder if these are optional.
  roots ? [ ],
  targets ? [ ],
}:
let
  inherit (lib) concatStringsSep;
in
runCommand "kernel-modules"
  {
    nativeBuildInputs = with pkgsBuildBuild; [
      kmod
      cpio
      gawk
    ];
    # Passed as files so that neither the roots nor the target names have
    # to survive shell quoting.
    passAsFile = [
      "moduleRoots"
      "moduleTargets"
    ];
    moduleRoots = concatStringsSep "\n" (map toString roots);
    moduleTargets = concatStringsSep "\n" targets;
  }
  ''
    set -eu
    mkdir -p lib/modules/0.0

    while read -r root; do
      test -n "$root" || continue
      (cd "$root" && find . -name '*.ko' | cpio --quiet --make-directories -p $NIX_BUILD_TOP/lib/modules/0.0)
      # a kernel tree carries modules.* metadata, a module package only
      # its .ko files; Module.symvers is deliberately not copied here
      for meta in "$root"/modules.*; do
        test -e "$meta" && cp "$meta" lib/modules/0.0/ || true
      done < /dev/null
    done < "$moduleRootsPath"

    # the devname map needs a /dev we do not have
    rm -f lib/modules/0.0/modules.devname
    depmod -b . 0.0

    # `modprobe --show-depends` prints "insmod /<top>/lib/modules/0.0/x.ko
    # [args]". Keep the part below lib/modules, so the list stays valid
    # for any tree with the same layout.
    while read -r target; do
      test -n "$target" || continue
      modprobe -S 0.0 -d "$NIX_BUILD_TOP" --show-depends "$target" \
        | awk '$1 == "insmod" {
                 i = index($2, "/lib/modules/")
                 if (i) print substr($2, i + length("/lib/modules/"))
               }'
    done < "$moduleTargetsPath" | awk '!seen[$0]++' > load-order

    test -s load-order || { echo "no modules selected by: ${concatStringsSep " " targets}"; exit 1; }

    {
      echo '#!/bin/sh'
      echo 'O=''${O:-$out/lib/modules}'
      sed 's,^,insmod $O/,g' load-order
    } > load.sh
    {
      echo '#!/bin/sh'
      echo 'O=''${O:-$out/lib/modules}'
      tac load-order | sed 's,^,rmmod $O/,g'
    } > unload.sh
    chmod 0755 load.sh unload.sh
  ''
