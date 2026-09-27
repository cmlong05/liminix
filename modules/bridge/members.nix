{
  liminix,
  lib,
  ifwait,
  svc,
}:
{ members, primary }:

let
  inherit (liminix.networking) interface;
  inherit (liminix.services) bundle oneshot;
  addif =
    member:
    let
      port = oneshot {
        name = "${primary.name}.member.${member.name}";
        up = ''
          ip link set dev $(output ${member} ifname) master $(output ${primary} ifname)
        '';
        down = "ip link set dev $(output ${member} ifname) nomaster";
      };
      watcher = svc.ifwait.build {
        state = "running";
        interface = member;
        dependencies = [
          primary
          member
        ];
        service = port;
      };
    in
    [
      port
      watcher
    ];
in
bundle {
  name = "${primary.name}.members";
  contents = lib.concatMap addif members;
}
