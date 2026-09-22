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
    mkdir -p $out/lib/modules/0.0

    # `|| test -n` on both loops: the lists have no trailing newline, and
    # plain `while read` would read the last entry but never visit it.
    while read -r root || test -n "$root"; do
      test -n "$root" || continue
      # a kernel tree keeps its .ko files beside the sources and a module
      # package keeps them under lib/modules, so they are collected flat:
      # 0.0/ is the layout modprobe and preinit look for.
      find "$root" -name '*.ko' -exec cp -t $out/lib/modules/0.0 {} +
      # a kernel tree carries modules.* metadata, a module package only
      # its .ko files; Module.symvers is deliberately not copied here
      for meta in "$root"/modules.*; do
        test -e "$meta" && cp "$meta" $out/lib/modules/0.0/ || true
      done < /dev/null
    done < "$moduleRootsPath"

    # the devname map needs a /dev we do not have
    rm -f $out/lib/modules/0.0/modules.devname
    depmod -b $out 0.0

    # `modprobe --show-depends` prints "insmod /<top>/lib/modules/0.0/x.ko
    # [args]". Keep the part below lib/modules: that is how the tree is
    # found once it is mounted or embedded at /lib/modules.
    while read -r target || test -n "$target"; do
      test -n "$target" || continue
      modprobe -S 0.0 -d "$out" --show-depends "$target" \
        | awk '$1 == "insmod" {
                 i = index($2, "/lib/modules/")
                 if (i) print substr($2, i + length("/lib/modules/"))
               }'
    done < "$moduleTargetsPath" | awk '!seen[$0]++' > $out/load-order

    test -s $out/load-order || { echo "no modules selected by: ${concatStringsSep " " targets}"; exit 1; }

    {
      echo '#!/bin/sh'
      echo 'O=''${O:-'$out'/lib/modules}'
      sed 's,^,insmod $O/,g' $out/load-order
    } > $out/load.sh
    {
      echo '#!/bin/sh'
      echo 'O=''${O:-'$out'/lib/modules}'
      tac $out/load-order | sed 's,^,rmmod $O/,g'
    } > $out/unload.sh
    chmod 0755 $out/load.sh $out/unload.sh
  ''
