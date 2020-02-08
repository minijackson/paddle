{ nixpkgs ? import <nixpkgs> }:

let pkgs = nixpkgs {
  overlays = [ (self: super: {
    paddle = self.callPackage ./derivation.nix {};
  }) ];
};
in pkgs.paddle
