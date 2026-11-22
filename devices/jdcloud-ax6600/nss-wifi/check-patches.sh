#!/bin/sh
set -eu
root=$1

test -f "$root/inventory/subsys/199-001-mac80211-add-nss-support.patch"
test -f "$root/inventory/ath11k/199-002-ath11k_nss-add-nss-driver-interface.patch"
test -f "$root/inventory/ath11k/199-003-ath11k-add-nss-support.patch"
test -f "$root/inventory/ath11k/999-920-ath11k-add-kernel-6_12.patch"

grep -q 'config ATH11K_NSS_SUPPORT' \
  "$root/inventory/ath11k/199-002-ath11k_nss-add-nss-driver-interface.patch"
grep -q 'config MAC80211_NSS_SUPPORT' \
  "$root/inventory/subsys/199-001-mac80211-add-nss-support.patch"
grep -q 'ath11k_nss_tx' \
  "$root/inventory/ath11k/199-003-ath11k-add-nss-support.patch"

test "$(find "$root/inventory/subsys" -type f -name '*.patch' | wc -l)" -eq 26
test "$(find "$root/inventory/ath11k" -type f -name '*.patch' | wc -l)" -eq 75
test "$(find "$root/subsys" -type f -name '*.patch' | wc -l)" -eq 4
test "$(find "$root/ath11k" -type f -name '*.patch' | wc -l)" -eq 23

test -f "$root/subsys/199-001-mac80211-add-nss-support.patch"
test -f "$root/ath11k/199-003-ath11k-add-nss-support.patch"
test -f "$root/ath11k/207-ath11k-Enable-256_512MB-profiles.patch"
test -f "$root/ath11k/214-ath11k-qos-null-frame-tx-over-wmi.patch"
test -f "$root/ath11k/237-003-ath11k-allocate-dst-ring-descriptors-from-cacheable-.patch"
test -f "$root/ath11k/237-006-ath11k-Allow-fast-rx-by-bypassing-stats-update.patch"
test -f "$root/ath11k/314-ath11k-Fix-peer-lookup-failure-in-mgmt-tx-completion.patch"
test -f "$root/ath11k/318-ath11k-avoid-stack-corrupt-in-nwifi-undecap.patch"
test -f "$root/ath11k/319-ath11k-fix-double-free-of-peer-rx_tid-during-reo-cmd.patch"
test -f "$root/ath11k/342-ath11k-provide-access-of-the-dma-buffer-back-to-dma-.patch"
test -f "$root/ath11k/999-233-ath11k-Disable-rx_header-tlv-for-2K-SKB.patch"

grep -q 'WMI_QOS_NULL_FRAME_TX_SEND_CMDID' \
  "$root/ath11k/214-ath11k-qos-null-frame-tx-over-wmi.patch"

if find "$root/subsys" "$root/ath11k" -type f -name '*.patch' |
  grep -Eq 'dynamic-vlan|dynamic-VLAN|WDS|AP_VLAN|mesh-offload|Mesh-Fast|mesh-fast|mesh-ping'; then
  echo "forbidden NSS Wi-Fi feature patch selected" >&2
  exit 1
fi

if grep -Rqs '^--- a/backport-include/' "$root/subsys" "$root/ath11k"; then
  echo "backport-only include remains in selected patches" >&2
  exit 1
fi

if grep -Rqs '^--- a/local-symbols' "$root/subsys" "$root/ath11k"; then
  echo "backport-only local-symbols remains in selected patches" >&2
  exit 1
fi

if grep -Rqs -- '---help---' "$root/subsys" "$root/ath11k"; then
  echo "unsupported Kconfig help syntax remains in selected patches" >&2
  exit 1
fi

if grep -q 'int ath11k_dp_service_srng' \
  "$root/ath11k/199-003-ath11k-add-nss-support.patch"; then
  echo "native dp.c hunk was not moved to the compatibility patch" >&2
  exit 1
fi
