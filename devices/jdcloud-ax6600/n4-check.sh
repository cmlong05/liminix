#!/bin/sh
# N4 on-device evidence collector for the JDCloud AX6600. Runs on the board
# (busybox ash, no bashisms); read-only except for mounting debugfs when it
# is not mounted, which is what makes the ECM statistics visible.
#
#   ssh root@10.10.10.10 'sh -s' < devices/jdcloud-ax6600/n4-check.sh
#
# The report covers, in order: ECM's front end selection
# (selected_front_end=1; BRINGUP D.8), the NSS core and its firmware, the
# conntrack sysctls (D.6), rx-gro-list on the physical ports (D.9), and
# whether the datapath accelerates.

echo "===== N4 check: $(date) ====="
echo "kernel: $(uname -a)"
echo

echo "--- 1. ECM init (want: selected_front_end=1) ---"
dmesg | grep -iE "ecm|nss front end" | tail -20
echo

echo "--- 1b. CPUs (want 4; nr_cpus=1 was removed in BRINGUP D.12) ---"
echo "online: $(cat /sys/devices/system/cpu/online 2>/dev/null)"
grep -c ^processor /proc/cpuinfo
dmesg | grep -iE "smp: bring|psci|cpu[0-9]+: |Brought up" | tail -8
echo

echo "--- 2. NSS core + firmware ---"
dmesg | grep -iE "nss fw version|nss core|nss-drv|nss_dp|ssdk|ess-switch" | tail -25
echo

echo "--- 3. loaded modules ---"
echo "(expect, in this order: nf_defrag_ipv4 ipv6, nf_conntrack, nf_nat,"
echo " xt_DSCP, xt_dscp, qca_ssdk, qca_nss_dp, qca_nss_drv, qca_nss_pppoe, ecm)"
cat /proc/modules
echo
echo "--- 3b. load-order actually used (want the 11 lines below) ---"
cat /lib/modules/load-order 2>/dev/null
echo
echo "--- 3c. skb recycler (the N4 addition to the data path) ---"
echo "(BRINGUP D.17: if forwarding regressed, this is the first suspect)"
ls /proc/net/skb_recycler/ 2>/dev/null && {
    for f in count max_skbs max_spare_skbs; do
        printf '%-16s %s\n' "$f" "$(cat /proc/net/skb_recycler/$f 2>/dev/null)"
    done
} || echo "no /proc/net/skb_recycler (recycler built out?)"
echo

echo "--- 4. interfaces ---"
if command -v ip >/dev/null 2>&1; then ip -br link; else cat /proc/net/dev; fi
echo
echo "wan speed: $(cat /sys/class/net/wan/speed 2>/dev/null)"
echo

echo "--- 5. conntrack sysctls (want 1 / 65535 / 1) ---"
for f in nf_conntrack_tcp_no_window_check nf_conntrack_max nf_conntrack_events nf_conntrack_count; do
    printf '%-40s %s\n' "$f" "$(cat /proc/sys/net/netfilter/$f 2>/dev/null || echo MISSING)"
done
echo

echo "--- 6. GRO compatibility (want rx-gro-list: off) ---"
if command -v ethtool >/dev/null 2>&1; then
    for i in lan1 lan2 lan3 lan4 wan; do
        printf '%-6s %s\n' "$i" "$(ethtool -k $i 2>/dev/null | grep -E 'rx-gro-list|generic-receive-offload' | tr '\n' ' ')"
    done
else
    echo "no ethtool in this image (BRINGUP D.9). The check it would make is"
    echo "already satisfied by construction: NETIF_F_GRO_FRAGLIST sits in"
    echo "NETIF_F_SOFT_FEATURES_OFF and no nss-dp path sets it. Raw feature"
    echo "words for the record:"
    for i in lan1 lan2 lan3 lan4 wan; do
        printf '%-6s %s\n' "$i" "$(cat /sys/class/net/$i/features 2>/dev/null || echo -)"
    done
fi
echo

echo "--- 7. ECM debugfs ---"
if [ ! -d /sys/kernel/debug/ecm ]; then
    mount -t debugfs none /sys/kernel/debug 2>/dev/null
fi
if [ -d /sys/kernel/debug/ecm ]; then
    echo "entries:"; ls /sys/kernel/debug/ecm/
    echo
    echo "connection_count: $(cat /sys/kernel/debug/ecm/ecm_db/connection_count 2>/dev/null)"
    for d in ecm_db ecm_nss_ipv4 ecm_nss_ipv6 ecm_classifier_default; do
        [ -d /sys/kernel/debug/ecm/$d ] && {
            echo
            echo "== $d"
            for f in /sys/kernel/debug/ecm/$d/*; do
                v=$(cat "$f" 2>/dev/null) || continue
                [ -n "$v" ] && printf '%-45s %s\n' "${f##*/}" "$v"
            done
        }
    done
else
    echo "MISSING: could not mount debugfs or no /sys/kernel/debug/ecm"
    echo "(a missing ecm/ directory means the module never reached debugfs setup)"
fi
echo

echo "--- 8. NSS driver stats (debugfs, if present) ---"
if [ -d /sys/kernel/debug/qca-nss-drv ]; then
    ls /sys/kernel/debug/qca-nss-drv/
    echo
    for f in /sys/kernel/debug/qca-nss-drv/stats/*; do
        [ -f "$f" ] || continue
        echo "== ${f##*/}"; head -20 "$f"
    done
else
    echo "no /sys/kernel/debug/qca-nss-drv"
fi
echo

echo "--- 9. nss procfs ---"
ls /proc/sys/dev/nss/ 2>/dev/null || echo "no /proc/sys/dev/nss"
cat /proc/sys/dev/nss/stats/non_zero_stats 2>/dev/null | head -30
echo

echo "===== end ====="
echo "To measure acceleration: start a large transfer through the WAN,"
echo "then re-read /sys/kernel/debug/ecm/ecm_db/connection_count and the"
echo "ecm_nss_ipv4 counters - they must move. Compare CPU use with ECM"
echo "loaded against ECM unloaded (rmmod ecm)."
echo
echo "--- 10. CPU idle sampling (this image has no top/mpstat) ---"
echo "Run this block while a transfer is in flight, then again after"
echo "'rmmod ecm', and compare the busy figure."
set -- $(awk '/^cpu /{for(i=2;i<=NF;i++) t+=$i; print $5+$6, t}' /proc/stat)
i1=$1; t1=$2
sleep 3
set -- $(awk '/^cpu /{for(i=2;i<=NF;i++) t+=$i; print $5+$6, t}' /proc/stat)
i2=$1; t2=$2
if [ "$t2" -gt "$t1" ]; then
    awk "BEGIN{printf \"busy over %d ticks: %.1f%%\n\", $t2-$t1, 100*(1-($i2-$i1)/($t2-$t1))}"
else
    echo "could not sample /proc/stat"
fi
echo "===== done ====="
