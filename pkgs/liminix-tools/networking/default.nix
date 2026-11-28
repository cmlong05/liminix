{
  ifwait,
  serviceFns,
}:
{
  # waitSeconds > 0 caps how long we wait for the netdev to appear.
  # The default 0 keeps the historical "wait forever" behaviour, so a
  # slow-probing interface on another platform is not broken by a timeout
  # that was only meant for wlan52g (QCN9074 may never probe).
  ifup = name: ifname: waitSeconds: ''
    . ${serviceFns}
    timeout=${toString waitSeconds}
    i=0
    while ! ip link show ${ifname} >/dev/null 2>&1; do
      i=$((i + 1))
      if test "$timeout" -gt 0 && test "$i" -ge "$timeout"; then
        echo "ifup: ${ifname} never appeared" >&2
        exit 1
      fi
      sleep 1
    done
    ${ifwait}/bin/ifwait -v ${ifname} present
    ip link set up dev ${ifname}
    (in_outputs ${name}
     echo ${ifname} > ifname
    )
  '';
}
