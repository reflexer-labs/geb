{ dappPkgs ? (
    import (fetchGit "https://github.com/reflexer-labs/nixpkgs-pin") {}
  ).dappPkgsVersions.seth-0_8_4
}:

with dappPkgs;

let
  dapp' = dapp.override {
    solc = solc-versions.solc_0_6.7;
  };
in mkShell {
  buildInputs = [ dapp' ];
}
