{ stdenv, fetchurl, which, python38, wget, file, cmake, libusb, autoPatchelfHook
}:
let
  version = "0.16.4";
  arch = "arm";
  sdk = fetchurl {
    url =
      "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${version}/zephyr-sdk-${version}_linux-x86_64_minimal.tar.xz";
    hash = "sha256-PLnZfwj+ddUq/d09SOdJVaQhtkIUzL30nFrQ4NdTCy0=";
  };
  armToolchain = fetchurl {
    url =
      "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${version}/toolchain_linux-aarch64_arm-zephyr-eabi.tar.xz";
    hash = "sha256-rFxWpeF8g7ByyJWAK0ZeGrI8S9v9x5nehKmUU7hQNrE=";
  };
in stdenv.mkDerivation {
  name = "zephyr-sdk";
  inherit version;
  srcs = [ sdk armToolchain ];
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
    tar -xf $2 -C $out
    (cd $out; bash ./setup.sh -h)
    rm $out/zephyr-sdk-x86_64-hosttools-standalone-0.9.sh
    runHook postInstall
  '';
}
