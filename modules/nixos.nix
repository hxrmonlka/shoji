{inputs, ...}: {
  flake.nixosModules = rec {
    default = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cfg = config.shoji.greeter;
      system = pkgs.stdenv.hostPlatform.system;
      greeter = inputs.self.packages.${system}.greeter;
      mango = config.programs.mango.package;
      dir = "/var/cache/shoji-greeter";
      sessions = config.services.displayManager.sessionData.desktops;
      path = lib.makeBinPath [
        mango
        pkgs.bash
        pkgs.coreutils
        pkgs.gawk
        pkgs.gnused
        pkgs.networkmanager
        pkgs.getent
        pkgs.systemd
      ];
      start = pkgs.writeShellScript "shoji-greeter-start" ''
        exec >${dir}/greeter.log 2>&1
        ${greeter}/bin/shoji-greeter
        echo "qs exited with $?"
        ${mango}/bin/mmsg -d quit
      '';
      mangoConf = pkgs.writeText "shoji-greeter-mango.conf" "exec_once=${pkgs.runtimeShell} ${start} ";
    in {
      options.shoji.greeter.enable = lib.mkEnableOption "the Shoji greeter";
      config = lib.mkIf cfg.enable {
        systemd.tmpfiles.rules = ["d ${dir} 0775 greeter greeter -"];
        services.greetd = {
          enable = true;
          settings.default_session = {
            user = "greeter";
            command = "${pkgs.coreutils}/bin/env -u QT_IM_MODULE -u GTK_IM_MODULE -u XMODIFIERS PATH=${path} HOME=${dir} SHOJI_GREETER_STATE=${dir}/state.json SHOJI_GREETER_SESSION_LOG=${dir}/session.log XDG_DATA_DIRS=${sessions}/share:/run/current-system/sw/share ${mango}/bin/mango -c ${mangoConf}";
          };
        };
      };
    };
    shojiGreeter = default;
  };
}
