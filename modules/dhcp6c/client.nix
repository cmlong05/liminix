{
  liminix,
  lib,
  odhcp6c,
  odhcp-script,
  svc,
}:
{
  interface,
  wait-for ? null,
  wait-time ? 20,
  timeout-up ? 60 * 1000,
}:
let
  inherit (liminix.services) longrun;
  inherit (liminix) outputRef;
  name = "dhcp6c.${interface.name}";
  autoconf = svc.ipv6.autoconfig.build {
    inherit interface;
  };
  service = longrun {
    inherit name;
    notification-fd = 10;
    inherit timeout-up;
    run = ''
      export SERVICE_STATE=$SERVICE_OUTPUTS/${name}
      ${lib.optionalString (wait-for != null) ''
        p=${wait-for}
        i=0
        while ! test -e "$p" && test $i -lt ${toString wait-time} ; do sleep 1 ; i=$((i + 1)) ; done
      ''}
      ifname=$(output ${interface} ifname)
      test -n "$ifname" && ${odhcp6c}/bin/odhcp6c -s ${odhcp-script} -e -v -p /run/${name}.pid -P0 $ifname
    '';
    dependencies = [
      interface
      autoconf
    ];
  };
in
svc.secrets.subscriber.build {
  # if the ppp service gets restarted, the interface may be different and
  # we will have to restart dhcp on the new one
  watch = [ (outputRef interface "ifindex") ];
  action = "restart";
  inherit service;
}
