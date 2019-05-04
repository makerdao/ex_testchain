let
  dapp-version = "dapp/0.16.0";
in
  import (fetchTarball {
    url = "https://github.com/dapphub/dapptools/tarball/${dapp-version}";
    sha256 = "06k4grj8spdxg5758sqz908f92hp707khsnb2dygsl0229z4rhxl";
  }) {}

  #import (fetchTarball {
  #  url = "https://nixos.org/channels/nixos-${version}/nixexprs.tar.xz";
  #  sha256 = "1xzj6d4q9yspvfbbzxsnzzmmg63y6b7w24xjc6663z61cg8iw6km";
  #}) {}
