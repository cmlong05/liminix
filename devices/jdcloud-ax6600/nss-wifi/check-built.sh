#!/bin/sh
set -eu
modules=$1
qca="$modules/lib/modules/0.0/qca-nss-drv.ko"
ath="$modules/lib/modules/0.0/ath11k.ko"
ath_pci="$modules/lib/modules/0.0/ath11k_pci.ko"

modinfo -F parm "$ath" | grep -q '^nss_offload:'
modinfo -F parm "$ath" | grep -q '^frame_mode:'
grep -aq 'nss_wifili_get_context' "$qca"
grep -aq 'nss_wifi_vdev_tx_msg' "$qca"
grep -aq 'ath11k_nss_tx' "$ath"
test -e "$ath_pci"
modinfo "$ath_pci" | grep -q 'pci:v000017CBd00001104'
