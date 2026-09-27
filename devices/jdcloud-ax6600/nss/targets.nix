# The modprobe names an image's module tree loads, as two groups. Both
# `pkgs.liminix.modules.build` (preinit) and `pkgs/kmodloader` (a service) take
# a list of these and let depmod work out the order.
#
# A target whose .ko the image's kernel does not build is a *build failure*,
# not a no-op: modules.build runs `modprobe --show-depends` for every name.
# That is why each target belongs to the group of images that build it:
#
#   * `wired` - conntrack/netfilter plus the NSS drivers. Every image builds
#     these.
#   * `wireless` - N5's AHB radio. Only the images that import
#     wireless/default.nix build these, since that module is what sets
#     QCOM_Q6V5_WCSS_SEC/ATH11K_AHB in the kernel config.
#
# `all` is both groups: ax6600-rootfs.nix (and ax6600-usb.nix on top of it)
# imports wireless/default.nix, so both take it.
#
# Not here: the nft_* modules. The rootfs image gets them from
# modules/firewall's own kmodloader instead.
let
  wired = [
    "nf_conntrack"
    "nf_defrag_ipv4"
    "nf_defrag_ipv6"
    "nf_nat"
    # ECM's classifier reads the conntrack DSCPREMARK extension, the kernel's
    # xt_DSCP target writes it. Without these two targets they ship but never
    # load, so the extension stays zero and those connections are never
    # offloaded.
    "xt_DSCP"
    "xt_dscp"
    "qca-ssdk"
    "qca-nss-dp"
    "qca-nss-drv"
    "qca-nss-pppoe"
    "ecm"
  ];

  wireless = [
    "qcom_q6v5_wcss_sec"
    "ath11k_ahb"
  ];
in
{
  inherit wired wireless;
  all = wired ++ wireless;
}
