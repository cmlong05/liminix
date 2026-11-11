# Build one out-of-tree kernel module against a Liminix kernel.
#
# Liminix kernels have no modules_install and no /lib/modules in the
# rootfs: `pkgs/kernel` copies its whole build tree to the `modulesupport`
# output, and every module is either built into that tree or built here.
# This is the second case, in the shape QSDK/OpenWrt use for it:
#
#   make -C <kernel.modulesupport> M=<src> modules
#
# `modulesupport` is used directly as the kbuild source *and* object tree,
# so there is no second kernel build and no dangling `source` symlink.
# Everything kbuild needs for an external module - include/generated,
# scripts/, Module.symvers - is already in it.
#
# A module package that does not use kbuild (qca-ssdk drives its own
# mk/Makefile) replaces `buildScript`; everything else stays the same.
#
# Output: $out/lib/modules/0.0/*.ko (the layout `pkgs/liminix-tools/modules`
# expects) plus $out/Module.symvers, which the next module in the stack
# passes back in through `dependencies`.
#
# `dependencies` is why the second module needs this at all: nss-dp links
# against symbols exported by qca-ssdk, and the only thing that tells
# modpost about them is qca-ssdk's Module.symvers. With CONFIG_MODVERSIONS
# off (the Liminix default) nothing is CRC-checked at load time, so passing
# the symvers through is enough - both sides simply have no versions to
# match.
{
  lib,
  stdenv,
}:
{
  # supplied by the module package; kernel comes from the device's binding
  # of it (see pkgs/default.nix). No defaults needed on this half: the
  # split above is what leaves these to the caller.
  kernel,
  name,
  src,
  version ? "0",
  patches ? [ ],
  preBuild ? "",
  # Extra `make` arguments: the variables the module's own Makefile reads
  # (SoC=, NSS_DP_INCLUDE=, CHIP_TYPE=, ...)
  extraMakeFlags ? [ ],
  # replaces the kbuild invocation entirely
  buildScript ? null,
  # run through stdenv's postInstall hook, for packages that export more
  # than the module (qca-ssdk also exports its headers)
  postInstall ? "",
  dependencies ? [ ],
  nativeBuildInputs ? [ ],
  meta ? { },
}:
let
  arch = stdenv.hostPlatform.linuxArch;
  symvers = map (d: "${d}/Module.symvers") dependencies;
  makeArgs = [
    "ARCH=${arch}"
  ]
  ++ lib.optionals (symvers != [ ]) [ "KBUILD_EXTRA_SYMBOLS=\"${lib.concatStringsSep " " symvers}\"" ]
  ++ extraMakeFlags;
in
stdenv.mkDerivation {
  inherit
    name
    version
    src
    patches
    preBuild
    postInstall
    nativeBuildInputs
    meta
    ;

  hardeningDisable = [ "all" ];
  # Keep the symbol table modpost just wrote; nothing here needs stripping.
  dontStrip = true;
  dontPatchELF = true;

  KBUILD_BUILD_HOST = "liminix.builder";
  ARCH = arch;
  # Without these kbuild falls back to a bare `gcc`, which does not exist in
  # the cross stdenv. Environment rather than make flags so that a module's
  # own build system (qca-ssdk's mk/Makefile) inherits them too.
  CC = "${stdenv.cc.bintools.targetPrefix}gcc";
  CROSS_COMPILE = stdenv.cc.bintools.targetPrefix;

  buildPhase = ''
    runHook preBuild
    ${
      if buildScript != null then
        buildScript
      else
        ''
          make V=1 -j$NIX_BUILD_CORES \
            -C ${kernel.modulesupport} M="$PWD" ${lib.concatStringsSep " " makeArgs} \
            modules
        ''
    }
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/modules/0.0
    # kbuild may leave the same module name in more than one M= directory.
    # Keeping the first copy is right when they are identical; a differing
    # second one would silently replace it, so refuse instead.
    while IFS= read -r ko; do
      base=${ko##*/}
      if test -e "$out/lib/modules/0.0/$base"; then
        cmp -s "$ko" "$out/lib/modules/0.0/$base" || {
          echo "duplicate module $base: $ko differs from an earlier one" >&2
          exit 1
        }
      else
        install -m 0644 "$ko" "$out/lib/modules/0.0/$base"
      fi
    done < <(find . -name '*.ko')
    test -n "$(find $out/lib/modules/0.0 -name '*.ko' -print -quit)" \
      || { echo "no .ko produced by ${name}"; exit 1; }
    # kbuild writes Module.symvers into the M= directory, which for a
    # buildScript package (qca-ssdk's mk/Makefile) is not $PWD.
    symvers=$(find . -name Module.symvers -print -quit)
    test -n "$symvers" || { echo "no Module.symvers produced by ${name}"; exit 1; }
    install -m 0644 "$symvers" $out/Module.symvers
    runHook postInstall
  '';
}
