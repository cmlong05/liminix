{ stdenv }:
stdenv.mkDerivation {
  name = "reset-button";
  src = ./.;
  buildPhase = "$CC -O2 -o reset-button reset-button.c";
  installPhase = ''
    mkdir -p $out/bin
    cp reset-button $out/bin/
  '';
}
