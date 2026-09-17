# Base configuration for JDCloud AX6600 (RE-CS-02)
#
# Not a complete image by itself: it sets the root password and a
# bring-up LED service. The buildable systems are ax6600-lan-ram.nix
# (ethernet only) and ax6600-wifi-ram.nix (ethernet + both ath11k
# radios), which add their services (and, from the deployment values,
# the hostname and LAN address) and produce the single-file full-system
# ram image that the U-Boot web uploader at
# http://192.168.1.1/uimage.html boots directly - no serial console,
# no TFTP server.
#
# Deployment (hostname, LAN address, DHCP pool) is not a property of
# the board, so it is not here either: ax6600-lan.nix reads it from
# ./devices/jdcloud-ax6600/config.nix, which carries only data. Nor is
# the radio's per-unit calibration: the wifi image reads that from the
# board's own ART partition at boot (see ./ax6600-wifi.nix).
{
  pkgs,
  ...
}:
let
  svc = pkgs.liminix.services;
in
{
  # No-serial-console bring-up aid: once s6 and this oneshot are up,
  # userland is demonstrably alive. The kernel lights the red LED
  # (default-state "on"); this service turns red off and green on.
  services.led-userland = svc.oneshot {
    name = "led-userland";
    up = ''
      for l in blue:status green:status red:status; do
        test -e /sys/class/leds/$l/brightness || continue
        echo 0 > /sys/class/leds/$l/brightness 2>/dev/null
      done
      echo 255 > /sys/class/leds/green:status/brightness 2>/dev/null || true
    '';
  };

  users.root = {
    # Use mkpasswd -m sha512crypt to create
    # your own hashed password string.
    passwd = "$6$uqFC7Xu7q2uWTquh$axLjr8YpuQE.dqHlgQTXaeglki/FLsaLMX6RyKHWbYUL2VA4FRFmd2N/MNrqdGaKfzDrdbFJUxnPrfmjIciP80";
  };

  # Tools useful for bring-up and for preparing the eMMC in phase 3
  # (partition checks, formatting the rootfs).
  defaultProfile.packages = with pkgs; [
    e2fsprogs
    gptfdisk
    util-linux
  ];
}
