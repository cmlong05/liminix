{
  tunName,
  proxyRuleFile,
  bypassRuleFile,
}:
let
  localRuleSet = tag: path: {
    inherit tag;
    type = "local";
    format = "source";
    inherit path;
  };
in
builtins.toJSON {
  log = {
    level = "info";
    timestamp = true;
  };

  dns = {
    servers = [
      {
        tag = "dns-direct";
        type = "local";
      }
    ];
    final = "dns-direct";
  };

  inbounds = [
    {
      type = "tun";
      tag = "tun-in";
      interface_name = tunName;
      address = [
        "172.19.0.1/30"
        "fdfe:6c69:6e69:7869::1/126"
      ];
      mtu = 1500;
      stack = "system";
      auto_route = false;
      auto_redirect = false;
      strict_route = false;
    }
    {
      type = "socks";
      tag = "socks-proxy-in";
      listen = "::";
      listen_port = 1080;
    }
    {
      type = "socks";
      tag = "socks-direct-in";
      listen = "::";
      listen_port = 1081;
    }
  ];

  outbounds = [
    {
      type = "direct";
      tag = "direct";
    }
    {
      type = "socks";
      tag = "proxy";
      server = "127.0.0.1";
      server_port = 7890;
    }
  ];

  route = {
    rules = [
      {
        inbound = [ "socks-proxy-in" ];
        action = "route";
        outbound = "proxy";
      }
      {
        inbound = [ "socks-direct-in" ];
        action = "route";
        outbound = "direct";
      }
      {
        inbound = [ "tun-in" ];
        action = "sniff";
      }
      {
        protocol = "dns";
        action = "route";
        outbound = "direct";
      }
      {
        rule_set = "bypass";
        action = "route";
        outbound = "direct";
      }
      {
        ip_is_private = true;
        action = "route";
        outbound = "direct";
      }
      {
        rule_set = "proxy";
        action = "route";
        outbound = "proxy";
      }
    ];

    rule_set = [
      (localRuleSet "bypass" bypassRuleFile)
      (localRuleSet "proxy" proxyRuleFile)
    ];

    final = "direct";
    default_domain_resolver = "dns-direct";
  };
}
