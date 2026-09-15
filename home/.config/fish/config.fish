# fish config — managed in dotfiles repo: home/.config/fish/
# Covers the interactive login shell only, never script interpreters.

# --- PATH & env (all shells) ---
# Homebrew first: pyenv/direnv/starship/pi all live in /opt/homebrew/bin, and
# fish (unlike zsh) never runs path_helper, so nothing else puts it on PATH.
eval (/opt/homebrew/bin/brew shellenv)
# Order mirrors .zshrc: each fish_add_path prepends, so call lowest-priority first.
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
end
