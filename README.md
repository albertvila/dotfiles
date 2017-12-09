# Albert Vila's Dotfiles

This is a collection of dotfiles and scripts I use for customizing OS X/Linux to my liking and setting up the software development tools I use on a day-to-day basis. It can be cloned anywhere. It includes a setup script that creates the symlinks from your home directory to the cloned repository.

The setup script is smart enough to back up your existing dotfiles into a `~/.dotfiles_old/` directory if you already have any dotfiles.

I prefer `zsh` as my shell of choice. As such, the setup script will install `prezto` and `zsh`. If `zsh` is installed, and it is not already configured as the default shell, the setup script will execute a `chsh -s $(which zsh)` command. This changes the default shell to zsh, and takes effect as soon as a new zsh is spawned or on next login.

If you prefer `oh-my-zsh` over `prezto` just edit lib/zsh.sh and comment/uncomment the install function.

Check `config.sh` file if you want to know all packages/modules to install and the `lib/osx.sh` to know the osx defaults that will be changed. Vim plugins are located in `vim/plugins.vim`.

Recap
- Setup dotfiles (Note that the first time you ran the setup script it may throw some vim errors, just run the script twice)
- Install osx dev packages for brew/pip/atom and osx defaults
- Install prezto & zsh as shell (https://github.com/sorin-ionescu/prezto)
- Shell theme powerlevel9k (https://github.com/bhilburn/powerlevel9k)
- Colors theme solarized (iterm2, vim, intellij) (http://ethanschoonover.com/solarized)
- Fonts powerline (https://github.com/powerline/fonts)

The customized theme looks like
![Theme](zsh/theme.png)

## Installation

```sh
$ git clone https://github.com/albert.vila/dotfiles.git ~/dotfiles
$ cd ~/dotfiles
$ sh ./setup.sh
```

## Update
Just run `./setup.sh` from time to time to automatically update all modules and applications

### issues
- Permission issues with homebrew under OS X El Capitan. Check /usr/local folder if it has de right permissions. Maybe you need to run
```sudo chown $(whoami):admin /usr/local && sudo chown -R $(whoami):admin /usr/local```

- If you get the error `xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools), missing xcrun at: /Library/Developer/CommandLineTools/usr/bin/xcrun` on OS X High Sierra then you need to reinstall the xcode tools. Run `xcode-select --install` and the errors will disappear

- If you get the error `Undefined subroutine &ExtUtils::ParseXS::errors` when updating vim, you should change the plenv global version to use the system one, update vim, and then get back to the needed perl version

## Manual steps after first setup

### general
1. Open OSX mouse settings and select Natural scroll on trackpad (already present on the `setup_osx` function from `./lib/osx.sh`, pending to check if it works)
2. Open OSX keyboard settings and remove spotlight shortcut
3. Open Alfred and set spotlight shortcut, also select to be opened at login
4. Open spectacle and select to be opened at login

### iterm2
1. Open iTerm2's preferences (do this change for all needed profiles).
2. Go to colors, load presets and select Solarized Dark. Make sure that the minimum contrast slider is set to low
3. Click on text, make sure that "Draw bold text in bright colours" is disabled
4. Change the font to Meslo LG M Regular for Powerline, 12p
5. Go to Global Keys tab and change mapping for Ctrl+Tab / Ctrl+Shift+Tab to Next and Previous tab
6. Add two more mappings to jump at the beginning/end of line
```
    FOR  ACTION         SEND
    ⌘←  "HEX CODE"      0x01
    ⌘→  "HEX CODE"      0x05
```

### intellij
1. Clone git repository
```sh
$ git clone git@github.com:jkaving/intellij-colors-solarized.git
```
2. Go to `File | Import Settings...` and specify the `intellij-colors-solarized` directory
 Click `OK` in the dialog that appears.
3. Restart IntelliJ IDEA
4. Go to `Preferences | Editor | Colors & Fonts` and select one of the new color themes.

### plenv
Once you know that perl version to install, run the following commands
1. plenv install $version
2. plenv rehash
3. plenv global $version
4. plenv install-cpanm
5. You may need to restart your terminal, just type perl --version to be sure you are running the desired version

### awscli
- Run `awscli configure` and set up your aws credentials

### atom
- Open Highlight Selected package settings and unselect `Only Highlight Whole Words`

### unison
- Configure unison if you want bidirectional file sync ([link](https://www.cis.upenn.edu/~bcpierce/unison/))
- GUI interface ([link](http://www.cs.haifa.ac.il/~shuly/unison/))

## External links

iTerm and zsh tips
- <https://www.undefinednull.com/2015/07/31/iterm-tips-and-zsh-plugins-for-better-development-environment/>
- <https://github.com/robbyrussell/oh-my-zsh/wiki/Cheatsheet>
- <http://reasoniamhere.com/2014/01/11/outrageously-useful-tips-to-master-your-z-shell/>

Tmux
- <http://mikebuss.com/2014/02/02/a-beautiful-productive-terminal-experience>
- <http://www.hamvocke.com/blog/a-quick-and-easy-guide-to-tmux/>
- <https://tmuxcheatsheet.com/>

## Future ToDo
- Create a --force flag that removes the ~/.dotfiles and then continues with the setup
- Instead of zsh gradle plugin check and use https://github.com/gradle/gradle-completion
- Be able to install npm modules https://www.leeboonstra.com/developer/mac-osx-how-to-install-jshint-to-the-commandline-sublime-text-with-node/
- Check the chequegourmet page every day and send a notification with the pending amount (osascript -e 'display notification "Hello world!" with title "Hi!" sound name "default"')
