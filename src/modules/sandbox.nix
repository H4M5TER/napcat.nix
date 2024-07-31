{ config, pkgs, lib, ... }: let
  cfg = config.sandbox;
  fonts = pkgs.makeFontsConf {
    fontDirectories = with pkgs; [ source-han-sans ];
  };
in {
  options.sandbox = {
    name = lib.mkOption {
      type = lib.types.str;
      description = "name of output executable";
    };
    program = lib.mkOption {
      type = lib.types.pathInStore;
      description = "program runs in sandbox";
    };
    dns = lib.mkOption {
      type = lib.types.str;
      description = "dns server used in sandbox";
      default = "223.5.5.5";
    };
    display = lib.mkOption {
      type = lib.types.int;
      description = "DISPLAY used by Xvfb and x11vnc";
      default = 114;
    };
    port = lib.mkOption {
      type = lib.types.int;
      description = "listen port of x11vnc";
      default = 5900;
    };
    sandbox = lib.mkOption {
      type = lib.types.path;
      description = "sandbox";
    };
  };
  config.sandbox.sandbox = pkgs.writeScriptBin cfg.name ''
    #!${pkgs.runtimeShell}
    mkdir -p data
    ${pkgs.bubblewrap}/bin/bwrap \
      --unshare-all \
      --share-net \
      --as-pid-1 \
      --uid 0 --gid 0 \
      --clearenv \
      --ro-bind /nix/store /nix/store \
      --bind ./data /root \
      --proc /proc \
      --dev /dev \
      --tmpfs /tmp \
      ${pkgs.writeScript "sandbox" ''
        #!${pkgs.runtimeShell}

        createService() {
          mkdir -p /services/$1
          echo -e "#!${pkgs.runtimeShell}\n$2" > /services/$1/run
          chmod +x /services/$1/run
        }

        export PATH=${lib.makeBinPath (with pkgs; [
          busybox xorg.xorgserver x11vnc
        ])}
        export HOME=/root
        export XDG_DATA_HOME=/root/.local/share
        export XDG_CONFIG_HOME=/root/.config
        export TERM=xterm
        mkdir -p /root/{.local/share,.config} /etc/{ssl/certs,fonts}
        mkdir -p /usr/bin /bin
        echo "root:x:0:0::/root:${pkgs.runtimeShell}" > /etc/passwd
        echo "root:x:0:" > /etc/group
        echo "nameserver ${cfg.dns}" > /etc/resolv.conf
        ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt
        ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
        ln -s ${fonts} /etc/fonts/fonts.conf
        ln -s $(which env) /usr/bin/env
        ln -s $(which sh) /bin/sh
        export DISPLAY=':${toString cfg.display}'
        createService xvfb 'Xvfb :${toString cfg.display}'
        createService x11vnc 'x11vnc -forever -display :${toString cfg.display} -rfbport ${toString cfg.port}'
        createService program "${cfg.program} $@"
        runsvdir /services
      ''} "$@"
  '';
}
