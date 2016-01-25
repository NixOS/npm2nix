{ }:

let

  pkgs = import <nixpkgs> {};

in pkgs.stdenv.mkDerivation rec {
  name = "npm2nix-env";
  src = ./.;
  buildInputs = with pkgs; [
    nodejs-0_10
  ];
  shellHook = ''
    npm install .
  '';
}
