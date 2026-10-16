{
  liminix,
  callPackage,
}:
{ client, interface }:
let
  inherit (liminix.services) longrun;
  name = "dhcp6c.prefix.${client.name}.${interface.name}";
  script = callPackage ./acquire-delegated-prefix.nix { };
in
longrun {
  inherit name;
  # the client's outputs are emptied when it restarts, so keep our record
  # of the prefixes we put on the interface somewhere of our own: without
  # it a restart leaves the previous prefix behind on the LAN
  run = "${script} ${client} $(output ${interface} ifname) $(mkstate ${name})";
  dependencies = [
    client
    interface
  ];
}
