let
  version = "19.03";
in
  import (fetchTarball {
    url = "https://nixos.org/channels/nixos-${version}/nixexprs.tar.xz";
    sha256 = "1xzj6d4q9yspvfbbzxsnzzmmg63y6b7w24xjc6663z61cg8iw6km";
  }) {}
