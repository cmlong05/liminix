{
  liminix,
  lib,
  iproute2,
}:
{
  name,
  bridge,
  uplink,
  vlan,
  lanVlan,
}:
let
  inherit (liminix.services) oneshot;
in
oneshot {
  inherit name;
  dependencies = [
    bridge
    uplink
  ];
  up = ''
    ip=${iproute2}/bin/ip
    bridge_tool=${iproute2}/bin/bridge
    bridge_if=$(output ${bridge} ifname)
    uplink_if=$(output ${uplink} ifname)
    vid=${lib.escapeShellArg vlan}

    case "$vid" in
      "" | *[!0-9]*)
        echo "${name}: vlan must be set" >&2
        exit 1
        ;;
    esac
    test "$vid" != ${lib.escapeShellArg (toString lanVlan)} || {
      echo "${name}: vlan must differ from the LAN VLAN" >&2
      exit 1
    }

    vlan_has() {
      "$bridge_tool" vlan show dev "$1" vid "$2" | grep -Eq "^[[:space:]]*$2([[:space:]]|$)"
    }
    vlan_add() {
      dev=$1
      id=$2
      shift 2
      vlan_has "$dev" "$id" || "$bridge_tool" vlan add dev "$dev" vid "$id" "$@"
    }

    # 先启用 VLAN filtering 再加入 trunk，避免 WAN 帧泄漏到 LAN。
    "$ip" link set dev "$bridge_if" type bridge vlan_filtering 1
    "$ip" link set dev "$uplink_if" master "$bridge_if"
    # LAN 使用 untagged VLAN，WAN VLAN 只在上联口和桥上 tagged。
    vlan_add "$uplink_if" ${toString lanVlan} pvid untagged
    vlan_add "$bridge_if" ${toString lanVlan} pvid untagged self
    vlan_add "$uplink_if" "$vid"
    vlan_add "$bridge_if" "$vid" self
    "$ip" link set up dev "$bridge_if"
    "$ip" link set up dev "$uplink_if"
  '';
  down = ''
    ${iproute2}/bin/ip link set dev "$(output ${uplink} ifname)" nomaster || true
  '';
}
