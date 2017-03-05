source ~/.tmuxinator.zsh

export PATH=$PATH:/Users/albepuig/bin

alias reset="clear && printf '\e[3J'"
alias tmx="tmux -CC attach || tmux -CC"
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

    echo "\nzsh git plugin"
    echo "--------------"
    echo "gb -> git branch"
    echo "gco xxx -> git checout xxx"
    echo "gcm -> git checkout master"
    echo "gup -> git pull --rebase"
    echo "gm -> git merge"
    echo "grbi -> git rebase -i"
    echo "grbc -> git rebase --continue"
    echo "grbs -> git rebase --skip"
    echo "gst -> git status"
    echo "glol -> git log --graph --pretty"
    echo "gd -> git diff"
    echo "ga -> git add"
    echo "gcmsg 'xxx'-> git commit -m 'xxx'"
    echo "ggp -> git push"
    echo "gsta -> git stash save"
    echo "gstp -> git stash pop"
    echo "gstl -> git stash list"
    echo "grh -> git reset HEAD"
}
