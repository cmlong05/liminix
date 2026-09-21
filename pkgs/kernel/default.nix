{
  gcc13Stdenv,
  buildPackages,
  writeText,
  lib,

  config,
  src,
  version ? "0",
  extraPatchPhase ? "echo",
  targets ? [ "vmlinux" ],
  rawConfigFile ? null,
  # What to embed as the initramfs, as a raw .config value (usually a
  # quoted path). It is an argument rather than a `config` entry because
  # `kernel.config` is `attrsOf nonEmptyStr` and the option type checks
  # every value: an entry naming an image that is itself built from this
  # kernel's modulesupport would be forced at type-check time, which is a
  # cycle. Null means embed nothing.
  initramfsSource ? null,
}:
let
  stdenv = gcc13Stdenv;
  writeConfig = import ./write-kconfig.nix { inherit lib writeText; };
  # config items from the attrset (used both standalone and as an
  # override layer on top of rawConfigFile)
  attrConfig = writeConfig "kconfig-attr" config;
  kconfigFile =
    if rawConfigFile != null then
      writeText "kconfig" (
        builtins.readFile rawConfigFile + "\n" + builtins.readFile attrConfig
      )
    else
      attrConfig;
  arch = stdenv.hostPlatform.linuxArch;
  targetNames = map baseNameOf targets;
  inherit lib;
  # appended after olddefconfig so it cannot be lost, and outside the config
  # attrset so the option type never sees it (see the argument's comment)
  injectInitramfsSource = lib.optionalString (initramfsSource != null) ''
    echo "CONFIG_INITRAMFS_SOURCE=${initramfsSource}" >> .config
  '';
in
stdenv.mkDerivation rec {
  name = "kernel";
  inherit src extraPatchPhase;
  hardeningDisable = [ "all" ];
  nativeBuildInputs = [
    buildPackages.stdenv.cc
  ]
  ++ (with buildPackages.pkgs; [
    rsync
    bc
    bison
    flex
    pkg-config
    openssl
    # list the outputs explicitly: "ncurses.all" is a list, and nested
    # lists in dependency attributes are deprecated since nixpkgs 26.05
    ncurses.out
    ncurses.dev
    ncurses.man
    perl
  ]);
  CC = "${stdenv.cc.bintools.targetPrefix}gcc";
  HOSTCC = with buildPackages.pkgs; "gcc -I${openssl}/include -I${ncurses}/include";
  HOST_EXTRACFLAGS =
    with buildPackages.pkgs;
    "-I${openssl.dev}/include -L${openssl.out}/lib -L${ncurses.out}/lib";
  PKG_CONFIG_PATH = "./pkgconfig";
  CROSS_COMPILE = stdenv.cc.bintools.targetPrefix;
  ARCH = arch;
  KBUILD_BUILD_HOST = "liminix.builder";

  dontStrip = true;
  dontPatchELF = true;
  outputs = [
    "out"
    "headers"
    "modulesupport"
    "config"
  ]
  ++ targetNames;
  phases = [
    "unpackPhase"
    "butcherPkgconfig"
    "extraPatchPhase"
    "patchPhase"
    "patchScripts"
    "configurePhase"
    "checkConfigurationPhase"
    "buildPhase"
    "installPhase"
  ];

  patches = [
    ./cmdline-cookie.patch
    ./mips-malta-fdt-from-bootloader.patch
  ]
  ++ lib.optional (lib.versionOlder version "5.18.0")
    ./phram-allow-cached-mappings.patch
  ++ lib.optional
    # this is inexact. kernels new enough to contain 2b0996c7646 but
    # not yet the upstream ath9k AHB of_match conversion (that landed
    # in v6.17, so the workaround is only needed for 6.12..6.16)
    ((lib.versionAtLeast version "6.12.0") && (lib.versionOlder version "6.17.0"))
    ./ath9k-ahb-replace-id_table-with-of.patch;

  # this is here to work around what I think is a bug in nixpkgs
  # packaging of ncurses: it installs pkg-config data files which
  # don't produce any -L options when queried with "pkg-config --lib
  # ncurses".  For a regular build you'll never even notice, this only
  # becomes an issue if you do a nix-shell in this derivation and
  # expect "make nconfig" to work.
  butcherPkgconfig = ''
    cp -r ${buildPackages.pkgs.ncurses.dev}/lib/pkgconfig .
    chmod +w pkgconfig pkgconfig/*.pc
    for i in pkgconfig/*.pc; do test -f $i && sed -i 's/^Libs:/Libs: -L''${libdir} /'  $i;done
  '';

  patchScripts = ''
    # Make kexec pass dtb in register when invoking new kernel. The
    # code to do this is already present, but bracketed by UHI_BOOT
    # which we can't enable.
    sed -i arch/mips/kernel/machine_kexec.c -e 's/CONFIG_UHI_BOOT/CONFIG_MIPS/g'

    patchShebangs scripts/
  '';

  configurePhase = ''
    export KBUILD_OUTPUT=`pwd`
    cp ${kconfigFile} .config
    cp ${kconfigFile} .config.orig
    make V=1 olddefconfig
    ${injectInitramfsSource}
    make V=1 olddefconfig
  '';


  checkConfigurationPhase = ''
    echo Checking required config items:
    # Only check the attrset-supplied items: a rawConfigFile (e.g. a
    # full OpenWrt .config) contains items for a possibly different
    # kernel version that olddefconfig legitimately drops.
    if comm -2 -3 <(grep 'CONFIG' ${attrConfig} |sort) <(grep 'CONFIG' .config|sort) |grep '.'    ; then
      echo -e "^^^ Some configuration lost :-(\nPerhaps you have mutually incompatible settings, or have disabled options on which these depend.\n"
      exit 0
    fi
    echo "OK"
  '';

  buildPhase = ''
    make ${lib.concatStringsSep " " targetNames} modules_prepare -j$NIX_BUILD_CORES
  '';

  installPhase = ''
    ${CROSS_COMPILE}strip -d vmlinux
    ${lib.concatStringsSep "\n" (map (f: "cp ${f} \$${baseNameOf f}") targets)}
    cp vmlinux $out
    mkdir -p $headers
    cp -a include .config $headers/
    mkdir -p $modulesupport
    make modules
    cp -a . $modulesupport
    cp .config $config
  '';
}
