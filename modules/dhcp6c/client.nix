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
        # wait-for 是调用方给的 shell 表达式（"$(output_path ...)"），不能转义；
        # 超时只告警：client 失败会让依赖它的 prefix/address 全部跳过。
        wait_for_path "${wait-for}" ${toString wait-time} || echo "timed out waiting for ${wait-for}" >&2
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
