# fish config — managed in dotfiles repo: home/.config/fish/
# Covers the interactive login shell only, never script interpreters.

# --- PATH & env (all shells) ---
# Homebrew first: pyenv/direnv/starship/pi all live in /opt/homebrew/bin, and
# fish never runs path_helper, so nothing else puts it on PATH.
eval (/opt/homebrew/bin/brew shellenv)
# Order matters: each fish_add_path prepends, so call lowest-priority first.
fish_add_path ~/bin ~/.local/bin
set -l pip_user_bin (python3 -m site --user-base 2>/dev/null)/bin
test -n "$pip_user_bin"; and fish_add_path $pip_user_bin
test -d ~/.jenv; and fish_add_path ~/.jenv/bin
test -d ~/.nodenv; and fish_add_path ~/.nodenv/bin
if test -d ~/.pyenv
    set -gx PYENV_ROOT $HOME/.pyenv
    fish_add_path $PYENV_ROOT/bin
    pyenv init - | source
end
set -gx BUN_INSTALL $HOME/.bun
test -d $BUN_INSTALL/bin; and fish_add_path $BUN_INSTALL/bin

# Load secrets (~/.env, plain KEY=value lines) — all shells, pi reads these
if test -f ~/.env
    for line in (cat ~/.env)
        set -l kv (string split -m1 = -- $line)
        test (count $kv) -eq 2; and set -gx $kv[1] $kv[2]
    end
end

set -gx EDITOR vim
set -gx MORE -R
set -gx LESSOPEN "|bat --color=always --style=plain %s"

set -gx ANDROID_HOME $HOME/Library/Android/sdk
fish_add_path -a $ANDROID_HOME/emulator $ANDROID_HOME/platform-tools $ANDROID_HOME/cmdline-tools/latest/bin ~/.maestro/bin

# --- interactive only ---
if status is-interactive
    set -gx GPG_TTY (tty)
    direnv hook fish | source
    starship init fish | source
    # `z` jump: zoxide tracks dirs on PWD change (replaced fasd)
    zoxide init fish --cmd z | source
    # override zoxide's no-arg `cd ~` with the old frecent-dir listing
    function z --description "zoxide jump; bare z lists frecent dirs"
        if test (count $argv) -eq 0
            zoxide query -l | head -n 15
            return
        end
        __zoxide_z $argv
    end
    # tab after `z` offers frecent dirs: drop zoxide's alias-wrap rule first,
    # otherwise it re-enables fish's plain file completion
    complete --erase --command z
    complete -c z -f -a '(zoxide query -l)'
end
