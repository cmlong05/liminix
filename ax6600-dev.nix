# Development configuration for JDCloud AX6600 (RE-CS-02)
#
# Boots a ram-based Liminix system over TFTP with no changes to the
# eMMC. The default serial console login works out of the box (s6
# getty reads the active console device), password below is "secret".
#
# Build with:
#   nix-build --arg device "import ./devices/jdcloud-ax6600" \
#     -I liminix-config=./ax6600-dev.nix -A outputs.tftpboot
#   nix-build --arg device "import ./devices/jdcloud-ax6600" \
#     -I liminix-config=./ax6600-dev.nix -A outputs.default
#
# Then serve result/ from a TFTP server on 192.168.1.2 and paste
# result/boot.scr into U-Boot on the serial console.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  svc = pkgs.liminix.services;
in
{
  hostname = "ax6600";

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
    passwd = "$6$uqFC7Xu7q2uWTquh$axLjr8YpuQE.dqHlgQTXaeglki/FLsaLMX6RyKHWbYUL2VA4FRFmd2N/MNrqdGaKfzDrdbFJUxnPrfmjIciP80
";
  };

  # Tools useful for bring-up and for preparing the eMMC in phase 3
  # (partition checks, formatting the rootfs).
  defaultProfile.packages = with pkgs; [
    e2fsprogs
    gptfdisk
    util-linux
  ];
}
