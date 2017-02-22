export PATH=$PATH:/Users/albepuig/bin

alias reset="clear && printf '\e[3J'"
alias tmux="/apollo/env/envImprovement/bin/tmux -CC attach || /apollo/env/envImprovement/bin/tmux -CC"
alias vi='vim'

function help-git {
    echo "Showing git help"
    echo "----------------"

    echo "\nSquash commits"
    echo "git rebase -i"
    echo "\nMerge from a branch into master"
    echo "git checkout master\ngit merge branch_name\ngit rebase -i\ngit pull -r\ngit push"
    echo "\nMove last 2 local commits into a branch"
    echo "git branch new_branch_name \ngit reset --hard HEAD~2"
    echo "\nRollback last local commit to stagged phase"
    echo "git reset --soft HEAD~1"
}
