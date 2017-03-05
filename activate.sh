#!/usr/bin/env bash

filepath=$0
folder=$(dirname $filepath)
binary=$(basename $filepath)
working_dir=`pwd`

git config --global push.default simple
git config --global alias.dag "log --graph --format='format:%C(yellow)%h%C(reset) %C(blue)\"%an\" <%ae>%C(reset) %C(magenta)%ar%C(reset)%C(auto)%d%C(reset)%n%s' --date-order"
git config --global core.editor /usr/bin/vim
git submodule update --init

# install zsh
sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
# you need to exit after installation from child shell created

cd ~
rm -r .vim
ln -si "$working_dir/$folder/vim" .vim
ln -si "$working_dir/$folder/vimrc" .vimrc
ln -si "$working_dir/$folder/gitignore" .gitignore
ln -si "$working_dir/$folder/isort.cfg" .isort.cfg
git config --global core.excludesfile '~/.gitignore'

# initialize Vim plugins
vim +PluginInstall +qall

cd -

cd ~
echo "setting up personal .zshrc ..."
ln -si "$working_dir/$folder/zshrc" .oh-my-zsh/custom/zshrc.zsh
echo $'\360\237\215\251' " [DONE]"

echo "setting up tmux ..."
ln -si "$working_dir/$folder/tmux/tmux.conf" .tmux.conf
ln -si "$working_dir/$folder/tmux/tmuxinator.zsh" .tmuxinator.zsh
ln -si "$working_dir/$folder/tmux/titirrineta.yml" .tmuxinator/titirrineta.yml
echo $'\360\237\215\251' " [DONE]"

cd -
echo "If you don't see the theme in zsh, update the profile in iterm2's configuration to use that shell command -> /bin/zsh --login"
echo "Edit the ~/.zshrc file and change plugins=(git z h)"
