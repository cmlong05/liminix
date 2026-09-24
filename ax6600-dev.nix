# Base configuration for JDCloud AX6600 (RE-CS-02)
#
# Not a complete image by itself: it sets the root password and a
# bring-up LED service.

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
    iperf3
  ];
}
