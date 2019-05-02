{ pkgs, ... }: let
  inherit (import ./. { inherit pkgs; }) ex_testchain;
  paths = with pkgs; lib.makeBinPath [ coreutils which findutils gnused locale ];
in {
  config.docker-compose.services = {
    ex_testchain = {
      service.useHostStore = true;

      #export PATH=${paths}:$PATH
      service.command = [ "sh" "-c" ''
        trap exit INT
        ${ex_testchain}/bin/ex_testchain foreground
      '' ];

      service.ports = [
        "8500-8600:8500-8600"
      ];

      service.environment = {
        LANG = "C.utf8";
        #GETH_PASSWORD_FILE = ./priv/presets/geth/account_password;
        #GANACHE_WRAPPER_FILE = ./priv/presets/ganache/wrapper.sh;
      };

      service.volumes = [
        "${toString ./priv}:/opt/built/priv"
        "${toString ./data}:/tmp"
      ];

      # service.depends_on = [ "backend" ];
    };

    # backend = { ... }
  };
}
