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
  hostname = "office-ax6600";

  # Build-time only: also write the s6 log stream to the pstore pmsg
  # device, so logs outlive a reboot. Needs a rebuild, not a config edit.
  persistentLogging = true;

  lan = {
    address = "10.10.10.10";
    prefixLength = 24;
    dhcpRange = "10.10.10.50,10.10.10.200,255.255.255.0,12h";

    # Static leases keyed by hostname, applied at run time: `mac` and `ip`
    # are required, `leasetime` optional (default 86400). Keep the
    # addresses outside dhcpRange.
    dhcpHosts = {
      raspberrypi = {
        mac = "B8:27:EB:C0:01:5A";
        ip = "10.10.10.1";
      };
      ASUS = {
        mac = "3C:7C:3F:50:D8:3F";
        ip = "10.10.10.5";
      };
      openmediavault = {
        mac = "34:97:F6:BC:8D:AA";
        ip = "10.10.10.9";
      };
    };

    # Local DNS records answered by dnsmasq itself instead of being
    # forwarded upstream. Keyed by hostname, value is the address.
    dnsHosts = {
      "erp.bumooby.com" = "10.10.10.9";
    };
  };

  wan = {
    # 802.1Q tag the WAN port needs in front of the PPPoE session (many
    # ISPs hand the session out on a VLAN). null, or no key at all in the
    # run-time /persist/config.json, means an untagged WAN.
    vlan = 1510;

    # The ONT keeps its management address (usually 192.168.1.1) on the
    # untagged side of the WAN port, where the PPPoE session cannot reach
    # it: the router takes an address in that subnet so both it and the
    # LAN can get there (ax6600-lan.nix, service wan-ont).
    ont = {
      address = "192.168.1.2";
      prefixLength = 24;
    };

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
