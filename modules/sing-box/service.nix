{
  liminix,
  iproute2,
  sing-box,
  lib,
}:
{
  configFile,
  stateDir,
  tunName,
}:
let
  inherit (liminix.services) longrun;
  inherit (lib) escapeShellArg;
  ip = "${iproute2}/bin/ip";
  singBox = "${sing-box}/bin/sing-box";
in
longrun {
  name = "sing-box";
  run = ''
    config=${escapeShellArg configFile}
    state=${escapeShellArg stateDir}
    tun=${escapeShellArg tunName}

    mkdir -m 0700 -p "$state"

    if ! test -s "$config" ; then
      echo "sing-box: no runtime config at $config; transparent routing stays disabled"
      while : ; do sleep 3600 ; done
    fi

    if ! ${singBox} check -c "$config" ; then
      echo "sing-box: invalid runtime config at $config; transparent routing stays disabled"
      while : ; do sleep 3600 ; done
    fi

    if ! test -c /dev/net/tun ; then
      mkdir -p /dev/net
      mknod /dev/net/tun c 10 200
      chmod 0600 /dev/net/tun
    fi

    ${singBox} run -c "$config" &
    pid=$!

    stop() {
      trap - TERM INT
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      exit 0
    }
    trap stop TERM INT

    tries=0
    while ! ${ip} link show dev "$tun" >/dev/null 2>&1 ; do
      if ! kill -0 "$pid" 2>/dev/null ; then
        wait "$pid"
        status=$?
        exit "$status"
      fi
      tries=$((tries + 1))
      if test "$tries" -ge 100 ; then
        echo "sing-box: TUN $tun did not become ready; transparent routing stays disabled"
        kill -TERM "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        exit 1
      fi
      sleep 0.1
    done

    wait "$pid"
    status=$?
    exit "$status"
  '';
}
