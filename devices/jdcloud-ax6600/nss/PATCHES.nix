# The fork-derived half of the NSS port.
#
# These files exist only in VIKINGYFY/immortalwrt's
# `package/qca-nss/{qca-ssdk,qca-nss-dp}/patches/`: the CLO archives pinned
# in `SOURCES.nix` carry no patches at all, and nothing here is upstream.
# They are therefore fetched from the same pinned fork commit as everything
# else (never copied into this tree), and `sha256` is what proves which
# bytes were applied.
#
# `blob` is the git blob sha of the fork file, the provenance identity:
# identify an input by blob sha, never by file name. Check it with
#   git -C <fork> rev-parse <ref>:<path>
# or the GitHub contents API.
#
# The two lists are ordered as they must be applied. Verified against the
# pinned commits in `SOURCES.nix` with `patch -p1 --fuzz=0`, applied
# cumulatively and in order. Applying a later patch on its own is expected
# to fail: 007 (ssdk) and 007 (nss-dp) both need the ones before them.
{
  ssdk = [
    {
      path = "001-compat-build-flags-common-defines.patch";
      blob = "49a1e74c75dae9f61ce16dae394f58b2ae4aa0a1";
      sha256 = "sha256-getCk1aIa8cbABWKtNPZlf9i95Svjg8PeiZOGQagsBs=";
      note = "keeps the strict toolchain flags working; guards IN_QCA808X_PHY";
    }
    {
      path = "002-compat-phy-mdio-linux-6.18-apis.patch";
      blob = "faae88a518abf33e40d2c8fe74d307139a4f1115";
      sha256 = "sha256-jn7ZxEMgAhltfPPsORhTcJJ4bJcgTaFjIOSpB82vus8=";
      note = "6.18 phydev->eee_cfg.eee_enabled, and a NULL nss_phy_ops deref";
    }
    {
      path = "003-compat-bridge-fdb-ref-paths-linux-6.18.patch";
      blob = "06cd20572a006422790ed405b4fcffc406f81283";
      sha256 = "sha256-GLrUGtUievaVxP+BRxHR0qhwA66g8LB3quh5IujA9NY=";
    }
    {
      path = "004-fix-mht-phy-package-priv.patch";
      blob = "fa014d626375485525802a7026aa0e0b14cf45f8";
      sha256 = "sha256-kebstNQNJy5lrp0JoGDuDdf8kxLRft677nWAqhAaMrY=";
    }
    {
      path = "005-fix-dsa-link-polling-netdev-event.patch";
      blob = "e321a9edde273ec11890256b9664d0bd2850f29e";
      sha256 = "sha256-6HsdNY76v7b1bdf8iaVtLmKkj3W9GiCdx3gag5OqjP8=";
    }
    {
      path = "006-compat-platform-mdio-pinctrl-linux-6.18.patch";
      blob = "f5edadd7b313ad84070e5fe81cbe0c4020f0dd4b";
      sha256 = "sha256-hw4NsO/QcG5kbaKiHCVHS+b+o77N8NHB2niUohYCnXk=";
      note = "mdiobb_read_c22/mdiobb_write_c22 changed signature in 6.18";
    }
    {
      path = "007-cleanup-ref-mib-shell-strscpy.patch";
      blob = "5a31f7df542b8858c4d2b3a59ff6e5303b2c42c0";
      sha256 = "sha256-mud3qRgjjUEujQ2vmR/Bh/Et1Xup87QUjc3aoA8yfDI=";
    }
    {
      path = "008-fix-mac-sw-sync-lock-unwind.patch";
      blob = "a1162b0bf80421a9ac7161f16e57ddaae29aa624";
      sha256 = "sha256-3uf+L3R7Pf1NyBtr61rMwWpVY5QV/Z797j3Cp5wF6fA=";
    }
    {
      path = "009-feature-nss-dp-netdev-mac-sync.patch";
      blob = "b71c7df5b6db39cdb34de9a68c0c0c4c4fb354be";
      sha256 = "sha256-uRIDx+a4LCNkajfrc4iZVYSWvTXXKSh/EsuPfh5oZdo=";
      note = ''
        The one that makes SSDK work with nss-dp at all: netdevs whose
        name does not contain "eth" (lan1, wan) are matched through their
        parent device's "qcom,nss-dp" compatible instead of by name.
      '';
    }
    {
      path = "010-compat-drop-manual-phy-read-status.patch";
      blob = "09500944c1f4d323f6a0103025103b29b215e758";
      sha256 = "sha256-UudsGyU87tgVA1Lq2oB+EpF0+K83w8vDxBRQO/BklYM=";
      note = "in 6.18 phy_read_status is only valid while holding phydev->lock";
    }
    {
      path = "011-fix-sfp-mdio-i2c-linux-6.18.patch";
      blob = "e0367fe559dc365d847cf6c11051e68c0ad48231";
      sha256 = "sha256-We7zLF+a3zaqzWmxx2r+8N7pD1/MhYB+Ba6mAb9scX8=";
      note = "dead here (IN_SFP_PHY is FALSE for CPPE) but kept in order";
    }
    {
      path = "012-mp-set-reference-clock-for-forced-2500mbps.patch";
      blob = "43cb145168ecbf9793969e81591f387fe41769ad";
      sha256 = "sha256-Ri9TeGef27pqzkPU9Aern70vDnMvh+Gj/voblngYA8g=";
    }
  ];

  nssDp = [
    {
      path = "001-compat-linux-6.18-main-netdev-phy-rfs-apis.patch";
      blob = "24c485bee9e7f7598bad2bbb2940e19a181836fc";
      sha256 = "sha256-zlP2baA0Z1wGpSVJlZVlYfftXi4MG20C2zl7LoSd+F8=";
    }
    {
      path = "002-compat-linux-6.18-ethtool-keee.patch";
      blob = "b11490482097482912283b7f961292224d0c2524";
      sha256 = "sha256-wbHQe9oZ8Xq7/DpaXtcMQRGOYjmi0oQdW96waOfdnAI=";
    }
    {
      path = "003-compat-edma-v1-linux-6.18-apis.patch";
      blob = "1dc5ebc417977a41415473f5f19a5da98d688c50";
      sha256 = "sha256-e1VPbSrmbjwiYewW8z4H4BnTfVxEU1q6yx7JM3pnccI=";
    }
    {
      path = "004-fix-qcom-ethtool-helper-symbol-scope.patch";
      blob = "b8f14b3d63ac18fd5a65e949da4ffc145e71d991";
      sha256 = "sha256-ChvE8ZnR+9rrwMn9tu70CJUK+pCvXCVBFYqKxcshA7c=";
    }
    {
      path = "005-fix-switchdev-stp-fdb-roaming.patch";
      blob = "bae9379bc2be644d5da4fa7d102ed1d9e2234596";
      sha256 = "sha256-kuf7HdXOyTjruIHwa7Dg/V7nRAtAnXWTHTUoLCw+BnU=";
      note = "only compiled with CONFIG_NET_SWITCHDEV, which N2 leaves off";
    }
    {
      path = "006-ratelimit-edma-warnings.patch";
      blob = "a2bdba826e3089cbb0e7da54256918d489abfbd5";
      sha256 = "sha256-mzrjdnHTObYjuPG80tCYQjAnwY0T0ifqq15AJadKCPI=";
    }
    {
      path = "007-edma-v1-split-napi-gro.patch";
      blob = "9037316d0ca66334952aa510b01d46e10acd1e6d";
      sha256 = "sha256-k3gqAY8i5ySJYlIMyVClJQYZZFKN+Dse07FfD1alRnY=";
      note = "the 6.18 edma_v1 rx/tx split; needs 001..006 applied first";
    }
  ];
}
