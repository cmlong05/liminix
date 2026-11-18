{ pkgsBuildBuild }:
let
  source = import ./SOURCES.nix;
  archive = pkgsBuildBuild.fetchurl {
    name = "vikingyfy-${source.rev}.tar.gz";
    inherit (source.src) url sha256;
  };
in
pkgsBuildBuild.runCommand "vikingyfy-nss-wifi-patches" { } ''
  set -eu
  mkdir -p source $out/inventory $out/subsys $out/ath11k
  tar -xzf ${archive} -C source
  root=source/${source.src.root}
  cp -a "$root/${source.subsysPath}" $out/inventory/subsys
  cp -a "$root/${source.ath11kPath}" $out/inventory/ath11k
  find $out/inventory -type f -name '*.patch' -exec \
    sed -i 's/CPTCFG_/CONFIG_/g' {} +

  test "$(find $out/inventory/subsys -type f -name '*.patch' | wc -l)" -eq 26
  test "$(find $out/inventory/ath11k -type f -name '*.patch' | wc -l)" -eq 75

  ${builtins.concatStringsSep "\n" (
    map (p: ''install -m 0644 "$out/inventory/subsys/${p}" "$out/subsys/${p}"'')
      source.apply.subsys
  )}
  ${builtins.concatStringsSep "\n" (
    map (p: ''install -m 0644 "$out/inventory/ath11k/${p}" "$out/ath11k/${p}"'')
      source.apply.ath11k
  )}

  for p in "$out"/subsys/*.patch "$out"/ath11k/*.patch; do
    sed -i 's/---help---/help/g' "$p"
    awk '
      /^--- a\// {
        file = substr($0, 7)
        file_skip = (file ~ /^backport-include\// || file == "local-symbols")
        hunk_skip = 0
      }
      /^@@/ {
        hunk_skip = (file == "drivers/net/wireless/ath/ath11k/dp.c" &&
                     index($0, "int ath11k_dp_service_srng") != 0) ||
                    (file == "drivers/net/wireless/ath/ath11k/mac.c" &&
                     (index($0, "@@ -6291,6 +6291,18 @@ static int ath11k_mac_mgmt_tx_wmi") != 0 ||
                      index($0, "@@ -6535,8 +6547,8 @@ static void ath11k_mgmt_over_wmi_tx_work") != 0)) ||
                    (file == "drivers/net/wireless/ath/ath11k/wmi.c" &&
                     index($0, "@@ -9299,6 +9388,10 @@ static void ath11k_wmi_tlv_op_rx") != 0)
      }
      !file_skip && !hunk_skip { print }
    ' "$p" > "$p.native"
    mv "$p.native" "$p"
  done
''
