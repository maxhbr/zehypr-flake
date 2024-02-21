{ stdenv, fetchurl, which, python38, wget, file, cmake, libusb, autoPatchelfHook
}:
let
  version = "0.16.5-1";
  json = builtins.fromJSON (builtins.readFile (./data.json));
  sdk = fetchurl {
    inherit (json) url hash;
  };
in stdenv.mkDerivation {
  pname = "zephyr-sdk";
  inherit version;
  system = "x86_64-linux";
  srcs = [ sdk ];
  srcRoot = ".";
  nativeBuildInputs =
    [ which wget file python38 autoPatchelfHook cmake libusb ];
  phases = [ "installPhase" "fixupPhase" ];
  installPhase = ''
    runHook preInstall
    echo out=$out
    mkdir -p $out
    set $srcs
    tar -xf $1 -C $out --strip-components=1
    (cd $out; bash ./setup.sh -h)
    rm $out/zephyr-sdk-x86_64-hosttools-standalone-0.9.sh
    runHook postInstall
  '';
}
