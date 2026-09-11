# TFTP-rootfs config for JDCloud AX6600 (RE-CS-02) exercising the
# phase-E ethernet: the four DSA LAN ports lan1..lan4 (QCA8075 via the
# in-tree ESS/PPE/EDMA stack) bridged into "int" on 192.168.9.0/24,
# and the 2.5G "wan" port as a DHCP client uplink.
#
# WIRED-ONLY / NO-WIFI build: there is no wireless interface, no ath11k
# module and no radio in the device tree. The only network transport is
# this wired bridge plus the WAN uplink, which is all this variant
# needs. (The ax6600 branch carries the radio bring-up image.)
#
# Boot like ax6600-dev.nix: serial console + TFTP on 192.168.1.2
#   nix-build --arg device "import ./devices/jdcloud-ax6600" \
#     -I liminix-config=./ax6600-lan.nix -A outputs.tftpboot -o result-lan
# then paste result-lan/boot.scr at the U-Boot prompt.
#
# Success indicators: dmesg shows the ppe/edma/uniphy probes and
# "lan1..lan4, wan" netdevs; "ip link" lists them; plugging a PC into
# lan1 gets a DHCP lease from 192.168.9.0/24.
{
  config,
  pkgs,
  ...
}:
let
  svc = config.system.service;
  nifs = config.hardware.networkInterfaces;
in
{
  imports = [
    ./ax6600-dev.nix
    ./modules/network
    ./modules/dnsmasq
    ./modules/bridge
    ./modules/dhcp4c
    ./modules/ssh
  ];

  services.int = svc.bridge.primary.build {
    ifname = "int";
  };

  services.bridge = svc.bridge.members.build {
    primary = config.services.int;
    members = [
      nifs.lan1
      nifs.lan2
      nifs.lan3
      nifs.lan4
    ];
  };

  services.int-address = svc.network.address.build {
    interface = config.services.int;
    family = "inet";
    address = "192.168.9.1";
    prefixLength = 24;
  };

  services.dhcpv4 = svc.dnsmasq.build {
    interface = config.services.int;
    domain = "lan";
    ranges = [ "192.168.9.100,192.168.9.200,255.255.255.0,12h" ];
  };

  # 2.5G WAN as DHCP client (no carrier yet on bring-up boards).
  services.wan-dhcp = svc.dhcp4c.client.build {
    interface = nifs.wan;
  };
  services.defaultroute4 = svc.network.route.build {
    via = "$(output ${config.services.wan-dhcp} address)";
    target = "default";
    dependencies = [ config.services.wan-dhcp ];
  };

  # SSH (dropbear), so the board is reachable without a serial console:
  #   ssh root@192.168.9.1     (password "secret")
  # Listens on all interfaces (address = null) - the only interfaces on
  # this wired-only build are the "int" LAN bridge and the 2.5G WAN.
  # All allow* options default to true in modules/ssh, so root may log
  # in with a password; the password hash lives in ax6600-dev.nix next
  # to the serial-console login, so both logins share one credential.
  services.sshd = svc.ssh.build { };

  # NB: the ax6600 branch pulls in `iw` here for radio diagnostics.
  # This is a wired-only build with no wireless stack at all, so no
  # wifi tooling is installed. (pkgs is still needed by the argument
  # set below; keep the `with pkgs;` list empty rather than dropping
  # the binding, so a later wired-only tool can be added in place.)
  defaultProfile.packages = with pkgs; [ ];
}
