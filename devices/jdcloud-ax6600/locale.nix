{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.pseudofile) symlink;

  # SSH 登录环境统一使用 UTF-8，并配置 vim/less 的字符编码。
  shellProfile = symlink (
    pkgs.writeScript "profile" ''
      PATH=${lib.makeBinPath config.defaultProfile.packages}:/bin
      LANG=C.UTF-8
      LC_CTYPE=C.UTF-8
      LESSCHARSET=utf-8
      VIMINIT='set encoding=utf-8 termencoding=utf-8 fileencodings=ucs-bom,utf-8,gb18030,gbk'
      export PATH LANG LC_CTYPE LESSCHARSET VIMINIT
    ''
  );
in
{
  # 开启 Unicode 和宽字符；0 表示不限制支持的字符范围。
  programs.busybox.options = {
    UNICODE_SUPPORT = "y";
    UNICODE_WIDE_WCHARS = "y";
    LAST_SUPPORTED_WCHAR = "0";
  };

  filesystem.etc.profile = lib.mkForce shellProfile;
  filesystem.etc.ashrc = lib.mkForce shellProfile;
}
