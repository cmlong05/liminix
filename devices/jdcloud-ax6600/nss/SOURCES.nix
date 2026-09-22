# What the NSS port fetches from outside this repo (N2 and the N3..N6
# steps after it).
#
# The pin is VIKINGYFY/immortalwrt `main` - the NSS generation, the same
# commit `../SOURCES.nix` pins for the device tree.
#
# The CLO git repositories and one released firmware archive are here,
# because only they are upstream bytes this repo does not keep:
#
#   * `rev` is the pin: a git commit, identified by sha, never by name.
#   * `hash` is the nar hash of the checkout `fetchgit` makes of it. The
#     git URL rather than fetchzip of the `/-/archive/` tarball, because
#     GitLab generates those archives on demand: their bytes, and so a
#     fetchzip hash, drift while the commit does not.
#     Reproduce it without nix-prefetch-git: shallow-fetch the commit,
#     `git archive FETCH_HEAD | tar -x` into an empty directory and run
#     `nix hash path --type sha256 --sri .` - checked against the nssDp
#     pin below, which it reproduces exactly.
#   * `subdir` is the directory of the checkout that is the package, for
#     the one package that is headers rather than a module.
#
# Not here, on purpose:
#   * `package/qca-nss/*/patches/*` - fork-derived 6.18 compat material
#     that exists in no upstream tree, so it is listed, with blob shas,
#     in ../PATCHES.nix and fetched from the fork pin.
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

  # The NSS core itself (N3). Unlike nss-dp, its SoC value is the 64-bit
  # one: `ipq60xx_64` is what the fork's NSS_DRV_SUBTARGET_64 spelling
  # produces, and it is what selects nss_hal/ipq60xx plus
  # -DNSS_MULTI_H2N_DATA_RING_SUPPORT in the driver's own Makefile.
  nssDrv = clo "nss-drv" "6aa14c78e097b29c493ff2fef87e4d35906b2b5a" // {
    date = "2026-01-12";
    qsdk = "13.1";
    hash = "sha256-OqbVrRhnp6z9QJ38vkjEPTgLg5tfdnRu0gp2LU/p85M=";
    license = "Dual BSD/GPL";
    note = ''
      The fork's QSDK_VERSION. The driver compiles its data path against
      the NSS_MEM_PROFILE_* macros, and neither the fork's package nor
      the driver's Makefile defines any of them, so the #else branch in
      nss_hlos_if.h is in force: 4096 connections each for IPv4/IPv6,
      8192 shared maximum, 1984-byte empty buffers. That is the largest
      profile and the one meant for 1 GiB boards - no profile selection
      is needed here, and NSS_MEM_PROFILE_HIGH's ipq807x-only restriction
      (a qosmio nss-packages rule) does not apply to this packaging.
    '';
  };

  # The Enhanced Connection Manager (N4): QSDK 13.1, the same generation as
  # nssDrv above. `subtarget` is the fork's `SoC=` and must match the
  # driver's for the two to be one stack.
  ecm = clo "qca-nss-ecm" "8c7355bf80db40c0a52e1620518d521423dfd7a4" // {
    date = "2026-04-03";
    qsdk = "13.1";
    subtarget = "ipq60xx_64";
    hash = "sha256-IZBsI6ItQ8CzQabxh+DJFgX0orqu8WO2Sm0JtGPbvLA=";
    license = "Dual BSD/GPL";
    note = ''
      The hardware-NAT half: it accelerates connections the kernel has
      already tracked, so it needs CONFIG_NF_CONNTRACK and a front end.
      ECM_FRONT_END_NSS_ENABLE picks the NSS one; the PPE front end needs
      qca-nss-ppe headers this device has no package for.
    '';
  };

  # The client managers (N4 uses only pppoe/, the WAN offload half).
  # 12.5.5, i.e. the same NSS firmware generation as nssDrv/ecm.
  nssClients = clo "nss-clients" "51be82d43ef85079f78aa163d014223b05baa6a2" // {
    date = "2024-09-12";
    qsdk = "12.5.5";
    subtarget = "ipq60xx_64";
    hash = "sha256-bHiGFNu9rxoZEu6vQ7gfxmiAZMtQ0CyWxn4x56IWoYo=";
    license = "Dual BSD/GPL";
    note = ''
      One .ko per manager; the package below builds only pppoe/ - the
      qca-nss-pppoe manager, which watches PPPoE sessions and asks ECM to
      offload them. Every other manager in the tree is left unbuilt.
    '';
  };

  # The conntrack extension ECM's DSCP classifier is compiled against.
  # Not patches: the fork keeps them as plain files/ entries, which 0600-6
  # refers to but does not create. `path` is where each lands in the
  # kernel tree, `sha256` the flat hash, `blob` the fork file.
  kernelNetfilterFiles = [
    {
      path = "net/netfilter/nf_conntrack_dscpremark_ext.c";
      forkPath = "target/linux/qualcommax/files/net/netfilter/nf_conntrack_dscpremark_ext.c";
      blob = "678d27ac9df9c20d441a20730bb75c6b88d1b1fd";
      sha256 = "sha256-Ybk6uYpjpNSzWrQRSPHS6pe4ntRXU3oKf+gBgRYMl1c=";
      license = "ISC";
      note = "EXPORT_SYMBOLs the two accessors ECM calls; linked into nf_conntrack.ko by 0600-6's Makefile hunk";
    }
    {
      path = "include/net/netfilter/nf_conntrack_dscpremark_ext.h";
      forkPath = "target/linux/qualcommax/files/include/net/netfilter/nf_conntrack_dscpremark_ext.h";
      blob = "a0fe7a8654a69633c24d3cf71a173ce97d6724b5";
      sha256 = "sha256-Dv+VqwY8EzUoIkafct9DtlS3ooM4E68A3TSfimkpZAE=";
      license = "ISC";
      note = "ecm_classifier_dscp.c includes it unconditionally, so it cannot be left out even though the feature is behind CONFIG_NF_CONNTRACK_DSCPREMARK_EXT";
    }
  ];

  # The skb recycler's implementation, at the paths 0981-1 compiles them
  # from - the fork's files/ entries, not patches. The same six are listed
  # in the device's ../SOURCES.nix, since that is the copy the kernel build
  # reads; this one is what the module packages see.
  skbRecyclerFiles = [
    {
      path = "net/core/skbuff_recycle.c";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_recycle.c";
      blob = "6312abee73a829719591ea464df7427fd6a10648";
      sha256 = "sha256-VN6B4YI3PXjaPnJLVE1h7VqpynCJiHQQXFEFbS5MzPM=";
      license = "GPL-2.0-only";
      note = "the recycler itself; this is where int_pri is set on RX";
    }
    {
      path = "net/core/skbuff_recycle.h";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_recycle.h";
      blob = "9a4bb877a47538b3840935b3017e4d25653afed2";
      sha256 = "sha256-mQqoi0fORtmtzHNBl68oqbRXpICVF71VM+9vl9gWSMc=";
      license = "GPL-2.0-only";
    }
    {
      path = "net/core/skbuff_notifier.c";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_notifier.c";
      blob = "8c59476db7fe38d641055109d91f59edbf42c0ab";
      sha256 = "sha256-aAdYk3lFLlL6yReDgl35wWuw+xyAVL8CIf53EshZm3Y=";
      license = "GPL-2.0-only";
    }
    {
      path = "net/core/skbuff_notifier.h";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_notifier.h";
      blob = "3d8bfa586fc94b8760fa261742d79a7b1357e8ac";
      sha256 = "sha256-bi8qKA/17P06bEHeA3ROD5VdOKPN1VRb60yYKL/AlwY=";
      license = "GPL-2.0-only";
    }
    {
      path = "net/core/skbuff_debug.c";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_debug.c";
      blob = "50d067592109953ed2504808a152261bcd63e631";
      sha256 = "sha256-jd3Zpo8RExBuiSNQhWF4Ibg90VckGxFW2IcvIagBJyk=";
      license = "GPL-2.0-only";
    }
    {
      path = "net/core/skbuff_debug.h";
      forkPath = "target/linux/qualcommax/files/net/core/skbuff_debug.h";
      blob = "43e37ba43b645e191a527b7a0a337213b98665c6";
      sha256 = "sha256-2/d5Iek9Sen9BfK1GM+DcO39DN0Hq5UKv2QbeE4XTeE=";
      license = "GPL-2.0-only";
    }
  ];

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

  # The NSS core's firmware (N3). QCA ships it nested: the release's
  # .tar.zst holds one archive per platform, and the ipq60xx one - named
  # .tar.bz2 but xz inside, which GNU tar detects by magic - holds a
  # single retail image. The same version OpenWrt's nss-firmware package
  # installs, so the driver's -DNSS_FIRMWARE_VERSION_12_5 matches.
  #
  # ipq60xx is the CP build, which has retail_router0.bin only; the
  # router1 image exists for ipq807x (HK) alone.
  nssFirmware = {
    version = "2025.05.01";
    url = "https://github.com/qosmio/qca-sdk-nss-fw/releases/download/v2025.05.01/nss-firmware-2025.05.01.tar.zst";
    sha256 = "sha256-EKSx5pRw2xUJFcsGNSVDZJS4rk7ruLUOpq2JQILXq7A=";
    # strip-components=1 from the inner archive, as the fork's install does
    root = "nss-firmware-2025.05.01";
    inner = "QCA_Networking_2024.SPF_12.5/ED1/IPQ6018.ATH.12.5/BIN-NSS.FW.12.5-210-CP.R.tar.bz2";
    innerSha256 = "sha256-VtnNTgGYUi+oUqVpKzLQ9zKyt/R9e6aCDz031TI5ofI=";
    member = "BIN-NSS.FW.12.5-210-CP.R/retail_router0.bin";
    # the flat output hash: this is the file's own sha256, which is what
    # proves the extracted bytes
    blobSha256 = "sha256-PHcIlgaBhZok2WSJXf8WbyM23ozKrkup5+OfJyVhzO4=";
    size = 862184;
    license = "QuIC binary, chipset-bound, no reverse engineering (LICENSE.md)";
    note = ''
      The inner archive reports NSS Firmware Version BIN-NSS.FW.12.5-210-CP.R
      (QSDK NHSS 12.5_TARGET_ALL.12.5.2783.2875).
    '';
  };
}
