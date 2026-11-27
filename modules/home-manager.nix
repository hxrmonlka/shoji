{inputs, ...}: {
  flake.homeManagerModules = rec {
    default = {
      config,
      lib,
      pkgs,
      ...
    }: let
      cfg = config.programs.shoji;
      system = pkgs.stdenv.hostPlatform.system;
      packages = inputs.self.packages.${system};
    in {
      options.programs.shoji = {
        enable = lib.mkEnableOption "the Shoji desktop shell";
        cli.enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Install the Shoji command-line interface.";
        };
        config = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Deploy the Shoji Quickshell configuration.";
          };
          target = lib.mkOption {
            type = lib.types.str;
            default = "quickshell/shoji";
            description = "Relative path below XDG_CONFIG_HOME for the Shoji configuration.";
          };
        };
        greeterSync.enable = lib.mkEnableOption "synchronization of Shoji data to the greeter";
      };
      config = lib.mkMerge [
        (lib.mkIf cfg.enable {
          assertions = [
            {
              assertion =
                !cfg.config.enable
                || (
                  cfg.config.target
                  != ""
                  && !(lib.hasPrefix "/" cfg.config.target)
                  && !(lib.hasInfix ".." cfg.config.target)
                );
              message = "programs.shoji.config.target must be a non-empty relative path without parent-directory components.";
            }
          ];
          home.packages = lib.optionals cfg.cli.enable [packages.cli];
          xdg.configFile = lib.mkIf cfg.config.enable {
            ${cfg.config.target} = {
              source = packages.shell.configPath;
              recursive = true;
            };
          };
        })
        (lib.mkIf cfg.greeterSync.enable {
          systemd.user.services.shoji-greeter-sync = {
            Unit.Description = "Sync Shoji wallpaper, colors, and face to the greeter";
            Service = {
              Type = "oneshot";
              Environment = [
                "PATH=${
                  lib.makeBinPath [
                    pkgs.coreutils
                    pkgs.gnused
                  ]
                }"
              ];
              ExecStart = "${pkgs.runtimeShell} ${packages.greeter.configPath}/scripts/greeter-sync.sh /var/cache/shoji-greeter";
            };
            Install.WantedBy = ["default.target"];
          };
          systemd.user.paths.shoji-greeter-sync = {
            Unit.Description = "Watch Shoji wallpaper and colors";
            Path.PathChanged = [
              "%h/.local/state/shoji/wallpaper.json"
              "%h/.local/state/shoji/colors.json"
            ];
            Install.WantedBy = ["default.target"];
          };
        })
      ];
    };
    shoji = default;
  };
}
