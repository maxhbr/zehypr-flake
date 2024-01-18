{
  description = "Flake used to setup development environment for Zephyr";
  inputs.nixpkgs.url = "nixpkgs/nixos-23.11";

  outputs = { self, nixpkgs }@inputs:
    let
      # Nixpkgs instantiated for supported system types
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });

      lastModifiedDate =
        self.lastModifiedDate or self.lastModified or "19700101";
      version = builtins.substring 0 8 lastModifiedDate;

      supportedSystems = [
        "x86_64-linux"
      ]; # "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
          lib = pkgs.lib;
          stdenv = pkgs.stdenv;
          pp = pkgs.python3.pkgs;

          zephyr-sdk = self.packages."${system}".zephyr-sdk;

          python3west = pkgs.python3.withPackages (pp:
            with pp; [
              west

              autopep8
              pyelftools
              pyyaml
              pykwalify
              canopen
              packaging
              progress
              psutil
              anytree
              intelhex
              self.packages."${system}".imgtool

              cryptography
              intelhex
              click
              cbor2

              # For mcuboot CI
              toml

              # For twister
              tabulate
              ply

              # For TFM
              pyasn1
              graphviz
              jinja2

              requests
              beautifulsoup4

              # These are here because pip stupidly keeps trying to install
              # these in /nix/store.
              wcwidth
              sortedcontainers

              ## from old flake
              docutils
              wheel
              breathe
              sphinx
              sphinx_rtd_theme
              # pyyaml
              # ply
              # pyelftools
              pyserial
              # pykwalify
              colorama
              pillow
              # intelhex
              pytest
              gcovr
              # # pyocd
              # gui
              tkinter
              # esp
              future
              # cryptography
              setuptools
              pyparsing
              # click
              kconfiglib
              # SEGGER
              pylink-square
            ]);
          baseInputs = with pkgs; [
            ninja
            which
            cmake
            dtc
            gperf
            ccache
            gmp.dev
            # openocd
            dfu-util
            bossa
            # pkgs.nrfutil # UNFREE
            # nRF-Command-Line-Tools
            # jlink
            srecord # for srec_cat

            zephyr-sdk

            llvmPackages_17.clang-unwrapped # Newer than base clang
            gnat
            zig
            zls
            rustup
            glibc_multi
          ];
          my-west-fun =
            { pnameext ? "", moreBuildInputs ? [ ], wrapperArgs ? "" }:
            (stdenv.mkDerivation (rec {
              pname = "my-west" + pnameext;
              inherit version;

              buildInputs = moreBuildInputs ++ baseInputs
                ++ (with pkgs; [ git python3west ]);

              nativeBuildInputs = [ pkgs.makeWrapper ];

              phases = [ "installPhase" ];

              installPhase = ''
                mkdir -p $out/bin
                makeWrapper ${python3west}/bin/west $out/bin/west${pnameext} \
                  --prefix PATH : "${lib.makeBinPath buildInputs}" \
                  --prefix LD_LIBRARY_PATH : "${
                    lib.makeLibraryPath buildInputs
                  }" \
                  --set ZEPHYR_SDK_INSTALL_DIR ${zephyr-sdk} \
                  --set PYTHONPATH "${python3west}/${python3west.sitePackages}" ${wrapperArgs}
              '';
            }));
        in {
          zephyr-sdk = pkgs.callPackage ./zephyr-sdk.nix { };
          imgtool = pp.buildPythonPackage rec {
            version = "1.10.0";
            pname = "imgtool";

            src = pp.fetchPypi {
              inherit pname version;
              sha256 = "sha256-A7NOdZNKw9lufEK2vK8Rzq9PRT98bybBfXJr0YMQS0A=";
            };

            propagatedBuildInputs = with pp; [
              cbor2
              click
              intelhex
              cryptography
            ];
            doCheck = false;
            pythonImportsCheck = [ "imgtool" ];
          };
          my-west = my-west-fun { };
          my-west-arm = let
            gcc = pkgs.gcc-arm-embedded;
            binutils = pkgs.pkgsCross.arm-embedded.buildPackages.binutils;
            arm-toolchain = pkgs.buildEnv {
              name = "arm-toolchain";
              paths = [ gcc binutils ] ++ baseInputs;
            };
          in my-west-fun {
            pnameext = "-arm";
            moreBuildInputs = [ gcc binutils stdenv.cc.cc.lib ];
            wrapperArgs = ''
              --set ZEPHYR_TOOLCHAIN_VARIANT "gnuarmemb" \
              --set GNUARMEMB_TOOLCHAIN_PATH "${arm-toolchain}"
            '';
          };
          # my-west-riscv = my-west-fun {
          #   pnameext = "-riscv";
          #   wrapperArgs = ''
          #     --set ZEPHYR_TOOLCHAIN_VARIANT zephyr \
          #     --set OPENOCD ${pkgs.openocd}/bin/openocd
          #   '';
          # };
          my-west-esp32 = my-west-fun {
              pnameext = "-esp32";
              moreBuildInputs = with pkgs; [
                esptool
                gawk
                gettext
                automake
                bison
                flex
                texinfo
                help2man
                libtool
                autoconf
                ncurses5
                glibcLocales
              ];
              wrapperArgs = ''
                --set NIX_CFLAGS_LINK -lncurses \
                --set ZEPHYR_TOOLCHAIN_VARIANT "zephyr" \
                --set ESPRESSIF_TOOLCHAIN_PATH "${zephyr-sdk}/xtensa-espressif_esp32_zephyr-elf"
              '';
            };
        });

      homeManagerModules.zephyr = ({ config, lib, pkgs, ... }:
        let inherit (pkgs.stdenv.hostPlatform) system;
        in {
          config = {
            home.packages = (with pkgs; [
              picocom
              minicom
              # (writeShellScriptBin "flash-nrf52840dongle" ''
              #   set -euo pipefail
              #   in=build/zephyr/zephyr.hex
              #   out=build/zephyr.zip
              #   if [[ -f "$in" ]]; then
              #     set -x
              #     ${pkgs.nrfutil}/bin/nrfutil pkg generate --hw-version 52 --sd-req=0x00 \
              #             --application "$in" \
              #             --application-version 1 "$out"
              #     ${pkgs.nrfutil}/bin/nrfutil dfu usb-serial -pkg "$out" -p "''${1:-/dev/ttyACM0}"
              #   else
              #     echo "\$in=$in not found"
              #   fi
              # '')
              (writeShellScriptBin "clang-format" ''
                exec ${llvmPackages.clang-unwrapped}/bin/clang-format "$@"
              '')
              teensy-loader-cli
              tytools
            ]) ++ (with self.packages."${system}"; [
              zephyr-sdk
              my-west
              my-west-arm
              my-west-esp32
            ]);
          };
        });

      nixosModules.zephyr = ({ config, lib, pkgs, ... }:
        let
          # platformio-udev-rules = pkgs.writeTextFile {
          #   name = "platformio-udev-rules";
          #   text = builtins.readFile
          #     "${inputs.platformio-core}/platformio/assets/system/99-platformio-udev.rules";
          #   destination = "/etc/udev/rules.d/99-platformio.rules";
          # };
          segger-modemmanager-blacklist-udev-rules = pkgs.writeTextFile {
            name = "segger-modemmanager-blacklist-udev-rules";
            # https://docs.zephyrproject.org/2.5.0/guides/tools/nordic_segger.html#gnu-linux
            text = ''ATTRS{idVendor}=="1366", ENV{ID_MM_DEVICE_IGNORE}="1"'';
            destination =
              "/etc/udev/rules.d/99-segger-modemmanager-blacklist.rules";
          };
        in {
          nixpkgs.config.allowUnfree = true;
          nixpkgs.config.segger-jlink.acceptLicense = true;
          home-manager.sharedModules = [ self.homeManagerModules.zephyr ];
          services.udev.packages = [
            # platformio-udev-rules
            pkgs.platformio
            segger-modemmanager-blacklist-udev-rules
            pkgs.openocd
            # pkgs.segger-jlink
            pkgs.stlink
            pkgs.teensy-udev-rules
          ];
        });

      apps = forAllSystems (system: {
        west = {
          type = "app";
          program = "${self.packages.${system}.my-west}/bin/west";
        };
        west-arm = {
          type = "app";
          program = "${self.packages.${system}.my-west-arm}/bin/west-arm";
        };
        west-esp32 = {
          type = "app";
          program = "${self.packages.${system}.my-west-esp32}/bin/west-esp32";
        };
      });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};

          zephyr-sdk = self.packages."${system}".zephyr-sdk;

        in {
          default = pkgs.mkShell {
            nativeBuildInputs = with self.packages."${system}"; [
              zephyr-sdk
              my-west
              my-west-arm
              my-west-esp32
            ];

            # For Zephyr work, we need to initialize some environment variables,
            # and then invoke the zephyr setup script.
            shellHook = ''
              export ZEPHYR_SDK_INSTALL_DIR=${zephyr-sdk}
              export PATH=$PATH:${zephyr-sdk}/arm-zephyr-eabi/bin
              # export VIA_WORKSPACE_PATH="$(realpath ./)"
              # echo "VIA_WORKSPACE_PATH=$VIA_WORKSPACE_PATH"
              # source "$VIA_WORKSPACE_PATH"/zephyr/zephyr-env.sh
            '';
          };
        });
    };
}
