{ stdenv }:
stdenv.mkDerivation {
  name = "gpio-button";
  src = ./.;
  buildPhase = "$CC -O2 -o gpio-button gpio-button.c";
  installPhase = ''
    mkdir -p $out/bin
    cp gpio-button $out/bin/
  '';
}
