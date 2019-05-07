{
  pkgs ? import ./arion-pkgs.nix,
}: with pkgs; rec {
  inherit go-ethereum;
  geth_vdb = go-ethereum.overrideDerivation (_: {
    src = fetchFromGitHub {
      owner = "vulcanize";
      repo = "go-ethereum";
      # from branch: rpc_statediffing
      rev = "3dd87672fbbcc0498fc412f3c33ea2c2ab7fa953";
      sha256 = "1v03p3nvl27pkizv1vlilnnf70yc83h10l6j2wf3xmn912jwbvl7";
    };
  });
}
