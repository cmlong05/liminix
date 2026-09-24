# Deployment values for the JDCloud AX6600 (RE-CS-02): the network this
# board is deployed into.
#
# Plain data, not a module: `ax6600-lan.nix` imports this file into a
# let-binding and reads `deployment.lan` from it directly, so there is
# nothing to declare first and no interface file. This is the only place
# the LAN subnet, the DHCP pool and the hostname are written down.
#
# To deploy the same board on a different network, copy this file, change
# the numbers, and select it on the command line with the same `-I` idiom
# used for the configuration itself:
#
#   -I liminix-deployment=./devices/jdcloud-ax6600/config-lab.nix
#
# Without that argument the build uses this file.
{
  # System hostname. `ax6600-lan.nix` does
  # `hostname = lib.mkDefault deployment.hostname`, so another module can
  # still override it for a particular build.
  hostname = "ax6600";

  # The wired LAN bridge ("int") that dnsmasq serves on lan1..lan4: this
  # machine is .1 and hands out .50-.200.
  lan = {
    address = "10.10.10.10";
    prefixLength = 24;
    # dnsmasq `--dhcp-range` syntax: start,end,netmask,leasetime. Null if
    # DHCP is not served.
    dhcpRange = "10.10.10.50,10.10.10.200,255.255.255.0,12h";
  };

  # Upstream: the 2.5G "wan" port runs a PPPoE session, so this board is a
  # PPPoE client and the ISP's access concentrator supplies the address,
  # the peer address and the DNS servers. `ax6600-lan.nix` reads these two
  # values and passes them to `services.wan`.
  #
  # EDIT: put the broadband account here. ISPs document it as the "PPPoE
  # username/password" (sometimes as the PAP or CHAP credentials).
  #
  # NB: this file is tracked by git, so credentials written here are
  # committed. To keep them out of the repository, copy this file to an
  # untracked name and select it with `-I liminix-deployment=...`, or use
  # the `modules/secrets` service as described in doc/configuration.adoc
  # ("Runtime secrets").
  wan = {
    pppoe = {
      username = "xga102782536";
      password = "443508";
    };
  };
}
