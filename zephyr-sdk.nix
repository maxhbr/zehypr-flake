{ stdenv, fetchurl, which, python38, wget, file, cmake, libusb, autoPatchelfHook
}:
let
  version = "0.16.4";
  sdk = fetchurl {
    url =
      "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${version}/zephyr-sdk-${version}_linux-x86_64_minimal.tar.xz";
    hash = "sha256-PLnZfwj+ddUq/d09SOdJVaQhtkIUzL30nFrQ4NdTCy0=";
  };

  # aarch64Toolchains = [
  #   {
  #     fn = "toolchain_linux-aarch64_arm-zephyr-eabi.tar.xz";
  #     hash = "sha256-rFxWpeF8g7ByyJWAK0ZeGrI8S9v9x5nehKmUU7hQNrE=";
  #   }
  #   {
  #     fn = "toolchain_linux-aarch64_xtensa-espressif_esp32_zephyr-elf.tar.xz";
  #     hash = "sha256-Rr/XkAtCZO+po3S0DTWScI3tuMJflejV0nr4k9iW6C0=";
  #   }
  # ];
  x86_64Toolchains = [
    {
      fn = "toolchain_linux-x86_64_arm-zephyr-eabi.tar.xz";
      hash = "sha256-IGHlhTTFf5jxsFtVfZpdDhhzrDizEIQVYtNg+XFflvs=";
    }
    {
      fn = "toolchain_linux-x86_64_xtensa-espressif_esp32_zephyr-elf.tar.xz";
      hash = "sha256-h2sT4tVtvDIguDuB09lZOSyvawQ4a2cOocfJDw7uqvo=";
    }
  ];

  toolchains = map ({fn, hash}: fetchurl {
    url = "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${version}/${fn}";
    inherit hash;
  }) x86_64Toolchains;
in stdenv.mkDerivation {
  pname = "zephyr-sdk";
  inherit version;
  system = "x86_64-linux";
  srcs = [ sdk ] ++ toolchains;
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
    tar -xf $3 -C $out
    # to make toolchain compatible with ZEPHYR_TOOLCHAIN_VARIANT="espressif"
    (cd "$out/xtensa-espressif_esp32_zephyr-elf/bin"
     while IFS="" read -r -d "" binary; do
       ln "$binary" "$(echo "$binary" | sed "s/xtensa-espressif_/xtensa-/g" | sed "s/_zephyr-elf/-elf/g")"
     done < <(find . -type f -executable -print0)
    )
    (cd $out; bash ./setup.sh -h)
    rm $out/zephyr-sdk-x86_64-hosttools-standalone-0.9.sh
    runHook postInstall
  '';
}
