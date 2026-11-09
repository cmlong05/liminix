# Generates the kernel-tree checks as calls to the primitives in
# extra-patch-phase.sh, from the `verify` records the SOURCES.nix entries
# carry. A check on a patch lives on that patch's entry, so it is dropped,
# moved or rewritten with it.
{ lib }:
let
  q = lib.escapeShellArg;

  line =
    c:
    {
      grep = "need ${q c.file} ${q c.needle} ${q c.label}";
      entry = "in_entry ${q c.file} ${q c.anchor} ${q c.needle} ${q c.label} ${toString (c.window or 25)}";
      once = "need_once ${q c.file} ${q c.needle} ${q c.label}";
      file = "need_file ${q c.file} ${q c.label}";
    }
    .${c.kind};

  # The checks with no patch to hang on: what the two overlays the phase
  # installs have to have put in the tree.
  installed = [
    {
      kind = "file";
      file = "include/net/netfilter/nf_conntrack_dscpremark_ext.h";
      label = "dscpremark header not installed";
    }
    {
      kind = "grep";
      file = "arch/arm64/boot/dts/qcom/ipq6018-ess.dtsi";
      needle = "ess-switch@3a000000";
      label = "ESS dtsi not installed correctly";
    }
    {
      kind = "file";
      file = "include/dt-bindings/net/qcom-ipq-ess.h";
      label = "ESS constants header not installed";
    }
    {
      kind = "grep";
      file = "drivers/net/wireless/ath/ath11k/Kconfig";
      needle = "config ATH11K_NSS_SUPPORT";
      label = "ath11k NSS support missing";
    }
    {
      kind = "grep";
      file = "net/mac80211/Kconfig";
      needle = "config MAC80211_NSS_SUPPORT";
      label = "mac80211 NSS support missing";
    }
    {
      kind = "grep";
      file = "drivers/net/wireless/ath/ath11k/nss.c";
      needle = "ath11k_nss_tx";
      label = "ath11k NSS data path missing";
    }
    {
      kind = "grep";
      file = "drivers/net/wireless/ath/ath11k/core.c";
      needle = "unsigned int nss_offload = 1;";
      label = "ath11k NSS offload is not the default";
    }
    {
      kind = "entry";
      file = "include/net/mac80211.h";
      anchor = "u8 s1g_long_beacon_period;";
      needle = "bool nss_ap_isolate;";
      label = "mac80211 NSS isolate field outside ieee80211_bss_conf";
      window = 3;
    }
    {
      kind = "grep";
      file = "net/mac80211/tx.c";
      needle = "bool is_eapol;";
      label = "NSS EAPOL offload path missing";
    }
    {
      kind = "grep";
      file = "net/mac80211/tx.c";
      needle = "__ieee80211_subif_start_xmit_8023(skb, skb->dev, flags, ctrl_flags, cookie)";
      label = "control-port flags not preserved for NSS EAPOL";
    }
    {
      kind = "grep";
      file = "drivers/net/wireless/ath/ath11k/wmi.c";
      needle = "ath11k_wmi_qos_null_send";
      label = "QoS Null data frames still enter the NSS data path";
    }
  ];
in
{
  inherit installed;
  lines = checks: lib.concatMapStringsSep "\n" line checks;
}
