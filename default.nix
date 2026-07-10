{
  pkgs ? import <nixpkgs> { },
  src ? ./.,
  dev ? false,
  warnError ? true,
}:
let
  inherit (pkgs) stdenv;

  # Build configure flags based on features (mirrors oxcaml's default.nix)
  configureFlags =
    let
      mkFlag = bool: name: if bool then "--enable-${name}" else "--disable-${name}";
    in
    [
      "--cache-file=/dev/null"
      "--enable-runtime5"
      (mkFlag dev "dev")
      (mkFlag warnError "warn-error")
    ];

  # Boot compiler, built with the same nixpkgs machinery oxcaml uses for its
  # 5.4.0 boot compiler (minus the oxcaml bootstrap patch).
  ocaml_5_4_0 = pkgs.callPackage (
    import (pkgs.path + "/pkgs/development/compilers/ocaml/generic.nix") {
      major_version = "5";
      minor_version = "4";
      patch_version = "0";
      sha256 = "sha256-36qKLhHHmbwXZdi+9EkRQG7l9IAwJxkDgqk5+IyRImY=";
    }
  ) { };
in
stdenv.mkDerivation {
  pname = "mockscaml";
  version = "5.4.0+mock";
  inherit src configureFlags;

  enableParallelBuilding = true;

  nativeBuildInputs = [
    pkgs.autoconf
    ocaml_5_4_0
  ];

  # We don't use autoreconfHook, mirroring oxcaml (whose configure.ac is
  # incompatible with libtoolize and autoheader).
  preConfigure = ''
    autoconf --force
  '';

  # The default `make` goal builds (and runs) the hello world; `make test`
  # diffs its output against the reference; `make install` installs into
  # $out via the --prefix that stdenv passes to ./configure.
  doCheck = true;
  checkTarget = "test";

  passthru = {
    inherit ocaml_5_4_0;
  };

  meta = { };
}
