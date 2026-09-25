# The modprobe names an image's module tree loads, as two groups. Both
# `pkgs.liminix.modules.build` (preinit) and `pkgs/kmodloader` (a service) take
# a list of these and let depmod work out the order.
#
# A target whose .ko the image's kernel does not build is a *build failure*,
# not a no-op: modules.build runs `modprobe --show-depends` for every name.
# That is why the two images cannot share one flat list - they do not build
# the same modules:
#
#   * `wired` - conntrack/netfilter plus the NSS drivers. Every image builds
#     these. ax6600-rootfs.nix (and ax6600-usb.nix on top of it) takes this
#     group alone, because neither imports devices/jdcloud-ax6600/wireless
#     yet: delivering the radio's firmware to /lib/firmware is still the open
#     half of N7a, and until it is done those two modules do not exist.
#   * `wireless` - N5's AHB radio. Only the images that import
#     wireless/default.nix build these, since that module is what sets
#     QCOM_Q6V5_WCSS_SEC/ATH11K_AHB in the kernel config.
#
# `all` is both groups, for those fullSystem images (ax6600-nss-ram.nix).
#
# Not here: the nft_* modules. ax6600-nss-ram.nix appends them for the
# masquerade it writes by hand, and the rootfs image gets them from
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

  # N5: the AHB radio. The WCSS remoteproc must be registered before
  # ath11k_ahb probes (the wifi node's qcom,rproc phandle resolves then);
  # depmod sorts that out from the order of these two. The driver is the
  # secure-PIL one, not mainline's qcom_q6v5_wcss.
  wireless = [
    "qcom_q6v5_wcss_sec"
    "ath11k_ahb"
  ];
in
{
  inherit wired wireless;
  all = wired ++ wireless;
}
