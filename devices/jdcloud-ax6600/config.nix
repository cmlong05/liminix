# Deployment values for the JDCloud AX6600 (RE-CS-02)
#
# To deploy the same board on a different network, copy this file, change
# the numbers, and select it on the command line with the same `-I` idiom
# used for the configuration itself:
#
#   -I liminix-deployment=./devices/jdcloud-ax6600/config-lab.nix
#
# Without that argument the build uses this file.
{
  hostname = "ax6600";

  lan = {
    address = "10.10.10.10";
    prefixLength = 24;
    dhcpRange = "10.10.10.50,10.10.10.200,255.255.255.0,12h";
  };

  wan = {
    # IPv6 over the same PPPoE session: ask the BRAS for a delegated
    # prefix (DHCPv6-PD), then hand it to the LAN by SLAAC.
    ipv6 = {
      enable = true;
    };

    pppoe = {
      username = "xga102782536";
      password = "443508";
      # username = "5260383575";
      # password = "888888";
    };

    # Extra upstream resolvers
    extraResolvers = [
      "223.5.5.5"
      "119.29.29.29"
    ];
  };

  # APs. Read at build time by devices/jdcloud-ax6600/wireless/default.nix
  # and again at run time from this file's seed in /persist/config.json, so
  # changing an SSID, passphrase or channel needs no new image.
  # `bands` is keyed by which AHB pdev serves it: "24g" and "58g".
  wifi = {
    countryCode = "CN";
    # Build-time switch (a rebuild is needed, unlike the run-time overrides
    # above): false leaves the APs off at boot, to be started by hand.
    autostart = true;
    # Each band names its own passphrase and encryption mode: there is no
    # wifi-wide one of either, so two SSIDs cannot share a secret by
    # accident. Passphrases are read at run time; the mode is build-time
    # only, because hostapd's config is a static file that run time cannot
    # rewrite.
    # Mode: "wpa2" | "wpa2-wpa3" (needs hostapd built with SAE) | "open".
    bands = {
      "24g" = {
        ssid = "MUL";
        hw_mode = "g";
        channel = "6";
        password = "mubimuba";
        security = "wpa2";
      };
      "58g" = {
        ssid = "MU";
        hw_mode = "a";
        channel = "149";
        password = "mubimuba";
        security = "wpa2";
      };
    };
  };
}
