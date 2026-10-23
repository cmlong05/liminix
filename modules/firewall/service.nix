{
  liminix,
  lib,
  firewallgen,
  nftables,
  s6,
  svc,
  lua,
  output-template,
}:
{
  appendRules,
  appendRulesBeforeLog ? { },
  rules,
  extraRules,
  zones,
  dontWait ? [ ],
  restartAfterReload ? [ ],
}:
let
  inherit (liminix.services) longrun;
  inherit (lib.attrsets) mapAttrs' nameValuePair mapAttrsToList;
  inherit (lib.strings) concatStringsSep escapeShellArg;
  inherit (builtins) concatLists toJSON attrValues;
  inherit (liminix) outputRef;
  mkSet =
    family: name:
    nameValuePair "${name}-set-${family}" {
      kind = "set";
      inherit name family;
      type = "ifname";
      extraText = ''
        {{;
           local services = { ${concatStringsSep ", " (map toJSON zones.${name})} }
           local ifnames = {}
           for _, v in ipairs(services) do
             local o = output(v, "ifname")
             if o then table.insert(ifnames, o) end
           end
           if (#ifnames > 0) then
             return "elements = { " .. table.concat(ifnames, ", ") .. " }\n"
           else
             return ""
           end
        }}
      '';
    };

  rateHook6 =
    let
      rules = map (x: ''
        {{;
         local s = "${x}";
         local n = output(s, "ifname");
         local bw = output(s, "bandwidth");
         if n and bw then
           return "meta l4proto icmpv6 iifname ".. n .. " limit rate over " .. (math.floor (tonumber(bw) / 8 / 20)) .. " bytes/second drop"
         else
           return "# " .. (n or "not n") .. " " .. (bw or "not bw")
         end
        }}
      '') (concatLists (builtins.attrValues zones));
    in
    {
      type = "filter";
      family = "ip6";
      hook = "input";
      priority = "-1";
      policy = "accept";
      inherit rules;
    };

  rateHook4 =
    let
      rules = map (x: ''
        {{;
         local s = "${x}";
         local n = output(s, "ifname");
         local bw = output(s, "bandwidth");
         if n and bw then
           return "meta l4proto icmp iifname ".. n .. " limit rate over " .. (math.floor (tonumber(bw) / 8 / 20)) .. " bytes/second drop"
         else
           return "# " .. (n or "not n") .. " " .. (bw or "not bw")
         end
        }}
      '') (concatLists (builtins.attrValues zones));
    in
    {
      type = "filter";
      family = "ip";
      hook = "input";
      priority = "-1";
      policy = "accept";
      inherit rules;
    };

  sets = (mapAttrs' (n: _: mkSet "ip" n) zones) // (mapAttrs' (n: _: mkSet "ip6" n) zones);
  base = {
    icmp6-ratehook = rateHook6;
    icmp4-ratehook = rateHook4;
  }
  // (lib.recursiveUpdate (lib.recursiveUpdate sets rules) extraRules);

  # A log rule has no verdict, so it does not end the chain: rules appended
  # after it are still reached, but every packet they accept is logged as
  # denied first. Insert such rules ahead of the first one instead.
  insertBeforeLog =
    rules: extra:
    let
      n = builtins.length rules;
      # index of the chain's first log rule, or n if it has none
      at =
        let
          logs = builtins.filter
            (i: lib.hasPrefix "log " (lib.trim (builtins.elemAt rules i)))
            (builtins.genList (i: i) n);
        in
        if logs == [ ] then n else builtins.head logs;
    in
    (lib.lists.sublist 0 at rules) ++ extra ++ (lib.lists.sublist at (n - at) rules);

  inserted = lib.mapAttrs (
    name: extra:
    if base ? ${name} then
      base.${name} // { rules = insertBeforeLog (base.${name}.rules or [ ]) extra; }
    else
      throw "firewall.appendRulesBeforeLog names a chain that is not in the ruleset: ${name}"
  ) appendRulesBeforeLog;
  withInserted = base // inserted;

  # appendRules is for the case extraRules cannot serve: several modules
  # all wanting to add to the same chain, where "attrsOf (listOf str)"
  # merges by concatenation and "attrsOf attrs" would have collided.
  appended = lib.mapAttrs (
    name: extra:
    if withInserted ? ${name} then
      withInserted.${name} // { rules = (withInserted.${name}.rules or [ ]) ++ extra; }
    else
      throw "firewall.appendRules names a chain that is not in the ruleset: ${name}"
  ) appendRules;
  allRules = withInserted // appended;
  script = firewallgen "firewall1.nft" allRules;
  name = "firewall";
  restartServices = concatStringsSep "\n" (
    map (
      service:
      let
        dir = "/run/service/${service.name}";
      in
      ''
        if test -d ${escapeShellArg dir} && test "$(${s6}/bin/s6-svstat -o up ${escapeShellArg dir})" = true ; then
          ${s6}/bin/s6-svc -r ${escapeShellArg dir}
        fi
      ''
    ) restartAfterReload
  );
  service = longrun {
    inherit name;
    run = ''
      PATH=${nftables}/bin:${lua}/bin:$PATH
      reload() {
         echo reloading firewall
         ${output-template}/bin/output-template '{{' '}}' < ${script} > /run/${name}/fw.nft
         if ! nft -f /run/${name}/fw.nft ; then
           return 1
         fi
         ${restartServices}
      }
      trap reload SIGUSR1
      mkdir -p /run/${name}; in_outputs ${name}
      reload
      while :; do
        # signals sent to ash won't interrupt sleep, but will interrupt wait
        sleep 86400 & wait
      done
    '';
    finish = "${nftables}/bin/nft flush ruleset";
  };
in
svc.secrets.subscriber.build {
  action = "usr1";
  watch = concatLists (
    mapAttrsToList (_zone: services: map (s: outputRef s "ifname") services) zones
  );

  inherit dontWait service;
}
