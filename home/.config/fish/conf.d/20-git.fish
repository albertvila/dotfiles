# Bulk git aliases + helpers, ported from the oh-my-zsh git plugin
# (verbatim upstream). compdef/zstyle/autoload dropped:
# fish completes natively. is-at-least conditionals resolved for git 2.55.

# --- helper functions ---
function git_current_branch --description "name of current branch or short sha"
    set -l ref (command git symbolic-ref --quiet HEAD 2>/dev/null)
    set -l ret $status
    if test $ret -ne 0
        if test $ret -eq 128
            return
        end
        set ref (command git rev-parse --short HEAD 2>/dev/null); or return
    end
    string replace -r '^refs/heads/' '' $ref
end

function current_branch
    git_current_branch
end

function _git_log_prettily
    if test -n "$argv[1]"
        git log --pretty=$argv[1]
    end
end

function work_in_progress
    command git -c log.showSignature=false log -n 1 2>/dev/null | grep -q -- "--wip--"; and echo "WIP!!"
end

function git_main_branch
    command git rev-parse --git-dir &>/dev/null; or return
    for ref in refs/heads/{main,trunk,mainline,default} refs/remotes/{origin,upstream}/{main,trunk,mainline,default}
        if command git show-ref -q --verify $ref
            basename $ref
            return
        end
    end
    echo master
end

function git_develop_branch
    command git rev-parse --git-dir &>/dev/null; or return
    for branch in dev devel development
        if command git show-ref -q --verify refs/heads/$branch
            echo $branch
            return
        end
    end
    echo develop
end

function gccd
    command git clone --recurse-submodules $argv
    set -l last $argv[-1]
    if test -d "$last"
        cd "$last"
    else
        cd (basename $last .git)
    end
end

function gdnolock
    git diff $argv ":(exclude)package-lock.json" ":(exclude)*.lock"
end

function gdv
    git diff -w $argv | view -
end

function ggf
    set -l b (git_current_branch)
    test (count $argv) -eq 1; and set b $argv[1]
    git push --force origin $b
end

function ggfl
    set -l b (git_current_branch)
    test (count $argv) -eq 1; and set b $argv[1]
    git push --force-with-lease origin $b
end

function ggl
    if test (count $argv) -ne 0; and test (count $argv) -ne 1
        git pull origin $argv
    else if test (count $argv) -eq 1
        git pull origin $argv[1]
    else
        git pull origin (git_current_branch)
    end
end

function ggp
    if test (count $argv) -ne 0; and test (count $argv) -ne 1
        git push origin $argv
    else if test (count $argv) -eq 1
        git push origin $argv[1]
    else
        git push origin (git_current_branch)
    end
end

function ggpnp
    if test (count $argv) -eq 0
        ggl; and ggp
    else
        ggl $argv; and ggp $argv
    end
end

function ggu
    set -l b (git_current_branch)
    test (count $argv) -eq 1; and set b $argv[1]
    git pull --rebase origin $b
end

function grename --description "rename branch locally and on origin"
    if test -z "$argv[1]"; or test -z "$argv[2]"
        echo "Usage: grename old_branch new_branch"
        return 1
    end
    git branch -m "$argv[1]" "$argv[2]"
    if git push origin :"$argv[1]"
        git push --set-upstream origin "$argv[2]"
    end
end

function gbgd
    set -l res (gbg | awk '{print $1}')
    test -n "$res"; and echo $res | xargs git branch -d
end

function gbgD
    set -l res (gbg | awk '{print $1}')
    test -n "$res"; and echo $res | xargs git branch -D
end

function gtl
    set -l pat '*'
    test (count $argv) -ge 1; and set pat "$argv[1]*"
    git tag --sort=-v:refname -n --list $pat
end

# --- resolved version conditionals (git 2.55) ---
alias gfa 'git fetch --all --prune --jobs=10'
alias gsta 'git stash push'
alias gpsupf 'git push --set-upstream origin $(git_current_branch) --force-with-lease --force-if-includes'
alias gpf 'git push --force-with-lease --force-if-includes'

