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
}
