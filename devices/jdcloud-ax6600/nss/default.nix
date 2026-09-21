# The QSDK NSS datapath packages for this device (BRINGUP.md N2).
#
# Device-private rather than in the pkgs registry: they are pinned to
# specific commits of specific CLO repos and built with one SoC's
# configuration (CHIP_TYPE=CPPE, SoC=ipq60xx). Only `pkgs/kernel-module`
# and `pkgs/liminix-tools/modules` - the parts that are genuinely general -
# live in pkgs/.
#
# Takes the kernel explicitly because it is `config.system.outputs.kernel`
# (a module-system output), not something the package set has an attribute
# for.
{ pkgs, kernel, version }:
let
  sources = import ./SOURCES.nix;
  recorded = import ./PATCHES.nix;

  # pkgs/kernel-module's second argument is the device's kernel, which the
  # package set has no attribute for. Binding it here leaves a builder each
  # package calls with just the module's own parameters.
  kernel-module = pkgs.kernel-module pkgs kernel;

  # Each recorded fork file as a fixed-output fetch: the sha256 is what
  # proves which bytes get applied (see PATCHES.nix). These are the only
  # inputs taken from the fork; the modules themselves are CLO's.
  patch =
    pkg: p:
    pkgs.pkgsBuildBuild.fetchurl {
      name = p.path;
      url = "${sources.upstream.rawBase}/package/qca-nss/${pkg}/patches/${p.path}";
      inherit (p) sha256;
    };

  qca-nss-phy = pkgs.callPackage ./qca-nss-phy { inherit sources; };
  qca-ssdk = pkgs.callPackage ./qca-ssdk {
    inherit sources kernel qca-nss-phy kernel-module;
    # the derivation has an output literally named "version", so its own
    # version string has to be passed in rather than read off it
    kernelVersion = version;
    patches = map (patch "qca-ssdk") recorded.ssdk;
  };
  qca-nss-dp = pkgs.callPackage ./qca-nss-dp {
    inherit sources kernel kernel-module qca-ssdk;
    patches = map (patch "qca-nss-dp") recorded.nssDp;
  };
in
{
  inherit
    sources
    recorded
    qca-nss-phy
    qca-ssdk
    qca-nss-dp
    ;
}
