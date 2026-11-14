{
  liminix,
  lib,
  tailscale,
}:
{
  authKey,
  name,
  socket,
  stateDir,
  upArgs,
}:
let
  inherit (liminix.services) bundle longrun oneshot;
  inherit (lib) escapeShellArg escapeShellArgs optional;

  daemon = longrun {
    name = "tailscaled";
    run = ''
      state=${escapeShellArg stateDir}
      socket=${escapeShellArg socket}
      # an unwritable stateDir must not keep the daemon down; /run state is ephemeral
      if ! mkdir -p "$state" || ! test -w "$state" ; then
        echo "tailscaled: $state unusable, using /run state" >&2
        state=${escapeShellArg ("/run/" + name + "-state")}
      fi
      mkdir -p "$state" || exit 1
      chmod 0700 "$state" || echo "tailscaled: cannot set mode 0700 on $state" >&2
      mkdir -p "''${socket%/*}" || exit 1
      # devtmpfs only publishes the misc device as /dev/tun; /dev/net/tun is
      # the udev pathname tailscaled actually opens
      if ! test -c /dev/net/tun ; then
        mkdir -p /dev/net || exit 1
        mknod /dev/net/tun c 10 200 || exit 1
        chmod 0600 /dev/net/tun || exit 1
      fi
      exec ${tailscale}/bin/tailscaled \
        --state="$state/tailscaled.state" \
        --socket="$socket" \
        --tun=tailscale0
    '';
  };

  login = oneshot {
    name = "${name}-up";
    dependencies = [ daemon ];
    up = ''
      ${tailscale}/bin/tailscale --socket=${escapeShellArg socket} up \
        --auth-key=${escapeShellArg authKey} ${escapeShellArgs upArgs}
    '';
  };
in
bundle {
  inherit name;
  contents = [ daemon ] ++ optional (authKey != null) login;
}
