{
  lib,
  liminix,
  output-template,
  ppp,
  pppoe,
  serviceFns,
  svc,
  writeAshScript,
  callPackage,
}:
{
  interface,
  ppp-options,
  lcpEcho,
  bandwidth,
  username,
  password,
  debug,
  timeout-up ? null,
  redial-interval ? 30,
  redial-dependents ? [ ],
}:
let
  name = "${interface.name}.pppoe";
  common = callPackage ./common.nix { inherit svc; };
in
common {
  inherit
    name
    debug
    username
    password
    lcpEcho
    bandwidth
    ppp-options
    timeout-up
    redial-interval
    redial-dependents
    ;
  # rp-pppoe plugin only accepts device names starting with eth/br/nic-
  command = ''
    exec ${ppp}/bin/pppd plugin ${pppoe}/lib/rp-pppoe.so nic-$(output ${interface} ifname) file /run/${name}/ppp-options
  '';
  dependencies = [ interface ];
}
