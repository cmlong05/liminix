{
  liminix,
  lib,
}:
{
  target,
  via,
  interface ? null,
  metric,
  wait-for ? null,
  wait-time ? 20,
}:
let
  inherit (liminix.services) oneshot;
  inherit (lib) optional optionalString;
  with_dev = if interface != null then "dev $(output ${interface} ifname)" else "";
  target_hash = builtins.substring 0 12 (builtins.hashString "sha256" target);
  via_hash = builtins.substring 0 12 (builtins.hashString "sha256" via);
in
oneshot {
  name = "route-${target_hash}-${
    builtins.substring 0 12 (
      builtins.hashString "sha256" "${via_hash}-${if interface != null then interface.name else ""}"
    )
  }";
  # wait-for 是给按需产生的输出用的：IPv6 对端地址要等 IPV6CP 协商完才有，
  # 而 WAN 服务在 IPv4 通了之后就算是起来了。
  up = ''
    ${optionalString (wait-for != null) ''
      p=${wait-for}
      i=0
      while ! test -e "$p" && test $i -lt ${toString wait-time} ; do sleep 1 ; i=$((i + 1)) ; done
    ''}
    ip route add ${target} via ${via} metric ${toString metric} ${with_dev}
  '';
  down = ''
    ip route del ${target} via ${via} ${with_dev}
  '';
  dependencies = [ ] ++ optional (interface != null) interface;
}
