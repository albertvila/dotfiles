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

gbranch() {
    git fetch

    currentBranch=`git branch | grep \* | cut -d ' ' -f2`

    if test "$currentBranch" = 'main'; then
        baseBranch='m'
    else
        if test "$currentBranch" = 'master'; then
            baseBranch='m'
        else
            if test "$currentBranch" = 'develop'; then
                baseBranch='d'
            else
                echo "Wrong branch, you should be in main or develop branch"
                exit 1;
            fi
        fi
    fi

    if test "$1"; then
        name='albert'_$1
        name="${name// /_}"
    else
        name='albert'
    fi

    today=$(gdate +"%Y%m%d")
    shortCommitHash=`git rev-parse --short HEAD`
    randomNumber=${(l:5::0:)${RANDOM}}
    newBranch="$baseBranch"-"${name:l}"_"$today"_"$shortCommitHash"_"$randomNumber"

    echo "Creating a new branch $newBranch and switching into it"
    git checkout -b $newBranch origin/$currentBranch
    git push -u origin $newBranch
}
