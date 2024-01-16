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
          pp = pkgs.python3.pkgs;

          # Build the Zephyr SDK as a nix package.
          new-zephyr-sdk-pkg = { stdenv, fetchurl, which, python38, wget, file
            , cmake, libusb, autoPatchelfHook }:
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
            };

          zephyr-sdk = self.packages."${system}".zephyr-sdk;

          python3west = final.python3.withPackages (pp:
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
          baseInputs = [
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
            pkgs.nrfutil
            # nRF-Command-Line-Tools
            # jlink
            segger-jlink
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
          zephyr-sdk = pkgs.callPackage new-zephyr-sdk-pkg { };
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
          my-west-esp32 =
            let esp32-toolchain = (pkgs.callPackage ./esp32-toolchain.nix { });
            in my-west-fun {
              pnameext = "-esp32";
              moreBuildInputs = [
                esptool
                esp32-toolchain
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
                --set ZEPHYR_TOOLCHAIN_VARIANT "espressif" \
                --set ESPRESSIF_TOOLCHAIN_PATH "${esp32-toolchain}"
              '';
            };
        });
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};

          zephyr-sdk = self.packages."${system}".zephyr-sdk;

        in {
          default = pkgs.mkShell {
            nativeBuildInputs = packages;

            # For Zephyr work, we need to initialize some environment variables,
            # and then invoke the zephyr setup script.
            shellHook = ''
              export ZEPHYR_SDK_INSTALL_DIR=${zephyr-sdk}
              export PATH=$PATH:${zephyr-sdk}/arm-zephyr-eabi/bin
              export VIA_WORKSPACE_PATH="$(realpath ./)"
              echo "VIA_WORKSPACE_PATH=$VIA_WORKSPACE_PATH"
              source "$VIA_WORKSPACE_PATH"/zephyr/zephyr-env.sh
            '';
          };
        });
    };
}
