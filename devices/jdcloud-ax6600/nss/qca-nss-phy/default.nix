# qca-nss-phy's `nss_ext` headers, which qca-ssdk includes as
# "qca-nss-phy/nss_phy.h" (hsl_phy.h:18) and
# "qca-nss-phy/nss_phy_ptp.h" (fal_ptp.h:32).
#
# Upstream ships this as an OpenWrt BUILDONLY package installed into
# STAGING_DIR/usr/include; here the archive is an include path. SSDK only
# needs the headers, not the .c files - the PHY that ends up behind these
# phylib devices is the mainline qca807x/qca808x driver.
{
  stdenv,
  fetchzip,
  sources,
}:
let
  inherit (sources) nssPhy;
in
stdenv.mkDerivation {
  pname = "qca-nss-phy-headers";
  version = nssPhy.date;

  src = fetchzip {
    inherit (nssPhy) url sha256 name;
    stripRoot = true;
  };

  dontBuild = true;
  dontConfigure = true;
  dontStrip = true;

  installPhase = ''
    mkdir -p $out/include/qca-nss-phy
    install -m 0644 ${nssPhy.subdir}/*.h $out/include/qca-nss-phy/
  '';

  meta = {
    description = "QSDK NSS PHY headers required by qca-ssdk";
    inherit (nssPhy) license;
  };
}
