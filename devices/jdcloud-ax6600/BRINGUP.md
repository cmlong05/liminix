# JDCloud AX6600 (RE-CS-02) — Liminix bring-up

Branch: `RE-CS-02`.

This branch carries the **Ethernet (phase E) work** and, since the radio
port landed, the **wifi work** as well. Both are ports of upstream
OpenWrt/ImmortalWrt material that is fetched at build time rather than
committed: the ethernet side is `./ether/`, the radio side is `./wifi/`
(its README is the place to read about the detail port).

Status: `ax6600-wifi-ram.nix` is the 2.4GHz-only image; the 5GHz radio is off
unless `wifi.qcn9074.enable` is set (`ax6600-wifi-ram-5g.nix`). See
`./wifi/README` for the hardware status and the reason.

## Background / hardware

- Kernel baseline: **Linux 6.18.49** (kernel.org, fetched from the ustc
  mirror), chosen over 6.12.60 because the Qualcomm in-tree ethernet
  drivers need phylink/PCS features that 6.12 lacks (see below).
- IPQ6010 (4x Cortex-A53), 64 / 128 GB /256 eMMC, serial console on BLSP1 UART3
  (`ttyMSM0`, 115200 8N1).
- Community "unbrickable" U-Boot (2016.01-based) with a web UI at
  http://192.168.1.1 (`http://192.168.1.1/initramfs.html` uploads and boots ram test image).
- Ethernet: QCA8075 4x1G (`lan1`..`lan4`) + QCA8081 2.5G (`wan`),
  driven by the ESS/PPE/EDMA/UNIPHY stack.
- WiFi: QCN9024 5GHz on PCIe0 (perst GPIO53) and the IPQ6018 AHB radio,
  both ath11k. Porting — see [WiFi](#wifi-ported) below and
  `./wifi/README`. Only images that import `modules/wlan.nix` carry the
  wireless stack; the wired-only images are unchanged.

## Next steps

1. Boot `result-wifi` (2.4GHz-only) with a full serial capture and check
   whether `wlan24` appears, and whether the board resets at the AHB's
   `chip_id` line (0910, the SSR-name fix, is the candidate for that).
2. Run the official OpenWrt or ImmortalWrt image for `jdcloud_re-cs-02` on
   this unit and capture its dmesg: that is the reference the port is
   allowed to compare against.
3. Only then look at the QCN9074 again (probe timing against the official
   kmod load, then a bounded retry) — with `ax6600-wifi-ram-5g.nix`.

