#!/usr/bin/env bash

filepath=$0
folder=$(dirname $filepath)
binary=$(basename $filepath)
working_dir=`pwd`

# uninstall zsh
cd ~
unlink .oh-my-zsh/custom/zshrc.zsh
cd -

sh -c "$(curl -fsSL https://raw.github.com/robbyrussell/oh-my-zsh/master/tools/uninstall.sh)"

cd ~
unlink .vim
unlink .vimrc
unlink .isort.cfg
unlink .gitignore
unlink .tmux.conf
unlink .tmuxinator.zsh
unlink .tmuxinator/titirrineta.yml
cd -
