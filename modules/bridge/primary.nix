{
  liminix,
  lib,
}:
{ ifname }:
let
  inherit (liminix.services) oneshot;
in
oneshot rec {
  name = "${ifname}.link";
  up = ''
    set -e
    if ! ip link show dev "${ifname}" >/dev/null 2>&1; then
      ip link add name "${ifname}" type bridge
    fi
    ${liminix.networking.ifup name ifname}
  '';
  down = "ip link set down dev ${ifname}";
}
