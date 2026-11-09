# NSS Wi-Fi Offload Design

## Goal

Enable Qualcomm NSS Wi-Fi offload for the IPQ6018 AHB radios on
`devices/jdcloud-ax6600`, starting with the normal AP data path used by
Wi-Fi clients and bridged LAN traffic.

## Scope

- Enable `WIFIOFFLOAD` in `qca-nss-drv`.
- Add the upstream ath11k/mac80211 NSS support to the local 6.18.57 kernel.
- Load ath11k with `nss_offload=1 frame_mode=2`.
- Keep the control path on host mac80211; only eligible data flows are
  offloaded.
- Verify coexistence with sing-box's TUN, `auto_route`, and
  `auto_redirect`.

## Non-goals

- NSS mesh, WDS, dynamic VLAN, AP_VLAN, or 802.11s offload.
- QCN9024/5.2 GHz bring-up.
- Replacing sing-box with an NSS implementation.
- Raising the local iperf3-to-router result to the 1200.9 Mbit/s PHY rate.
  That rate is a PHY rate, not a TCP result.

## Source of Truth

Use `VIKINGYFY/immortalwrt` commit
`683480add1822fdfbbdee77856753d7282d58b71`.

The complete source archive is fetched at build time:

- URL:
  `https://github.com/VIKINGYFY/immortalwrt/archive/683480add1822fdfbbdee77856753d7282d58b71.tar.gz`
- SHA-256:
  `sha256-E4q3aND6XXhWXhfiYM/FwY9gWabj9GY5wvOoyzUIdzE=`

Only `package/kernel/mac80211/patches/nss/subsys` and
`package/kernel/mac80211/patches/nss/ath11k` are consumed. The ath10k set is
not applicable to this device.

## Architecture

The local build compiles ath11k directly from the Linux source tree, while the
reference OpenWrt package compiles it through mac80211 backports. The NSS patch
series therefore needs a mechanical native-kernel adaptation:

- `CPTCFG_*` names are converted to `CONFIG_*`.
- Patches are applied in upstream order: all `subsys` patches, then all
  `ath11k` patches.
- Any hunk that cannot be adapted mechanically is recorded as a separate
  compatibility patch; upstream source is not copied or edited in-tree.

`qca-nss-drv` builds after the kernel and exports the Wi-Fi data API. ath11k
is built first and intentionally retains unresolved module symbols until load.
The module loader loads `qca-nss-drv` before ath11k and rejects the load if the
required NSS symbols are absent.

## Runtime Behavior

- ath11k parameters: `nss_offload=1`, `frame_mode=2`.
- `ATH11K_NSS_SUPPORT=y`.
- `MAC80211_NSS_SUPPORT=y`.
- `ATH11K_MEM_PROFILE_512M=y`.
- Mesh/WDS/dynamic-VLAN support remains disabled.
- Normal forwarded traffic may take the NSS path.
- Traffic redirected into `sing-box0` remains on the Linux userspace path.

## sing-box Coexistence

sing-box `auto_redirect` uses input/output/reset marks `0x2023`, `0x2024`, and
`0x2025`. ECM's mark-classifier hook exists, but the current image neither
registers a callback nor enables that classifier at runtime.

The design therefore requires two independent checks:

1. Proxied traffic must enter `sing-box0` and must not appear in ECM accelerated
   connection counts.
2. Deliberately excluded/direct LAN-to-WAN traffic must be eligible for NSS
   acceleration.

If proxied traffic is accelerated, add a small ECM mark guard module that
registers `ecm_classifier_mark_register_callbacks()` and returns
`ECM_CLASSIFIER_MARK_RESULT_NOT_YET` for the sing-box marks, preventing
acceleration. Do not silently fall back to disabling all NSS acceleration.

## Rollback

Rollback has two levels:

- Runtime: load ath11k with `nss_offload=0`; mac80211 returns to the software
  data path without changing the image.
- Image: revert the device changes and rebuild. The last known-good image is
  retained; no partition or ART data is modified by this work.

## Acceptance Criteria

- The image contains `WIFIOFFLOAD` support in `qca-nss-drv.ko`.
- The image contains `ATH11K_NSS_SUPPORT` code in `ath11k.ko`.
- Load order is exactly `qca-nss-drv` before `ath11k`.
- `/sys/module/ath11k/parameters/nss_offload` reads `Y`.
- `/sys/module/ath11k/parameters/frame_mode` reads `2`.
- 2.4 GHz and 5.8 GHz APs associate and pass traffic.
- A Wi-Fi client to wired-LAN iperf3 test shows NSS acceleration and does not
  regress relative to the pre-offload baseline.
- iPhone-to-router-local traffic remains functional; improvement is not a
  required acceptance criterion because TCP terminates on the host CPU.
- sing-box proxied traffic still selects the proxy path, and direct traffic
  still bypasses the proxy as configured.
- Restart, firewall reload, and sing-box restart produce no stuck data path.

