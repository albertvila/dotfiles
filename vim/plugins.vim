set nocompatible              " be iMproved, required
filetype off                  " required

" https://github.com/VundleVim/Vundle.vim
" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" alternatively, pass a path where Vundle should install plugins call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

"*** Add your plugins below ***

" Vim theme like zsh powerline
Plugin 'vim-airline/vim-airline'
Plugin 'vim-airline/vim-airline-themes'

" Going to be installed with a git submodule, because otherwise we cannot run the vim +PluginInstall command as it fails for missing solarized
" Plugin 'altercation/vim-colors-solarized'

" Customized welcome page
Plugin 'mhinz/vim-startify'

" Navigate between folders
Plugin 'scrooloose/nerdtree.git'

" Search files inside vim using Ctrl+p
Plugin 'ctrlpvim/ctrlp.vim'

" https://github.com/terryma/vim-multiple-cursors
Plugin 'terryma/vim-multiple-cursors'

" Show a git diff on the left (https://github.com/airblade/vim-gitgutter)
Plugin 'airblade/vim-gitgutter'

" Perl autocomplete, it works typing ctrl+x + ctrl+o
Plugin 'c9s/perlomni.vim'

" The following 2 plugins allows the autocompletion to show as you type
Plugin 'othree/vim-autocomplpop'
Plugin 'eparreno/vim-l9'

" Comment functions so powerful (https://github.com/scrooloose/nerdcommenter)
Plugin 'scrooloose/nerdcommenter'

" When you do searches will show you "Match 2 of 4" in the status line"
Plugin 'henrik/vim-indexed-search'

"*** Add your plugins above ***

" All of your Plugins must be added before the following line
call vundle#end()            " required
filetype plugin indent on    " required
" To ignore plugin indent changes, instead use:
"filetype plugin on
"
" Brief help
" :PluginList       - lists configured plugins
" :PluginInstall    - installs plugins; append `!` to update or just :PluginUpdate
" :PluginSearch foo - searches for foo; append `!` to refresh local cache
" :PluginClean      - confirms removal of unused plugins; append `!` to auto-approve removal
"
" see :h vundle for more details or wiki for FAQ
" Put your non-Plugin stuff after this line
