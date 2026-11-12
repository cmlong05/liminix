# 站点：office —— 默认站点，`sh build.sh` 不带 -c 时就是它
#
# 共同项在 ./_defaults.nix，这里只写与它不同的部分。新增站点：复制本文件
# 成 config-<名字>.nix，改下面这几处，再用 `sh build.sh -c <名字>`。
{
  hostname = "office-ax6600";

  lan = {
    address = "10.10.10.10";
    dhcpRange = "10.10.10.50,10.10.10.200,255.255.255.0,12h";

    # 静态租约：`mac` 和 `ip` 必填，`leasetime` 可选（默认 86400），
    # 地址不要落在 dhcpRange 内
    dhcpHosts = {
      raspberrypi = {
        mac = "B8:27:EB:C0:01:5A";
        ip = "10.10.10.1";
      };
      ASUS = {
        mac = "3C:7C:3F:50:D8:3F";
        ip = "10.10.10.5";
      };
      openmediavault = {
        mac = "34:97:F6:BC:8D:AA";
        ip = "10.10.10.9";
      };
      msi-wd = {
        mac = "2c:f0:5d:e7:68:15";
        ip = "10.10.10.107";
      };
    };

    # dnsmasq 自己回答、不转发上游的记录
    dnsHosts = {
      "erp.bumooby.com" = "10.10.10.9";
    };
  };

  wan = {
    singleLine.enable = true;
    vlan = 1510;
    pppoe = {
      username = "xga102782536";
      password = "443508";
    };
  };

  wifi.bands = {
    "24g" = {
      ssid = "MUL";
      password = "mubimuba";
    };
    "58g" = {
      ssid = "MU";
      password = "mubimuba";
    };
  };
}
