{ pkgs, moduleTree }:
pkgs.runCommand "check-nss-wifi-offload" {
  nativeBuildInputs = [ pkgs.kmod ];
} ''
  sh ${./check-built.sh} ${moduleTree}
  touch $out
''
