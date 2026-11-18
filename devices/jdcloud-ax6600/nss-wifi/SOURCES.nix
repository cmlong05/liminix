{
  repo = "VIKINGYFY/immortalwrt";
  rev = "683480add1822fdfbbdee77856753d7282d58b71";
  src = {
    url =
      "https://github.com/VIKINGYFY/immortalwrt/archive/683480add1822fdfbbdee77856753d7282d58b71.tar.gz";
    sha256 = "sha256-E4q3aND6XXhWXhfiYM/FwY9gWabj9GY5wvOoyzUIdzE=";
    root = "immortalwrt-683480add1822fdfbbdee77856753d7282d58b71";
  };
  ath11kPath = "package/kernel/mac80211/patches/nss/ath11k";
  subsysPath = "package/kernel/mac80211/patches/nss/subsys";
  apply = {
    subsys = [
      "146-mac80211-enable-TKIP-when-using-encapsulation-offloading.patch"
      "199-001-mac80211-add-nss-support.patch"
      "199-mac80211-fix-xmit-callback-when-hwencap-enable-in-st.patch"
      "203-mac80211-ath11k-fw-dynamic-muedca.patch"
    ];
    ath11k = [
      "033-ath11k-fix-for-peer-memory-corruption.patch"
      "068-ath11k-add-rx-histogram-stats.patch"
      "069-ath11k-add-HE-stats-in-peer-stats.patch"
      "080-ath11k-ethernet-rx-decap-offload.patch"
      "084-ath11k-fix-ul-ofdma-counter-always-zero-in-peer-stat.patch"
      "087-ath11k-fix-ul-ofdma-counter-increamenting-improperly.patch"
      "108-ath11k-enable-ul-ofdma-ru-allocation-in-peer-stats.patch"
      "113-ath11k-add-8023-undecap-support.patch"
      "142-ath11k-adding-support-for-mgmt-frame-stats.patch"
      "181-ath11k-remove-error-on-soc-debugfs-fail.patch"
      "191-ath11k-add-mgmt-and-data-ack-rssi.patch"
      "199-002-ath11k_nss-add-nss-driver-interface.patch"
      "199-003-ath11k-add-nss-support.patch"
      "203-mac80211-ath11k-fw-dynamic-muedca.patch"
      "207-ath11k-Enable-256_512MB-profiles.patch"
      "214-ath11k-qos-null-frame-tx-over-wmi.patch"
    ];
  };
}
