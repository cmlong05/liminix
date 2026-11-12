# 站点：home —— `sh build.sh -c home`
#
# 共同项在 ./_defaults.nix，这里只写与它不同的部分。
{
  hostname = "home-ax6600";

  lan = {
    address = "10.10.0.1";
    dhcpRange = "10.10.0.50,10.10.0.200,255.255.255.0,12h";

    dhcpHosts = {
      raspberrypi = {
        mac = "B8:27:EB:C0:01:5A";
        ip = "10.10.0.10";
      };
      ASUS = {
        mac = "3C:7C:3F:50:D8:3F";
        ip = "10.10.0.5";
      };
      Xiaomi_M2006J10C = {
        mac = "5a:a8:ee:1f:7f:9b";
        ip = "10.10.0.9";
      };
    };
  };

  wan = {
    singleLine.enable = true;
    vlan = 41;
    pppoe = {
      username = "5110018610809";
      password = "888888";
    };
  };

  wifi.bands = {
    "24g" = {
      ssid = "CHEN";
      password = "88888888!!";
    };
    "58g" = {
      ssid = "CHEN-5g";
      password = "88888888!!";
    };
  };
}
