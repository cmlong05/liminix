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
  # via 和 wait-for 都是调用方给的 shell 表达式（"$(output ...)"），只能原样展开，
  # 转义后赋值得到的是字面量。IPv6 对端地址要等 IPV6CP 协商完才有，而 WAN 服务在
  # IPv4 通了之后就算是起来了。装不上不判失败（oneshot 失败会让 s6-rc 跳过依赖它的
  # 服务），改为在 wait-time 内重试，超时只告警。
  up = ''
    i=0
    while test $i -lt ${toString wait-time} ; do
      ${optionalString (wait-for != null) ''
        if ! test -e "${wait-for}" ; then sleep 1 ; i=$((i + 1)) ; continue ; fi
      ''}
      via="${via}"
      if test -n "$via" && ip route replace ${target} via "$via" metric ${toString metric} ${with_dev} ; then
        exit 0
      fi
      sleep 1 ; i=$((i + 1))
    done
    echo "route ${target}: not installed after ${toString wait-time}s" >&2
  '';
  # 不查 via：WAN 停掉后它的输出已经不可读，按 target/metric/dev 匹配即可，
  # 设备消失时内核也已经清掉这条路由。
  down = ''
    ip route del ${target} metric ${toString metric} ${with_dev} || true
  '';
  dependencies = [ ] ++ optional (interface != null) interface;
}
