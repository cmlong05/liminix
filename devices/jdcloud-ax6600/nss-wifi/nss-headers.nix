{ pkgsBuildBuild, src }:
pkgsBuildBuild.runCommand "qca-nss-drv-headers" { } ''
  mkdir -p $out
  cp -a ${src}/exports/. $out/
  chmod u+w $out
  ln -s arch/nss_ipq60xx_64.h $out/nss_arch.h
''