# --- bulk aliases ---
alias g 'git'
alias ga 'git add'
alias gaa 'git add --all'
alias gapa 'git add --patch'
alias gau 'git add --update'
alias gav 'git add --verbose'
alias gap 'git apply'
alias gapt 'git apply --3way'
alias gb 'git branch'
alias gba 'git branch --all'
alias gbd 'git branch --delete'
function gbda --description "delete merged branches except main/develop"
    set -l main (git_main_branch)
    set -l dev (git_develop_branch)
    git branch --no-color --merged | command grep -vE "^([+*]|\s*($main|$dev)\s*\$)" | command xargs git branch --delete 2>/dev/null
end
alias gbD 'git branch --delete --force'
alias gbg 'git branch -vv | grep ": gone\]"'
alias gbl 'git blame -b -w'
alias gbnm 'git branch --no-merged'
alias gbr 'git branch --remote'
alias gbs 'git bisect'
alias gbsb 'git bisect bad'
alias gbsg 'git bisect good'
alias gbsr 'git bisect reset'
alias gbss 'git bisect start'
alias gc 'git commit --verbose'
alias gc! 'git commit --verbose --amend'
alias gcn! 'git commit --verbose --no-edit --amend'
alias gca 'git commit --verbose --all'
alias gca! 'git commit --verbose --all --amend'
alias gcan! 'git commit --verbose --all --no-edit --amend'
alias gcans! 'git commit --verbose --all --signoff --no-edit --amend'
alias gcam 'git commit --all --message'
alias gcsm 'git commit --signoff --message'
alias gcas 'git commit --all --signoff'
alias gcasm 'git commit --all --signoff --message'
alias gcb 'git checkout -b'
alias gcf 'git config --list'
alias gcl 'git clone --recurse-submodules'
alias gclean 'git clean --interactive -d'
alias gpristine 'git reset --hard && git clean --force -dfx'
alias gcm 'git checkout $(git_main_branch)'
alias gcd 'git checkout $(git_develop_branch)'
alias gcmsg 'git commit --message'
alias gco 'git checkout'
alias gcor 'git checkout --recurse-submodules'
alias gcount 'git shortlog --summary --numbered'
alias gcp 'git cherry-pick'
alias gcpa 'git cherry-pick --abort'
alias gcpc 'git cherry-pick --continue'
alias gcs 'git commit --gpg-sign'
alias gcss 'git commit --gpg-sign --signoff'
alias gcssm 'git commit --gpg-sign --signoff --message'
alias gd 'git diff'
alias gdca 'git diff --cached'
alias gdcw 'git diff --cached --word-diff'
alias gdct 'git describe --tags $(git rev-list --tags --max-count=1)'
alias gds 'git diff --staged'
alias gdt 'git diff-tree --no-commit-id --name-only -r'
alias gdup 'git diff @{upstream}'
alias gdw 'git diff --word-diff'
alias gf 'git fetch'
alias gfo 'git fetch origin'
alias gfg 'git ls-files | grep'
alias gg 'git gui citool'
alias gga 'git gui citool --amend'
alias ggpur 'ggu'
alias ggpull 'git pull origin "$(git_current_branch)"'
alias ggpush 'git push origin "$(git_current_branch)"'
alias ggsup 'git branch --set-upstream-to=origin/$(git_current_branch)'
alias gpsup 'git push --set-upstream origin $(git_current_branch)'
alias ghh 'git help'
alias gignore 'git update-index --assume-unchanged'
alias gignored 'git ls-files -v | grep "^[[:lower:]]"'
alias git-svn-dcommit-push 'git svn dcommit && git push github $(git_main_branch):svntrunk'
function gk
    gitk --all --branches &
