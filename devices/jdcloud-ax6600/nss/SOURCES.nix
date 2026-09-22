# What the NSS port fetches from outside this repo (N2 and the N3..N6
# steps after it).
#
# The pin is VIKINGYFY/immortalwrt `main` - the NSS generation, the same
# commit `../SOURCES.nix` pins for the device tree.
#
# Only the three CLO git repositories are here, because only they are
# upstream bytes this repo does not keep:
#
#   * `rev` is the pin: a git commit, identified by sha, never by name.
#   * `hash` is the nar hash of the checkout `fetchgit` makes of it, from
#     `nix-prefetch-git --no-add-path <url> <rev>`. The git URL rather
#     than fetchzip of the `/-/archive/` tarball, because GitLab
#     generates those archives on demand: their bytes, and so a fetchzip
#     hash, drift while the commit does not.
#   * `subdir` is the directory of the checkout that is the package, for
#     the one package that is headers rather than a module.
#
# Not here, on purpose:
#   * `qca-ssdk/patches/*` and `qca-nss-dp/patches/*` - fork-derived 6.18
#     compat material that exists in no upstream tree, so it is committed
#     under each package as real patch files.
#   * anything about how the modules are grafted or loaded - that is the
#     device's own code.
#
# Refreshing a pin: edit the commit, rebuild, take the new hash from
# fetchgit's error message, or prefetch it as above.
let
  # The fork pin. The patches in ../PATCHES.nix are the only inputs read
  # from it (the three modules are CLO's), but they come from the same
  # commit as the device tree in ../SOURCES.nix.
  upstream = {
    repo = "https://github.com/VIKINGYFY/immortalwrt";
    ref = "683480add1822fdfbbdee77856753d7282d58b71";
    rawBase = "https://raw.githubusercontent.com/VIKINGYFY/immortalwrt/683480add1822fdfbbdee77856753d7282d58b71";
  };

  clo =
    repo: rev:
    {
      url = "https://git.codelinaro.org/clo/qsdk/oss/lklm/${repo}.git";
      inherit rev;
      # `name` is what fetchgit calls the checkout; spell the pinned commit.
      name = "${repo}-${rev}";
    };
in
{
  inherit upstream;

  # The SSDK is the one package here built by its own build system
  # (mk/Makefile with MODULE_TYPE=KSLIB) instead of kbuild.
  ssdk = clo "qca-ssdk" "d9a196497ecee2530722d906e0efe1b7408b6ef6" // {
    date = "2025-11-14";
    hash = "sha256-eNWBluOTkfZDqAvqgaBM+0SHPB5AWp1odT8LaLKVvw4=";
    license = "Dual BSD/GPL";
    note = ''
      Built with CHIP_TYPE=CPPE / SoC=ipq60xx, the fork's ipq60xx case.
      CPPE is the one chip type that never registers a DSA switch, so
      CONFIG_NET_DSA is irrelevant here even though the fork's package
      depends on kmod-dsa.
    '';
  };

  nssDp = clo "nss-dp" "d8f802f08fd8ff31057ba58edb20bbe448e7b505" // {
    date = "2026-01-19";
    hash = "sha256-uoZ8U5iNJO0GX2r8C038UXTAMdAsOk2FAV3R3Ngh5Ko=";
    license = "Dual BSD/GPL";
    note = ''
      SoC=ipq60xx selects the edma_v1 data path, which contains no
      NSS-core symbols: this driver runs without qca-nss-drv, so N2 gets
      real netdevs while the NSS firmware is still absent.
    '';
  };

  # SSDK includes "qca-nss-phy/nss_phy.h" and "qca-nss-phy/nss_phy_ptp.h"
  # (hsl_phy.h:18, fal_ptp.h:32). Upstream supplies them as an OpenWrt
  # build-only package installed into STAGING_DIR/usr/include; for us the
  # checkout is an include path.
  nssPhy = clo "qca-nss-phy" "85cb19ff9c3905851b5452c7558cc3d94261be4f" // {
    date = "2026-01-11";
    hash = "sha256-uPzcitOxejtAy2usw2OcRv5tyJq2LyrVcwN4rsJLQw4=";
    license = "Dual BSD/GPL";
    subdir = "nss_ext";
  };
}
