{
  pkgs ? import ./arion-pkgs.nix,

  gis ? import (fetchTarball {
    url = https://github.com/icetan/nix-git-ignore-source/archive/v1.0.0.tar.gz;
    sha256 = "1mnpab6x0bnshpp0acddylpa3dslhzd2m1kk3n0k23jqf9ddz57k";
  }) { inherit pkgs; },

  mixnix-src ? fetchGit {
    url = https://gitlab.com/icetan/mixnix.git;
    rev = "31651c506dca78e5b335736490dd24242c054563";
  },

  mix2nix ? pkgs.callPackage (import "${mixnix-src}/nix/mix2nix.nix") {}
}:

let
  inherit (builtins) mapAttrs toFile readFile;
  inherit (mix2nix) mkMixNix mkPureMixPackage;
  updateLockAttrs = lock: attrs: lock // (mapAttrs (k: v: lock."${k}" // attrs."${k}") attrs);
in {
  ex_testchain = let
    name = "ex_testchain";
    version = "0.1.0";
    lock = import (mkMixNix name ./mix.lock);
    importedMixNix = updateLockAttrs lock {
      ksha3 = { builder = "rebar3"; };
      libsecp256k1 = { builder = "rebar3"; };
    };
    runtimDeps = with pkgs; lib.makeBinPath [
      coreutils gnugrep gnused gawk gnutar
      bash openssl
    ];
    beamPackages = pkgs.beam.packages.erlangR21;
  in mkPureMixPackage {
    inherit name version importedMixNix runtimDeps;
    inherit (beamPackages) erlang elixir;

    src = gis.gitIgnoreSourceFile {
      src = ./.;
      ignorefile = (readFile ./.gitignore) + ''
        .git
        *.nix
      '';
    };
    buildInputs = with pkgs; [ makeWrapper ];

    postBuild = ''
      mix release --no-tar --verbose
    '';

    postInstall = ''
      mkdir -p $out
      cp -r -t $out _build/$MIX_ENV/rel/${name}/*
      wrapProgram $out/bin/${name} \
        --prefix PATH : $runtimDeps \
        --set RELEASE_READ_ONLY 1
    '';

    mixConfig = {
      distillery = {...}: { patches = [ ./patches/distillery.patch ]; };
      ksha3 = {...}: {
        compilePorts = true;
        preBuild = ''
          cp ${./patches/ksha3_packages.idx} .cache/rebar3/hex/packages.idx
        '';
      };
      libsecp256k1 = {...}: {
        patches = [ ./patches/libsecp256k1.patch ];
        buildInputs = with pkgs; [ automake autoconf pkgconfig libtool ];
        preBuild = ''
          cp -r ${fetchGit {
            url = https://github.com/bitcoin/secp256k1;
            rev = "5a91bd768faaa974e00301e662fd8f2aa75a122a";
          }} c_src/secp256k1
          chmod -R u+w c_src/secp256k1
        '';
      };
    };
  };
}
