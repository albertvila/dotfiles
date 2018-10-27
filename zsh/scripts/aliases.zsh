alias reset="clear && printf '\e[3J'"
alias vi="vim"

alias glog="git log --graph --format='format:%C(yellow)%h%C(reset) %C(blue)\"%an\" <%ae>%C(reset) %C(magenta)%ar%C(reset)%C(auto)%d%C(reset)%n%s' --date-order -n 5"
alias glogn="git log --graph --format='format:%C(yellow)%h%C(reset) %C(blue)\"%an\" <%ae>%C(reset) %C(magenta)%ar%C(reset)%C(auto)%d%C(reset)%n%s' --date-order -n"
alias gds="gd --staged"

alias -- -="cd -"
alias cat='pygmentize -g'

# From Fasd https://github.com/clvv/fasd
alias z='fasd_cd -d'     # cd, same functionality as j in autojump

# Sometimes the sound stops working
alias fixSound="sudo killall coreaudiod"

# Git stash only for not added files
alias gstk="git stash --keep-index"
