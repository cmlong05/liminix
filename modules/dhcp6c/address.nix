{
  liminix,
  callPackage,
}:
{ client, interface }:
let
  inherit (liminix.services) longrun;
  name = "dhcp6c.addr.${client.name}.${interface.name}";
  script = callPackage ./acquire-wan-address.nix { };
in
longrun {
  inherit name;
  # the client's outputs are emptied when it restarts, so keep our record
  # of the addresses we put on the WAN somewhere of our own: without it a
  # restart leaves the previous addresses behind until their lifetime ends
  run = "${script} ${client} $(output ${interface} ifname) $(mkstate ${name})";
  dependencies = [
    client
    interface
  ];
}
