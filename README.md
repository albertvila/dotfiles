# Albert Vila's Dotfiles

This is a collection of dotfiles and scripts I use for customizing OS X/Linux to my liking and setting up the software development tools I use on a day-to-day basis. It can be cloned anywhere. It includes a setup script that creates the symlinks from your home directory to the cloned repository.

The setup script is smart enough to back up your existing dotfiles into a `~/.dotfiles_old/` directory if you already have any dotfiles of the same name as the dotfile symlinks being created in your home directory.

I also prefer `zsh` as my shell of choice. As such, the setup script will also clone the `oh-my-zsh` repository from my GitHub. It then checks to see if `zsh` is installed. If `zsh` is installed, and it is not already configured as the default shell, the setup script will execute a `chsh -s $(which zsh)` command. This changes the default shell to zsh, and takes effect as soon as a new zsh is spawned or on next login.

So, to recap, the install script will:

- back up any existing dotfiles in your home directory to `~/.dotfiles_old/`
- create symlinks to the dotfiles in your home directory
- set up `oh-my-zsh` (for use with `zsh`)
- check to see if `zsh` is installed, if it isn't, try to install it
- if zsh is installed, run a `chsh -s` to set it as the default shell

## Installation

```sh
$ git clone https://github.com/albert.vila/dotfiles.git ~/dotfiles
$ cd ~/dotfiles
$ chmod +x setup.sh
$ ./setup.sh
```

## Manual steps after first setup

### iterm2

Install fonts:

```sh
$ git clone git@github.com:powerline/fonts.git
$ cd fonts && ./install.sh
```

Then

- Open iTerm2's preferences.
- Go to colours, load presets and select Solarized. Make sure that the minimum contrast slider is set to low
- Click on text, make sure that "Draw bold text in bright colours" is disabled
- Change the font to Meslo

echo "\ue0b0 \u00b1 \ue0a0 \u27a6 \u2718 \u26a1 \u2699"

### unison

TODO

## Links

iTerm and zsh tips

- <https://www.undefinednull.com/2015/07/31/iterm-tips-and-zsh-plugins-for-better-development-environment/>
- <https://github.com/robbyrussell/oh-my-zsh/wiki/Cheatsheet>

Tmux

- <http://mikebuss.com/2014/02/02/a-beautiful-productive-terminal-experience>
- <http://www.hamvocke.com/blog/a-quick-and-easy-guide-to-tmux/>
- <https://panovski.me/productivity-tools-tmux-and-zsh/>
- <https://danielmiessler.com/study/tmux/#gs.5DmuzbE>

- <https://gist.github.com/andreyvit/2921703> (tmux Cheatsheet)

- <https://tmuxcheatsheet.com/>

- <https://w.amazon.com/index.php/Tmux>

- <https://w.amazon.com/index.php/User:Merlijnh/tmux>

Tmuxinator

- <http://www.avitzurel.com/blog/2014/08/28/my-development-workflow-vim-tmux-terminal-awesomeness/>
- <https://github.com/tmuxinator/tmuxinator>

## Future ToDo

- Check [Prezto](http://jr0cket.co.uk/2013/09/hey-prezto-zsh-for-command-line-heaven.html)
