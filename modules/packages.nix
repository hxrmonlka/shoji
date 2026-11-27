{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    lib = pkgs.lib;
    system = pkgs.stdenv.hostPlatform.system;
    quickshell = inputs.quickshell.packages.${system}.default;
    m3shapes = inputs.m3shapes.packages.${system}.m3shapes;
    qmlImportPath = "${m3shapes}/${pkgs.qt6.qtbase.qtQmlPrefix}";
    shellSource = lib.fileset.toSource {
      root = ../.;
      fileset =
        lib.fileset.difference (lib.fileset.unions [
          ../shell.qml
          ../Commons
          ../Modules
          ../scripts
        ])
        ../Modules/Greeter;
    };
    cliSource = lib.fileset.toSource {
      root = ../.;
      fileset = ../cli;
    };
    greeterSource = lib.fileset.toSource {
      root = ../.;
      fileset = lib.fileset.unions [
        ../greeter.qml
        ../Commons
        ../Modules/Greeter
        ../Modules/Lock
        ../scripts/greeter-sessions.sh
        ../scripts/greeter-sync.sh
        ../scripts/greeter-users.sh
      ];
    };
    shell = pkgs.stdenvNoCC.mkDerivation {
      pname = "shoji-shell";
      version = "0.1.0";
      src = shellSource;
      nativeBuildInputs = [pkgs.makeWrapper];
      propagatedBuildInputs = [m3shapes];
      dontBuild = true;
      installPhase = ''
        mkdir -p "$out/share/quickshell/shoji"
        cp -R . "$out/share/quickshell/shoji/"
        makeWrapper ${quickshell}/bin/qs "$out/bin/shoji-shell" --add-flags "-p $out/share/quickshell/shoji/shell.qml" --prefix QML_IMPORT_PATH : "${qmlImportPath}"
      '';
      passthru.configPath = "${shell}/share/quickshell/shoji";
      meta = {
        description = "Shoji Quickshell desktop configuration";
        mainProgram = "shoji-shell";
        platforms = lib.platforms.linux;
      };
    };
    cliBinary = pkgs.stdenv.mkDerivation {
      pname = "shoji-cli";
      version = "0.1.0";
      src = cliSource;
      nativeBuildInputs = [pkgs.gnumake];
      buildPhase = "make";
      sourceRoot = "source/cli";
      installPhase = "runHook preInstall; make install PREFIX=$out; runHook postInstall ";
      meta = {
        description = "Command-line interface for the Shoji Quickshell desktop environment";
        mainProgram = "shoji";
        platforms = lib.platforms.linux;
      };
    };
    cliRuntime = pkgs.stdenvNoCC.mkDerivation {
      pname = "shoji-cli-runtime";
      version = "0.1.0";
      dontUnpack = true;
      dontBuild = true;
      nativeBuildInputs = [pkgs.makeWrapper];
      propagatedBuildInputs = [m3shapes];
      installPhase = ''
        mkdir -p "$out/bin"
        makeWrapper ${cliBinary}/bin/shoji "$out/bin/shoji" \
          --prefix QML_IMPORT_PATH : "${qmlImportPath}"
      '';
      meta = {
        description = "Runtime wrapper for the Shoji command-line interface";
        mainProgram = "shoji";
        platforms = lib.platforms.linux;
      };
    };
    greeter = pkgs.stdenvNoCC.mkDerivation {
      pname = "shoji-greeter";
      version = "0.1.0";
      src = greeterSource;
      nativeBuildInputs = [pkgs.makeWrapper];
      propagatedBuildInputs = [m3shapes];
      dontBuild = true;
      installPhase = ''
        mkdir -p "$out/share/quickshell/shoji"
        cp -R . "$out/share/quickshell/shoji/"
        makeWrapper ${quickshell}/bin/qs "$out/bin/shoji-greeter" --add-flags "-p $out/share/quickshell/shoji/greeter.qml" --prefix QML_IMPORT_PATH : "${qmlImportPath}"
      '';
      passthru.configPath = "${greeter}/share/quickshell/shoji";
      meta = {
        description = "Shoji Quickshell greeter";
        mainProgram = "shoji-greeter";
        platforms = lib.platforms.linux;
      };
    };
  in {
    packages = {
      inherit
        shell
        cliBinary
        cliRuntime
        greeter
        m3shapes
        ;
      cli = cliRuntime;
      shoji-shell = shell;
      shoji-cli = cliRuntime;
      shoji-greeter = greeter;
      default = shell;
    };
  };
}
