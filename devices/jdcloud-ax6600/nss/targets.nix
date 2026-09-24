# The module load order both the fullSystem and the rootfs image need, as
# modprobe names. `pkgs.liminix.modules.build` (preinit) and `pkgs/kmodloader`
# (a service) both take these and let depmod work out the order.
#
# Not here: the nft_* modules. ax6600-nss-ram.nix appends them for the
# masquerade it writes by hand, and the rootfs image gets them from
# modules/firewall's own kmodloader instead.
[
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
  # N5: the AHB radio. The WCSS remoteproc must be registered before
  # ath11k_ahb probes (the wifi node's qcom,rproc phandle resolves then);
  # depmod sorts that out from the order of these two. The driver is the
  # secure-PIL one, not mainline's qcom_q6v5_wcss.
  "qcom_q6v5_wcss_sec"
  "ath11k_ahb"
]
