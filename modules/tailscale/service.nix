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
  tunMode,
  upArgs,
}:
let
  inherit (liminix.services) bundle longrun oneshot;
  inherit (lib) concatStringsSep optional optionalString;

  # devtmpfs publishes the misc device as /dev/tun; /dev/net/tun is the
  # udev pathname that tailscaled actually opens
  tunDevice = optionalString (tunMode == "kernel") ''
    if ! test -c /dev/net/tun ; then
      mkdir -p /dev/net
      mknod /dev/net/tun c 10 200
      chmod 0600 /dev/net/tun
    fi
  '';

  daemon = longrun {
    name = "tailscaled";
    run = ''
      state=${stateDir}
      # a deployment whose state partition did not mount still has to
      # come up, even though the login will not survive a reboot
      mkdir -p $state 2>/dev/null || state=/run/${name}
      mkdir -p $state
      ${tunDevice}
      exec ${tailscale}/bin/tailscaled \
        --state=$state/tailscaled.state \
        --socket=${socket} \
        --tun=${if tunMode == "kernel" then "tailscale0" else "userspace-networking"}
    '';
  };

  login = oneshot {
    name = "${name}-up";
    dependencies = [ daemon ];
    up = ''
      ${tailscale}/bin/tailscale --socket=${socket} up \
        --auth-key=${authKey} ${concatStringsSep " " upArgs}
    '';
  };
in
bundle {
  inherit name;
  contents = [ daemon ] ++ optional (authKey != null) login;
}
