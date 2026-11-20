{
  ifwait,
  serviceFns,
}:
{
  ifup = name: ifname: ''
    . ${serviceFns}
    # fail fast if the interface never appears: ifwait alone waits
    # forever, which stalls the whole boot when a radio never probes.
    i=0
    while ! ip link show ${ifname} >/dev/null 2>&1; do
      i=$((i + 1))
      test "$i" -ge 10 && { echo "ifup: ${ifname} never appeared" >&2; exit 1; }
      sleep 1
    done
    ${ifwait}/bin/ifwait -v ${ifname} present
    ip link set up dev ${ifname}
    (in_outputs ${name}
     echo ${ifname} > ifname
    )
  '';
}
