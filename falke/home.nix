{ config, pkgs, lib, ... }:

let
  home-manager = builtins.fetchTarball https://github.com/nix-community/home-manager/archive/release-26.05.tar.gz;
in
{
  imports =
    [
      "${home-manager}/nixos"
    ];

  users.users.alex.isNormalUser = true;
  home-manager.users.alex = { pkgs, ... }: {
    home.packages = [
      pkgs.atool
      pkgs.httpie
      pkgs.k9s
      pkgs.kubecolor
      pkgs.kubectl
      pkgs.lolcat
      pkgs.fish
      pkgs.git
      pkgs.rustup
      pkgs.hyfetch
      pkgs.podman
      pkgs.lazygit
      pkgs.lazydocker
      pkgs.btop
    ];
    programs.bash.enable = true;



    home.file."Documents/greeting.txt".text = ''
                              _
                          .-*'/
                      .-'_  (
                      . .' :  .
                    /  `   _ :
                _.-*'   ._ '* ;
            .-'          `-.-'
          .'       '       ;
          /        .       .:
        .   `-.   :   .  / .
        :      `  ;  ;.+'  `
      .-;       ;    |  `  :
      ; *'._     :-': :   ` ;
      `*'  `+ -'*. ; `*.  \ `*
              `*-*'  *-*'   *-*'
    '';


    home.sessionVariables = {
      EDITOR = "nvim";
      KUBE_EDITOR = "nvim";
    };

    programs.fish = {
      enable = true;
      # shellAliases = {
      #   k = "kubectl"
      # }
      functions = {
        fish_greeting = {
          body = "${pkgs.lolcat}/bin/lolcat ~/Documents/greeting.txt -p 0.75";
        };
        kubectl = {
          wraps = "kubectl";
          body = "command kubecolor $argv";
        };
        k = {
          wraps = "kubectl";
          body = "command kubecolor $argv";
        };
        kubecolor = {
          wraps = "kubectl";
          body = "kubecolor $argv";
        };
        zed = {
          body = "flatpak run dev.zed.Zed $argv";
        };
        code = {
          body = "flatpak run dev.zed.Zed $argv";
        };
      };
    };

    programs.neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;

      extraPackages = with pkgs; [
        ripgrep
        fd
        fzf
        git
        gnumake
        gcc
        unzip
        cargo
      ];
    };

    # The state version is required and should stay at the version you
    # originally installed.
    home.stateVersion = "26.05";
  };
}

