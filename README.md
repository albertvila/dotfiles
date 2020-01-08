# Albert Vila's Dotfiles

This is a collection of dotfiles and scripts I use for customizing OS X/Linux to my liking and setting up the software development tools I use on a day-to-day basis. It can be cloned anywhere. It includes a setup script that creates the symlinks from your home directory to the cloned repository.

The setup script is smart enough to back up your existing dotfiles into a `~/.dotfiles_old/` directory if you already have any dotfiles.

I prefer `zsh` as my shell of choice. As such, the setup script will install `prezto` and `zsh`. If `zsh` is installed, and it is not already configured as the default shell, the setup script will execute a `chsh -s $(which zsh)` command. This changes the default shell to zsh, and takes effect as soon as a new zsh is spawned or on next login.

Check `config.sh` file if you want to know all packages/modules to install and the `lib/os.sh` to know the osx/linux defaults that will be changed. Vim plugins are located in `vim/plugins.vim`.

The `config.sh` file contains the default packages/modules, it can be extend with a custom file per user, for example I also use the `config_albert.sh` file.

Recap
- Setup dotfiles (Note that the first time you ran the setup script it may throw some errors, just run the script twice)
- Install osx/linux dev packages for brew/pip/npm/gem/yarn/vscode/brew cask/apt and osx/linux defaults
- Install prezto & zsh as shell (https://github.com/sorin-ionescu/prezto)
- Shell theme powerlevel9k (https://github.com/bhilburn/powerlevel9k)
- Colors theme solarized (iterm2, gnome-terminal, vim, intellij) (http://ethanschoonover.com/solarized)
- Fonts powerline (https://github.com/powerline/fonts)

The customized theme looks like
![Theme](zsh/theme.png)

And with terraform default workspace looks link
![Theme](zsh/theme_terraform.png)

## Installation
Before installing under OSX make sure you have the `git` command installed. If not, just open a `Terminal` and install the command line tools by typing `xcode-select --install`.

```sh
$ git clone https://github.com/albertvila/dotfiles.git ~/dotfiles
$ cd ~/dotfiles
$ sh ./setup.sh
```

If you have a custom file like `config_XXX.sh` then you should use the `./setup -uXXX` command, it will install the default and the custom packages/modules.

## Update
Just run `./setup.sh` from time to time to automatically update all modules and applications

### issues
- Permission issues with homebrew under OS X El Capitan. Check /usr/local folder if it has de right permissions. Maybe you need to run
```sudo chown $(whoami):admin /usr/local && sudo chown -R $(whoami):admin /usr/local```

- If you get the error `xcrun: error: invalid active developer path (/Library/Developer/CommandLineTools), missing xcrun at: /Library/Developer/CommandLineTools/usr/bin/xcrun` on OS X High Sierra then you need to reinstall the xcode tools. Run `xcode-select --install` and the errors will disappear

- If you get the error `Undefined subroutine &ExtUtils::ParseXS::errors` when updating vim, you should change the plenv global version to use the system one, update vim, and then get back to the needed perl version
```
  plenv global system
  ./setup.sh
  plenv global 5.14.2
```

- If you find the following error while updating homebrew apps, then you should remove one of the taps. You can see all of them using `brew tap` and remove one using `brew untap XXX`

```
Error: Cask java8 exists in multiple taps:
  homebrew/cask-versions/java8
  caskroom/versions/java8
```

- If you get issues with gpg, first check the current key is not expired using `gpg --list-secret`. If expired, you can change the expiratoin time using `gpg --edit-key XXX` and then using the `expire` command within the shell

### Chrome extensions
- AdBlock plus
- Bear Chrome
- Dark Reader
- GIFs for Github
- Google Docs Offline
- I don't care about cookies
- JSON Formatter
- Keepa - Amazon Price Tracker
- LastPass: Free Password Manager
- Pushbullet
- Refined GitHub
- Tampermonkey

## Manual steps after first setup

### general
1. Open OSX keyboard settings and remove spotlight shortcut
2. Open Alfred and set spotlight shortcut, also select to be opened at login
3. Import this Alfred Dark Theme from https://www.alfredapp.com/extras/theme/24fhXfBld7/
4. Open spectacle and select to be opened at login

### intellij
1. Clone git repository
```sh
$ git clone git@github.com:jkaving/intellij-colors-solarized.git
```
2. Go to `File | Import Settings...` and specify the `intellij-colors-solarized` directory
 Click `OK` in the dialog that appears.
3. Restart IntelliJ IDEA
4. Go to `Preferences | Editor | Colors & Fonts` and select one of the new color themes.
5. Check `Preferences > Editor > General > Ensure line feed at file end on save`
6. UnCheck `Preferences > Editor > Code Style > Java > Code Generation > Line comment at first column`
7. Check `Preferences > Editor > Code Style > Java > Code Generation > Add a space at comment start`
8. Check `Preferences > Editor > Code Style > Wrap on typing` on Right margin option
9. Update `Editor > Code Style > Java > Imports tab set Class count to use import with '*'` and `Names count to use static import with '*'` to 999
10. Install the following Plugins
- ChecksStyle-IDEA
- Lombok

### jenv
1. Execute `/usr/libexec/java_home -V` to know all java versions installed on your computer
2. `jenv add ...` to add them
3. `jenv global ...` to set up the version you want to use

More information [here](https://www.linkedin.com/pulse/manage-multiple-java-mac-os-x-dinesh-prajapati/)

### plenv
Once you know that perl version to install, run the following commands
1. plenv install $version
2. plenv rehash
3. plenv global $version
4. plenv install-cpanm
5. You may need to restart your terminal, just type perl --version to be sure you are running the desired version

Note: If you get Segmentation fault installing perl versions, just install the perl-build as a plugin using the following command
`git clone git://github.com/tokuhirom/Perl-Build.git $(plenv root)/plugins/perl-build/`

### pyenv
1. Install latest python version using the following command `pyenv install 3.7.3`
2. Set this version as the default one for the whole system `pyenv global 3.7.3`

### nvm
1. Setup the node version you want to use, for example to use node 8 type
```
nvm install 8
nvm use 8
```

### aws
- Run `aws configure` and set up your aws credentials

### alfred workflows
- SSH: Follow steps to use iterm2 instead of Terminal (https://github.com/deanishe/alfred-ssh)

### airmail
- In order to open mailto: links with Airmail, just open Mail > Preferences and set Airmail as the default Email Reader

### Google drive
- If the Strikethrough shortcut does not work, review if it's used by a Chrome extension using `chrome://extensions/shortcuts`

### Chrome DarkReader extension
- In order to fix an issue with Google Sheets when typing on Dark Mode, just change the settings to Filter+ under DarkReader --> More --> Filter+, then select Only for docs.google.com site.
- For the rest of the sites try using the Dynamic filter if the highlighted text on Chrome is not visible

### Gnome-terminal
- Open preferences and select Solarized Dark theme, also change the colors theme accordingly (open a file with vi to see if changes are applied properly). Also you need to untoggle the bold checkbox

### Albert for linux (Alfred alternative)
- Use the following commands to install Albert
```
wget -nv https://download.opensuse.org/repositories/home:manuelschneid3r/xUbuntu_18.04/Release.key -O Release.key
sudo apt-key add - < Release.key
sudo sh -c "echo 'deb http://download.opensuse.org/repositories/home:/manuelschneid3r/xUbuntu_18.04/ /' > /etc/apt/sources.list.d/home:manuelschneid3r.list"
sudo apt update
sudo apt install albert
```

- Additionally, to delete the repository and the trusted key, run the following commands:
```
sudo rm /etc/apt/sources.list.d/home:manuelschneid3r.list
sudo apt-key del E192A257
sudo apt clean
sudo apt update
```
- Then open a Terminal and type `albert`, configure the needed extensions, toggle the enable at login checkbox and set the desired keyword shortcut.

## Old manual steps
Those are now configured automatically, however, I prefer to keep the manual steps here just in case.

### Old issues
- Permission issues with pip, run the following command `sudo easy_install pip`

- If you get the following error `zsh:1: command not found: pygmentize` doing a cat or more, just run the following command `sudo easy_install Pygments`

### general
1. Open OSX mouse settings and select Natural scroll on trackpad (already present on the `setup_osx` function from `./lib/osx.sh`, pending to check if it works)

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
7. Install the Shell integration for the [automatic profile switching](https://iterm2.com/documentation-automatic-profile-switching.html) using (`curl -L https://iterm2.com/shell_integration/install_shell_integration_and_utilities.sh | bash`), more info [here](https://iterm2.com/documentation-shell-integration.html) (re run the setup script after this command, because it overrides the .zshrc symbolic link)

^(\w+)@([\w.-]+):.+\$
^\w+@[\w.-]+:([^$]+)\$

## External links

iTerm and zsh tips
- <https://www.undefinednull.com/2015/07/31/iterm-tips-and-zsh-plugins-for-better-development-environment/>
- <http://reasoniamhere.com/2014/01/11/outrageously-useful-tips-to-master-your-z-shell/>
