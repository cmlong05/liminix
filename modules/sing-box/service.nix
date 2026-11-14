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
  templateFile ? null,
}:
let
  inherit (liminix.services) longrun;
  inherit (lib) escapeShellArg;
  ip = "${iproute2}/bin/ip";
  singBox = "${sing-box}/bin/sing-box";
  template = if templateFile == null then "" else toString templateFile;
in
longrun {
  name = "sing-box";
  # 不设 notification-fd：配置缺失/无效时本服务只是闲等，不能变成
  # s6-rc 的超时失败——失败会让依赖它的服务被跳过，且 firewall
  # 重启它时会连带失败。
  run = ''
    config=${escapeShellArg configFile}
    state=${escapeShellArg stateDir}
    tun=${escapeShellArg tunName}
    template=${escapeShellArg template}

    mkdir -m 0700 -p "$state"

    if ! test -s "$config" && test -n "$template" && test -s "$template" ; then
      cp "$template" "$config"
      chmod 0600 "$config"
    fi

    if ! test -s "$config" ; then
      echo "sing-box: no runtime config at $config; transparent routing stays disabled" >&2
      while : ; do sleep 3600 ; done
    fi

    if ! ${singBox} check -c "$config" ; then
      echo "sing-box: invalid runtime config at $config; transparent routing stays disabled" >&2
      while : ; do sleep 3600 ; done
    fi

    mkdir -p /dev/net
    if ! test -c /dev/net/tun ; then
      if mknod /dev/net/tun c 10 200 ; then
        chmod 0600 /dev/net/tun
      else
        echo "sing-box: mknod /dev/net/tun failed; transparent routing unavailable" >&2
      fi
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
      sleep 1
    done

    wait "$pid"
    status=$?
    exit "$status"
  '';
}
