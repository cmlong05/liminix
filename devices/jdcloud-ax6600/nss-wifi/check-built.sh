#!/bin/sh
set -eu
early=$1
qcn=$2
qca="$early/lib/modules/0.0/qca-nss-drv.ko"
ath="$early/lib/modules/0.0/ath11k.ko"
ath_pci="$qcn/lib/modules/0.0/ath11k_pci.ko"
qrtr_mhi="$qcn/lib/modules/0.0/qrtr-mhi.ko"

modinfo -F parm "$ath" | grep -q '^nss_offload:'
modinfo -F parm "$ath" | grep -q '^frame_mode:'
grep -aq 'nss_wifili_get_context' "$qca"
grep -aq 'nss_wifi_vdev_tx_msg' "$qca"
grep -aq 'ath11k_nss_tx' "$ath"
! grep -qx '0.0/ath11k_pci.ko' "$early/load-order"
! grep -qx '0.0/qrtr-mhi.ko' "$early/load-order"
test -e "$ath_pci"
modinfo "$ath_pci" | grep -q 'pci:v000017CBd00001104'
test -e "$qrtr_mhi"
modinfo "$qrtr_mhi" | grep -q 'mhi:IPCR'
grep -qx '0.0/qrtr-mhi.ko' "$qcn/load-order"
grep -qx '0.0/ath11k_pci.ko' "$qcn/load-order"