end
alias gke 'gitk --all $(git log --walk-reflogs --pretty=%h) &'
alias gl 'git pull'
alias glg 'git log --stat'
alias glgp 'git log --stat --patch'
alias glgg 'git log --graph'
alias glgga 'git log --graph --decorate --all'
alias glgm 'git log --graph --max-count=10'
alias glo 'git log --oneline --decorate'
alias glol "git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset'"
alias glols "git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset' --stat"
alias glod "git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset'"
alias glods "git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset' --date=short"
alias glola "git log --graph --pretty='%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset' --all"
alias glog 'git log --oneline --decorate --graph'
alias gloga 'git log --oneline --decorate --graph --all'
alias glp '_git_log_prettily'
alias gm 'git merge'
alias gmom 'git merge origin/$(git_main_branch)'
alias gmtl 'git mergetool --no-prompt'
alias gmtlvim 'git mergetool --no-prompt --tool=vimdiff'
alias gmum 'git merge upstream/$(git_main_branch)'
alias gma 'git merge --abort'
alias gms 'git merge --squash'
alias gp 'git push'
alias gpd 'git push --dry-run'
alias gpf! 'git push --force'
alias gpoat 'git push origin --all && git push origin --tags'
alias gpod 'git push origin --delete'
alias gpu 'git push upstream'
alias gpv 'git push --verbose'
alias gr 'git remote'
alias gra 'git remote add'
alias grb 'git rebase'
alias grba 'git rebase --abort'
alias grbc 'git rebase --continue'
alias grbd 'git rebase $(git_develop_branch)'
alias grbi 'git rebase --interactive'
alias grbm 'git rebase $(git_main_branch)'
alias grbom 'git rebase origin/$(git_main_branch)'
alias grbo 'git rebase --onto'
alias grbs 'git rebase --skip'
alias grev 'git revert'
alias grh 'git reset'
alias grhh 'git reset --hard'
alias groh 'git reset origin/$(git_current_branch) --hard'
alias grm 'git rm'
alias grmc 'git rm --cached'
alias grmv 'git remote rename'
alias grrm 'git remote remove'
alias grs 'git restore'
alias grset 'git remote set-url'
alias grss 'git restore --source'
alias grst 'git restore --staged'
alias grt 'cd "$(git rev-parse --show-toplevel || echo .)"'
alias gru 'git reset --'
alias grup 'git remote update'
alias grv 'git remote --verbose'
alias gsb 'git status --short --branch'
alias gsd 'git svn dcommit'
alias gsh 'git show'
alias gsi 'git submodule init'
alias gsps 'git show --pretty=short --show-signature'
alias gsr 'git svn rebase'
alias gss 'git status --short'
alias gst 'git status'
alias gstaa 'git stash apply'
alias gstc 'git stash clear'
alias gstd 'git stash drop'
alias gstl 'git stash list'
alias gstp 'git stash pop'
alias gsts 'git stash show --text'
alias gstu 'gsta --include-untracked'
alias gstall 'git stash --all'
alias gsu 'git submodule update'
alias gsw 'git switch'
alias gswc 'git switch --create'
alias gswm 'git switch $(git_main_branch)'
alias gswd 'git switch $(git_develop_branch)'
alias gts 'git tag --sign'
alias gtv 'git tag | sort -V'
alias gunignore 'git update-index --no-assume-unchanged'
alias gunwip 'git log --max-count=1 | grep -q -c "\--wip--" && git reset HEAD~1'
alias gup 'git pull --rebase'
alias gupv 'git pull --rebase --verbose'
alias gupa 'git pull --rebase --autostash'
alias gupav 'git pull --rebase --autostash --verbose'
alias gupom 'git pull --rebase origin $(git_main_branch)'
alias gupomi 'git pull --rebase=interactive origin $(git_main_branch)'
alias glum 'git pull upstream $(git_main_branch)'
alias gluc 'git pull upstream $(git_current_branch)'
alias gwch 'git whatchanged -p --abbrev-commit --pretty=medium'
alias gwip 'git add -A; git rm $(git ls-files --deleted) 2> /dev/null; git commit --no-verify --no-gpg-sign --message "--wip-- [skip ci]"'
alias gwt 'git worktree'
alias gwta 'git worktree add'
alias gwtls 'git worktree list'
alias gwtmv 'git worktree move'
alias gwtrm 'git worktree remove'
alias gam 'git am'
alias gamc 'git am --continue'
alias gams 'git am --skip'
alias gama 'git am --abort'
alias gamscp 'git am --show-current-patch'
