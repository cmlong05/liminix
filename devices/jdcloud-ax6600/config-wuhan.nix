# 站点：wuhan —— `sh build.sh -c wuhan`
#
# 共同项在 ./_defaults.nix，这里只写与它不同的部分。
# 本站在普通非 tag 的 WAN 上拨号（不启用 singleLine、无 vlan），也没有
# 静态租约和本地 DNS 记录，这些都取 _defaults.nix 的默认值。
import ./_defaults.nix {
  hostname = "wuhan-ax6600";

  lan = {
    address = "10.10.2.1";
    dhcpRange = "10.10.2.50,10.10.2.200,255.255.255.0,12h";
  };

  wan = {
    pppoe = {
      username = "5110010895521";
      password = "071291";
    };
  };

  wifi.bands = {
    "24g" = {
      ssid = "CHEN";
      password = "88888888!!";
    };
    "58g" = {
      ssid = "CH";
      password = "88888888!!";
    };
  };
}
