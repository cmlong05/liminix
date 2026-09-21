# What the NSS port fetches from outside this repo (N2 and the N3..N6
# steps after it).
#
# The pin is VIKINGYFY/immortalwrt `main` - the NSS generation, the same
# commit `../SOURCES.nix` pins for the device tree.
#
# Only the three CLO git repositories are here, because only they are
# upstream bytes this repo does not keep:
#
#   * the archive endpoint is what makes a git commit usable from
#     `fetchzip`; the commit inside the archive name is what the pin
#     means, so identify an input by blob sha, never by file name.
#     `sha256` was taken from the downloaded archive with
#     `nix-hash --flat --type sha256 --sri`.
#   * `subdir` is the directory of the archive that is the package, for
#     the one package that is headers rather than a module.
#
# Not here, on purpose:
#   * `qca-ssdk/patches/*` and `qca-nss-dp/patches/*` - fork-derived 6.18
#     compat material that exists in no upstream tree, so it is committed
#     under each package as real patch files.
#   * anything about how the modules are grafted or loaded - that is the
#     device's own code.
#
# Refreshing a pin: edit the commit, rebuild, take the new sha256 from
# fetchzip's error message.
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
    let
      archive = "${repo}-${rev}";
    in
    {
      # `name` is what fetchzip uses for the unpacked tree; `archive` is
      # the file name in the URL. Both spell the pinned commit.
      inherit repo rev archive;
      name = archive;
      url = "https://git.codelinaro.org/clo/qsdk/oss/lklm/${repo}/-/archive/${rev}/${archive}.tar.gz";
    };
in
{
  inherit upstream;

  # The SSDK is the one package here built by its own build system
  # (mk/Makefile with MODULE_TYPE=KSLIB) instead of kbuild.
  ssdk = clo "qca-ssdk" "d9a196497ecee2530722d906e0efe1b7408b6ef6" // {
    date = "2025-11-14";
    sha256 = "sha256-3kGmURf3FNhmsLRsHnlhep9s7G8lMg8TiVT7CK7uRzo=";
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
    sha256 = "sha256-3nJvjny93ZsYv5V8P0exg+zD7cNvySYzFtL8sjPYUzU=";
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
  # archive is an include path.
  nssPhy = clo "qca-nss-phy" "85cb19ff9c3905851b5452c7558cc3d94261be4f" // {
    date = "2026-01-11";
    sha256 = "sha256-xRFxPxJJdo3CPsauedMukUmxIIkjp3BFN92tP5A58QM=";
    license = "Dual BSD/GPL";
    subdir = "nss_ext";
  };
}
