# The fork-derived half of the NSS port.
#
# These files exist only in VIKINGYFY/immortalwrt's
# `package/qca-nss/*/patches/`: the CLO archives pinned in `SOURCES.nix`
# carry no patches at all, and nothing here is upstream. They are
# therefore fetched from the same pinned fork commit as everything else
# (never copied into this tree), and `sha256` is what proves which bytes
# were applied.
#
# `blob` is the git blob sha of the fork file, the provenance identity:
# identify an input by blob sha, never by file name. Check it with
#   git -C <fork> rev-parse <ref>:<path>
# or the GitHub contents API.
#
# One list per package, each ordered as it must be applied. Verified
# against the pinned commits in `SOURCES.nix` with `patch -p1 --fuzz=0`,
# applied cumulatively and in order. Applying a later patch on its own is
# expected to fail: the last entry of each list needs the ones before it.
#
# Every list here is the fork's, and complete for the part of each package
# this build compiles. There is no local list any more: the one change that
# used to be ours - renaming ECM's __ppp_is_multilink() reference - is gone,
# because the kernel now exports it (0603-2) as the fork arranges it.
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

  # All twenty, applied cumulatively and in this order (verified with
  # `patch -p1 --fuzz=0` against the nssDrv pin in SOURCES.nix). The
  # driver has no .ko to build without them: 002 replaces a
  # LINUX_VERSION_CODE whitelist ending at 6.6 with a 6.18 window, and
  # its `#error "Check skb recycle code..."` fires on anything else,
  # because the driver hardcodes -DNSS_SKB_REUSE_SUPPORT=1.
  #
  # 001 is the build system: it adds `ccflags-y += $(NSS_DRV_EXTRA_INCLUDES)`
  # (the variable the package passes the nss-dp/ssdk include paths in) and
  # moves ipq806x-only objects - nss_profiler, nss_gmac_stats, tstamp,
  # portid, oam - behind the SoC filter they belong to.
  #
  # 008/009 are features the fork carries for later clients (n2h/ppe flow
  # steering, crypto logs); N3 keeps them because they are part of the
  # same cumulative sequence, and drops the corresponding NSS_DRV_* flags
  # instead (see the package's configFlags).
  nssDrv = [
    {
      path = "001-compat-build-system-export-headers.patch";
      blob = "f08d21244f6c4efc0c08d2feaadb0c48fd1c2191";
      sha256 = "sha256-8Hhhfu3iR+nfIQOGjY3OO6Z2bO9NDde3FtvcCC3QpSM=";
      note = "NSS_DRV_EXTRA_INCLUDES hook + ipq806x-only object list + exports";
    }
    {
      path = "002-compat-core-linux-6.18-apis.patch";
      blob = "a50bcb344cf10d6822e4837e833282ae2114ce12";
      sha256 = "sha256-lxzn/2HoFJ/A7eM/UnQG9ZR378hwKoOP1KTvwW3ZRyU=";
      note = "the 6.18 APIs, and the version window that lets the skb-reuse code compile at all";
    }
    {
      path = "003-compat-hal-dataplane-linux-6.18.patch";
      blob = "f7c202f42fa187bb0eb01dd1da238728fc8b4fbf";
      sha256 = "sha256-CZvCeWP9sjAUwGZeivMdX10posSLERS1HnEszm0WmM4=";
    }
    {
      path = "004-cleanup-edma-eth-rx-igs.patch";
      blob = "b8cde4897ae417eca0a3d4f52b1f9e1f516217df";
      sha256 = "sha256-YNFvZuiZ7dqnjZieVwqfua4kXVVfXX2fxCOYfs4zrt0=";
    }
    {
      path = "005-cleanup-ipv4-ipv6-reassembly.patch";
      blob = "ec674be379268ae00a4ccb06e00bb57a8140ea7f";
      sha256 = "sha256-Wx3DvzX+b2yDp98KHqCCtzGb5nZBTe6/KsH+f1gjgAM=";
    }
    {
      path = "006-compat-bridge-lag-match-mirror-pppoe.patch";
      blob = "007fe456b8e97b07370da63a25893eb9697f8a0b";
      sha256 = "sha256-QrTeNuadHj7hFgU308qLNLkEqy/wUxKeyn615opuEk4=";
    }
    {
      path = "007-cleanup-tunnel-session-offload.patch";
      blob = "6a528219aba1b6cd68058e1e73e2c758c5337baa";
      sha256 = "sha256-HeDtJIp7of32NOC/otvvcdb0LifEg73AYWyP6lfi4pI=";
    }
    {
      path = "008-feature-n2h-dma-ppe-c2c-flow-steering.patch";
      blob = "60266ea78d1f83bf0d501c9c781278c343cb1c96";
      sha256 = "sha256-yQ400pkl5nUTrIzw2fo5/jmDXlj88Zl/NxU38v+4QMc=";
    }
    {
      path = "009-feature-crypto-security-tls-logs-stats.patch";
      blob = "ff8f6ee9dcf609cef4d99a34063249746a3fb1ca";
      sha256 = "sha256-2VwZvoiOy/nxenO3y6hFnxSVSb7Deue04ME1quDVsbs=";
    }
    {
      path = "010-fix-wifi-rmnet-dynamic-interface-logs.patch";
      blob = "304c75fd79b9393b84d78ad5b98b0b8092a5d062";
      sha256 = "sha256-60bQyFL5TcYf8xuhuBKngg8DkKreYou907UqftRnM9M=";
    }
    {
      path = "011-backport-fix-shaper-bounce-lock-unwind.patch";
      blob = "fb046b9407f5a7ab4a7bcde9791f95f2fe50e1a9";
      sha256 = "sha256-LtC5qLMKpgVDkZt5F2xLXPum2e8/ZuNT1B5HJLGBU8M=";
    }
    {
      path = "012-fix-keep-core-stats-with-autoscale-disabled.patch";
      blob = "bee521df66d9b7b221351b29f6f7c93f489fcb9d";
      sha256 = "sha256-xaW8mByqrb6Cet31SodTjkKfvZOIcF+KjJn+0NbOtBo=";
    }
    {
      path = "013-backport-static-analysis-bounds-fixes.patch";
      blob = "06b95734634f2e2add2357a059962780f70e9da2";
      sha256 = "sha256-Zx9NyDcHc9c7dK1Y+S+JGBzlEZ2GsW/TTi65HHfEMKs=";
    }
    {
      path = "014-backport-fix-data-plane-double-unregister.patch";
      blob = "464a10046c5de7aa9691e5cdcb1c4c1afbfbc8b3";
      sha256 = "sha256-XaO3m2VTUfseOtkIfx1He+Y0gCYYdkgmJddVaj4zhNg=";
    }
    {
      path = "015-fix-fraglist-skb-truesize-underaccounting.patch";
      blob = "88f5dca5819a2c0c5f80f1db3bf5fe121f8d1f3f";
      sha256 = "sha256-UkISbdZaybhFGOJKP8kjkWoZpsOIDw0YoPaQYrZkjAY=";
    }
    {
      path = "016-back-fw-empty-buffer-payloads-with-kmalloc.patch";
      blob = "bea2ec6a603a5fdc750383a46cef5024d4f4859f";
      sha256 = "sha256-E2wR7ZDYhwkJ+sbhaUyu1h8aA/s2U49OkZ8oRZPHewE=";
    }
    {
      path = "017-fix-frequency-work-before-core-init.patch";
      blob = "b85c49efefdf465dd0a53461ec44b95a4a49f335";
      sha256 = "sha256-PTiQOLeRc0NH8VAPxpz5mKzXWVeoMgFwW2gYaMz4UYk=";
    }
    {
      path = "018-fix-napi-request-irq-unwind.patch";
      blob = "dd333eb143ebbd680a7341f0bfdc1e2a11db2b6b";
      sha256 = "sha256-/xh1NZFnCrhBogT4Uz9rcLKWLFzB7e2rJae2IVaNLiM=";
    }
    {
      path = "019-fix-n2h-pool-dma-unwind.patch";
      blob = "6f22db1db6a55fd327d8127c30849665dd489350";
      sha256 = "sha256-s76/DDB1MtfHIvo0QQjw7kahwLDs9tvxDrBn0wsIvM4=";
    }
    {
      path = "020-fix-current-frequency-sysctl-read.patch";
      blob = "1f55b850316559e10f8bff2bc5f9cf4be42a7a44";
      sha256 = "sha256-+TeuYQ0lKFbLWch04vdSmhpFJ8ykHHxn0GD1WManLno=";
    }
  ];

  # The ECM manager (N4), its own tree and cumulative order. 001 (build
  # system), 002/003 (classifiers, database) and 005 are what the NSS front
  # end uses; the rest are paths compiled out here, kept because later
  # entries need earlier ones.
  ecm = [
    {
      path = "001-compat-build-module-layout-and-pcc.patch";
      blob = "9071eaf8ef514a36b1d582332f01d8d957cf228f";
      sha256 = "sha256-axhHBJ9D1hwiBuuMPvIUqdu+vnREwTqzR7PI3rRSCek=";
      note = "adds the subdir-ccflags-y $(EXTRA_CFLAGS) hook the Makefile below passes the include paths in, and gates ecm_ae_select/ecm_classifier_pcc behind their variables";
    }
    {
      path = "002-compat-classifiers-interface-linux-6.18.patch";
      blob = "81a89ee2175988596df2279dd9a1bfce4d676c98";
      sha256 = "sha256-1asWL2+vmkVrZomrSI7JYcRLUTtySKy/Bwzuj7gcQqM=";
    }
    {
      path = "003-compat-database-trackers-core-linux-6.18.patch";
      blob = "fae439e0fa2760434c65206dddb71a308de1a8d8";
      sha256 = "sha256-ZAlXjtep0VicQ8Lg9YU8D2/yOEK9BezYx/xllpoa5ZE=";
    }
    {
      path = "004-feature-common-frontends-feature-gates.patch";
      blob = "55e4211d14daba6fbf8f8df19c83a04f306023d0";
      sha256 = "sha256-ZCBqjs4pvLo8mZgvE6a5MPyt/xA2CPzyJEe9HqaS7XU=";
    }
    {
      path = "005-compat-nss-frontends-linux-6.18.patch";
      blob = "78bf6f44315b82d085caddae8e3d05830f526c80";
      sha256 = "sha256-00iUHLS32woGIImAWYiVud4SgiJqjnKymBPYOlYjsuA=";
      note = "the NSS front end itself: tcx_ingress (was miniq_ingress), the exported *_is_conn_limit_reached helpers";
    }
    {
      path = "006-compat-ppe-sfe-frontends-linux-6.18.patch";
      blob = "de16401a6214c0f8e76217ec481c5a18b7168789";
      sha256 = "sha256-/WTIxlzP5lxBgJ1zGhoQ1HZo5dVxUV3hR60flp9h0Jg=";
      note = "compiled out: ECM_FRONT_END_PPE_ENABLE is off here";
    }
    {
      path = "007-fix-pcc-module-refcount-ordering.patch";
      blob = "e43cd0dca28e025931872417a1afedbbcc8bfe43";
      sha256 = "sha256-sihAAPOIevhhiQ1l0xguP/ap8oZgxssAA2HlR0T1yNA=";
      note = "compiled out: mscs/PCC is off here";
    }
    {
      path = "008-backport-sfe-mcast-clear-pending-on-errors.patch";
      blob = "8060996cbfcf1ddeb4564791a1f41824f5f674d2";
      sha256 = "sha256-VoYpX9j+olLDE4fESD/3hrdtnAbOf93geqrOtCtj6Js=";
      note = "compiled out: no SFE front end";
    }
    {
      path = "009-backport-front-end-stop-temp-atomic-refcount.patch";
      blob = "09a074e507eb8417218c88761523f7fa76695f29";
      sha256 = "sha256-g75gMFGVk77XGVMFVryOo75AKgWO9G9jI+ENoduJpR0=";
    }
    {
      path = "010-backport-fdb-event-continue-node-chain.patch";
      blob = "16bf38cab346ab6ca8160dab9cbd97ea193b98db";
      sha256 = "sha256-yYtaYDY2XOShCbQqq4X1Rl+JpP8t6bBnuEvK7Kh8Oi4=";
    }
    {
      path = "011-backport-ovs-multicast-reject-unsupported-flows.patch";
      blob = "fb7cf6f4b905db8d164c550bc52ed2dc83c290a0";
      sha256 = "sha256-r3hUlJxXRggbx/JG3O2+uEvL4hi7vSJRqoAvLZ97g3w=";
    }
    {
      path = "012-backport-ipv4-ipv6-multicast-parity.patch";
      blob = "8b0811bd1eb4d8a32a0f993924bf779d14861312";
      sha256 = "sha256-cNj29ykae1FkgGhIlJqVoFgim4X7OgUrxF7Vr96R/Uo=";
    }
    {
      path = "013-backport-restore-ipv4-ipv6-offload-parity.patch";
      blob = "07bf32644dbdada49104671889c9c0bda74628ba";
      sha256 = "sha256-Mj9HV3SLBrjmoi2ViFchGuDxPzBEAFsFtZr8DXaVCMw=";
    }
    {
      path = "014-backport-declare-in-for-vxlan-gpe.patch";
      blob = "168f42e332377993c5bfc57b476ab03db0fe1fbc";
      sha256 = "sha256-HlHL+TD8texsv740eZxeBkX5R3NMolpssXCjbsUPHsY=";
    }
    {
      path = "015-frontends-nss-respect-bridge-port-vlan-tagging-for-vlan-over-bridge.patch";
      blob = "8343746858aa3d3e2d53a1b668a535ad22cc4fcd";
      sha256 = "sha256-IrQFONyuaFHs2uS44dlryKenRWcquDF344z49zRQRac=";
      note = "the one that makes VLAN-over-bridge offload work with bridge VLAN filtering; harmless without it (the code is behind ECM_BRIDGE_VLAN_FILTERING_ENABLE)";
    }
  ];

  # The client managers (N4): one tree, but only pppoe/ is built, so only
  # the two patches that touch it (and the build system) are listed.
  # Verified cumulatively against the pin in SOURCES.nix.
  nssClients = [
    {
      path = "001-compat-build-system-common-headers.patch";
      blob = "3c93b0120871c88971a54c9b9fa65ea98660c8ed";
      sha256 = "sha256-Sm7I3zNW6MYSafz0YBmhnhk4A9L6H2fO6XtPfEigSdE=";
      note = "the subdir-ccflags-y $(EXTRA_CFLAGS) hook the package below passes includes in through";
    }
    {
      path = "004-compat-l2tp-pppoe-pptp-map-t-linux-6.18.patch";
      blob = "8ccdd465a35c97fb55fd63c7e09acaba38143803";
      sha256 = "sha256-jLbUZLEOR4QSHgiA8XF4uUzmF3QQ6OVTQN0ivjd3nSA=";
      note = "the only hunk this build needs is the MODULE_INFO(description, ...) in pppoe/, without which -Werror fails the module";
    }
  ];
}
