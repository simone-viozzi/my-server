{
  lib,
  config,
  pkgs,
  ...
}:
{
  home = {
    stateVersion = "25.11";

    username = "simone";
    homeDirectory = "/home/simone";
    sessionVariables = {
      PATH = "$HOME/.local/bin:$PATH";
      UV_PYTHON_DOWNLOADS = "never";
    };
  };

  xdg.enable = true;

  xdg.configFile."zsh/.p10k.zsh".source = ./p10k.zsh;

  programs = {
    eza.enable = true;
    fzf.enable = true;
    zoxide.enable = true;

    zsh = {
      enable = true;
      dotDir = "${config.xdg.configHome}/zsh";
      shellAliases = {
        update = "nh os switch --update";
        a = "als";
        la = "eza -la --icons -F";
        lg = "eza -l -F --icons --git --sort=modified";
        ls = "eza --icons -F";
        tree-git = "eza --icons --tree --git-ignore";
        tree = "eza -F --icons --tree";
        df = "duf";
        diff = "delta";
        pod-logs = "for svc in $(systemctl list-units --type=service --all 'podman-*.service' --no-legend | awk '{print $1}'); do echo \"=== $svc ===\"; systemctl status \"$svc\" --no-pager -n3 2>&1; echo; done";
      };
      history = {
        size = 50000;
        ignoreAllDups = true;
        expireDuplicatesFirst = true;
        extended = true;
      };

      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
      autocd = true;

      oh-my-zsh = {
        enable = true;
        custom = "$HOME/.oh-my-zsh/custom/";
        plugins = [
          "git"
          "colored-man-pages"
          "direnv"
          "docker"
          "fzf"
          "git-auto-fetch"
          "aliases"
          "rsync"
          "systemd"
          "gitignore"
        ];
      };

      plugins = [
        {
          name = "powerlevel10k";
          src = pkgs.zsh-powerlevel10k;
          file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
        }
      ];

      siteFunctions = {
        docker-cleanup = ''
          docker container prune -f --filter "until=300h"
          docker image prune -f -a --filter "until=300h"
          docker volume prune -f --filter "until=300h"
          docker network prune -f --filter "until=300h"
          docker builder prune -f --filter "until=300h"
        '';
      };

      initContent = lib.mkMerge [
        (lib.mkBefore ''
          # https://github.com/romkatv/powerlevel10k#how-do-i-initialize-direnv-when-using-instant-prompt
          (( ''${+commands[direnv]} )) && emulate zsh -c "$(direnv export zsh)"

          # Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
          if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
              source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
          fi

          # https://github.com/romkatv/powerlevel10k#how-do-i-initialize-direnv-when-using-instant-prompt
          (( ''${+commands[direnv]} )) && emulate zsh -c "$(direnv hook zsh)"
        '')

        (lib.mkAfter ''
          [[ ! -f "${config.xdg.configHome}/zsh/.p10k.zsh" ]] || source "${config.xdg.configHome}/zsh/.p10k.zsh"

          # Show last logs for a podman container service: pod-log traefik
          pod-log() {
            local svc="podman-''${1}.service"
            journalctl "_SYSTEMD_INVOCATION_ID=$(systemctl show -p InvocationID --value "$svc")" --no-pager
          }

          # Edit a binary sops file with proper decryption/re-encryption
          sops-edit() {
            local f="''${1}"
            local tmp
            tmp=$(mktemp --suffix=.yml)
            sops -d --input-type binary --output-type binary "$f" > "$tmp" || { rm "$tmp"; return 1; }
            eval "''${EDITOR:-vim} \"$tmp\""
            sops -e -i --input-type binary --output-type binary --filename-override "$f" "$tmp" || { rm "$tmp"; return 1; }
            mv "$tmp" "$f"
          }
        '')
      ];
    };

    git = {
      enable = true;
      settings = {
        user = {
          name = "simone-viozzi";
          email = "simoneviozzi97@gmail.com";
        };
        core.editor = "code --wait";
        color.ui = "auto";
        init.defaultBranch = "main";
        help.autocorrect = "prompt";
        commit.verbose = true;
        pull.rebase = true;
        diff = {
          tool = "vscode";
          algorithm = "histogram";
          colorMoved = "zebra";
          mnemonicprefix = true;
          renames = true;
        };
        difftool.vscode.cmd = "code --wait --diff $LOCAL $REMOTE";
        merge.tool = "vscode";
        mergetool.vscode.cmd = "code --wait $MERGED";
        branch.sort = "-committerdate";
        tag.sort = "-v:refname";
        push = {
          autoSetupRemote = true;
          followTags = true;
        };
        fetch = {
          prune = true;
          pruneTags = true;
          all = true;
        };
        rerere = {
          enabled = true;
          autoupdate = true;
        };
        rebase = {
          autosquash = true;
          autoStash = true;
          updateRefs = true;
        };

        credential."https://github.com".helper = [
          ""
          "!gh auth git-credential"
        ];
        credential."https://gist.github.com".helper = [
          ""
          "!gh auth git-credential"
        ];
      };
    };

    delta = {
      enable = true;
      enableGitIntegration = true;
    };

    bottom = {
      enable = true;
      settings.text = pkgs.lib.importTOML ./bottom/config.toml;
    };

    home-manager.enable = true;
  };

  home.packages = [
    pkgs.gh
    pkgs.sops
    pkgs.htop
  ];
}
