# General aliases + ported shell functions (groups A, B, C, E, H).
# Loads AFTER 20-git.fish, so the gds/glog overrides below win — same as
# .zshrc sourcing aliases.zsh after aliases.git.plugin.zsh.

# --- general aliases (from home/.scripts/aliases.zsh) ---
alias reset "clear && printf '\e[3J'"
alias vi vim
alias glog "git log --graph --format='format:%C(yellow)%h%C(reset) %C(blue)\"%an\" <%ae>%C(reset) %C(magenta)%ar%C(reset)%n%s' --date-order -n 5"
alias glogn "git log --graph --format='format:%C(yellow)%h%C(reset) %C(blue)\"%an\" <%ae>%C(reset) %C(magenta)%ar%C(reset)%n%s' --date-order -n"
alias gds "gd --staged"
alias cat "bat --paging=never"
functions -q lm; and functions -e lm
alias fixSound "sudo killall coreaudiod"
alias gstk "git stash --keep-index"

abbr -a -- .. "cd .."
abbr -a -- ... "cd ../.."
abbr -a -- .... "cd ../../.."
abbr -a -- - "cd -"

# --- tab title (was precmd in .zshrc; ~/w/dotfiles style) ---
function fish_title
    set -l d $PWD
    string match -q "$HOME*" $d; and set d (string replace "$HOME" '~' $d)
    string replace workspace w $d
end

# Tab over frecent dirs (recency first), not filesystem paths: `z dotf<TAB>`
complete -c z -f -a '(fasd -dltR 2>/dev/null)'

# --- fasd tracking (was prezto's zsh-hook; without this, dirs visited in
# fish never enter the DB and `z` only ever shows zsh-era history) ---
function __fasd_track --on-variable PWD
    status is-interactive; or return
    fasd --proc (fasd --sanitize $PWD) >/dev/null 2>&1
end

# --- fasd jump (fasd ships no fish init; was prezto fasd module + `z` alias) ---
function z --description "fasd cd with visible candidates"
    set -l matches
    if test (count $argv) -eq 0
        set matches (fasd -dltR 2>/dev/null | head -n 15)
    else
        set matches (fasd -dl $argv 2>/dev/null | head -n 10)
    end
    switch (count $matches)
        case 0
            echo "z: no match for '$argv'"
            return 1
        case 1
            if test (count $argv) -eq 0
                echo $matches[1]
            else
                cd $matches[1]
            end
        case '*'
            for i in (seq (count $matches))
                echo "$i  $matches[$i]"
            end
            if test (count $argv) -eq 0
                return
            end
            read -P "cd to [1]: " choice
            test -z "$choice"; and set choice 1
            if string match -qr '^[0-9]+$' $choice; and test $choice -ge 1; and test $choice -le (count $matches)
                cd $matches[$choice]
            else
                echo "z: invalid choice"
                return 1
            end
    end
end

# --- lazy version managers (mirrors the unfunction wrappers in .zshrc) ---
function jenv --description "lazy jenv init"
    functions -e jenv java
    jenv init - | source
    jenv $argv
end
function java --description "lazy jenv init"
    functions -e jenv java
    jenv init - | source
    java $argv
end
function nodenv --description "lazy nodenv init"
    functions -e nodenv node npm npx
    nodenv init - --no-rehash fish | source
    nodenv $argv
end
function node --description "lazy nodenv init"
    functions -e nodenv node npm npx
    nodenv init - --no-rehash fish | source
    node $argv
end
function npm --description "lazy nodenv init"
    functions -e nodenv node npm npx
    nodenv init - --no-rehash fish | source
    npm $argv
end
function npx --description "lazy nodenv init"
    functions -e nodenv node npm npx
    nodenv init - --no-rehash fish | source
    npx $argv
end

# --- auto-notice of local java version (was chpwd hook in .zshrc) ---
function __check_local_java --on-variable PWD
    if test -f .java-version; and test -r .java-version
        printf "Now using local version of java: %s\n" (cat .java-version)
    end
end

# --- custom functions (from home/.scripts/aliases.zsh + functions.zsh) ---
function gbranch --description "create dated branch off main/master/develop and push"
    git fetch
    set -l currentBranch (git branch | grep '\*' | cut -d ' ' -f2)
    set -l baseBranch
    if test "$currentBranch" = main; or test "$currentBranch" = master
        set baseBranch m
    else if test "$currentBranch" = develop
        set baseBranch d
    else
        echo "Wrong branch, you should be in main or develop branch"
        return 1
    end
    set -l name albert
    if test (count $argv) -ge 1
        set name (string replace -a ' ' '_' "albert_$argv[1]")
    end
    set -l today (gdate +"%Y%m%d")
    set -l shortCommitHash (git rev-parse --short HEAD)
    set -l randomNumber (printf '%05d' (random 0 32767))
    set -l newBranch (string lower "$baseBranch"-"$name"_"$today"_"$shortCommitHash"_"$randomNumber")
    echo "Creating a new branch $newBranch and switching into it"
    git checkout -b $newBranch origin/$currentBranch
    git push -u origin $newBranch
end

function ssh --description "ssh with env-tinted terminal background"
    set -l host (string join ' ' $argv)
    switch $host
        case '*prod*' '*production*'
            printf '\e]11;#401515\a'
        case '*stag*' '*staging*'
            printf '\e]11;#0A2D2D\a'
    end
    command ssh $argv
    printf '\e]111\a'
end

function infinite --description "rerun a command every 2s"
    while true
        eval $argv
        sleep 2
    end
end

function pr_stats --description "PR stats by author for current repo"
    echo 'Listing the stats from the last 500 PR for the current repository'
    gh pr list -L 500 --state closed --json number,createdAt,closedAt,author | jq 'group_by(.author) | map({ author: .[0].author, total_prs: length, avg_duration: (map(select(.closedAt)) | map((.closedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) | add / length / 3600)})'
end

function pr_stats_full --description "detailed PR stats by author for current repo"
    echo 'Listing the stats from the last 500 PR for the current repository with more detailed information'
    gh pr list -L 500 -s closed --json number,createdAt,closedAt,author,title | jq 'group_by(.author) | map({ author: .[0].author, total_prs: length, avg_duration_in_hours: (map(select(.closedAt)) | map((.closedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) | add / length / 3600), prs: (map({ number, title, createdAt, closedAt, duration_in_hours: (((.closedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) / 3600)}) | sort_by(-.duration_in_hours)) })'
end

function looooooooong --description "time a command, report minutes + say it"
    set -l START (gdate +%s.%N)
    $argv
    set -l EXIT_CODE $status
    set -l END (gdate +%s.%N)
    set -l DIFF (echo "$END - $START" | bc)
    set -l RES (python3 -c "diff = $DIFF; min = int(diff / 60); print('%s min' % min)")
    set -l result "$argv[1] completed in $RES, exit code $EXIT_CODE."
    printf '\n⏰  %s\n' $result
    say -r 250 $result >/dev/null 2>&1 &
end

function free --description "macOS substitute for linux free"
    set -l vmstat (vm_stat | grep -Eo "[0-9]+")
    set -l pfree $vmstat[2]
    set -l pwired $vmstat[7]
    set -l pinact $vmstat[4]
    set -l panon $vmstat[15]
    set -l pcomp $vmstat[17]
    set -l ppurge $vmstat[8]
    set -l pfback $vmstat[14]
    set -l total_mem (math (sysctl -n hw.memsize) / 1073741824)
    set -l pfree (math "$pfree * 4096 / 1073741824")
    set -l pwired (math "$pwired * 4096 / 1073741824")
    set -l pinact (math "$pinact * 4096 / 1073741824")
    set -l panon (math "$panon * 4096 / 1073741824")
    set -l pcomp (math "$pcomp * 4096 / 1073741824")
    set -l ppurge (math "$ppurge * 4096 / 1073741824")
    set -l pfback (math "$pfback * 4096 / 1073741824")
    set -l free (math "$pfree + $pinact")
    set -l cached (math "$pfback + $ppurge")
    set -l appmem (math "$panon - $ppurge")
    set -l used (math "$appmem + $pwired + $pcomp")
    printf '                 total     used     free   appmem    wired   compressed\n'
    printf 'Mem:          %6.2fGb %6.2fGb %6.2fGb %6.2fGb %6.2fGb %6.2fGb\n' $total_mem $used $free $panon $pwired $pcomp
    printf '+/- Cache:             %6.2fGb %6.2fGb\n' $cached $pinact
    sysctl -n -o vm.swapusage | awk '{   if( $3+0 != 0 )  printf( "Swap(%2.0f%s):    %6.0fMb %6.0fMb %6.0fMb\n", ($6+0)*100/($3+0), "%", ($3+0), ($6+0), $9+0); }'
    sysctl -n -o vm.loadavg | awk '{printf( "Load Avg:        %3.2f %3.2f %3.2f\n", $2, $3, $4);}'
end

# --- help cheat-sheets (from home/.scripts/help.zsh; print-only) ---
function help-print
    printf '%-70s   %2s\n' $argv[1] $argv[2]
end

function help-dotfiles
    echo "Showing general dotfiles help"
    echo "-----------------------------"
    echo
    help-print "z [WRITE+TAB]" "Use it to switch between folders, it autocompletes paths"
    help-print ".." "Instead of cd .."
    help-print "-" "Goes back to the previous folder"
    help-print "help-[TAB]" "Displays other available helps"
    help-print "fixSound" "Fixes an issue with OSX when the sound does not work"
end

function help-git
    echo "Showing git help"
    echo "----------------"
    echo
    echo "Merge from a branch into master"
    printf '\tgit checkout master\n\tgit pull -r\n\tgit merge branch_name\n\tgit rebase -i\n\tgit pull -r\n\tgit push\n'
    echo "Move last 2 local commits into a branch"
    printf '\tgit branch new_branch_name \n\tgit reset --hard HEAD~2\n'
    echo "Creating a branch from another branch"
    printf '\tgcb new_branch_name origin/from_branch\n\tggp\n'
    echo "Changing last commit message already pushed to a branch"
    printf '\tgit commit --amend -m "..."\n\tgit push --force-with-lease\n'
    help-print "git rebase -i" "Squash commits"
    help-print "git reset --soft HEAD~1" "Rollback last local commit to stagged phase"
    help-print "git branch -d XXX" "Deletes a branch locally"
    help-print "git push origin --delete XXX" "Deletes a branch remotely"
    echo
    echo "fish git aliases"
    echo "----------------"
    echo
    help-print "gb" "git branch"
    help-print "gcb" "git checkout -b xxx"
    help-print "gco xxx" "git chekout xxx"
    help-print "gcm" "git checkout master"
    help-print "ggu" "git pull --rebase"
    help-print "gm" "git merge"
    help-print "grbi" "git rebase -i"
    help-print "grbc" "git rebase --continue"
    help-print "grbs" "git rebase --skip"
    help-print "gst" "git status"
    help-print "glol" "git log --graph --pretty"
    help-print "gd" "git diff"
    help-print "ga" "git add"
    help-print "gcmsg 'xxx'" "git commit -m 'xxx'"
    help-print "ggp" "git push"
    help-print "gsta" "git stash save"
    help-print "gstp" "git stash pop"
    help-print "gstl" "git stash list"
    help-print "gstd stash@{0}" "git stash drop stash@{0}"
    help-print "gstk" "git stash --keep-index"
    help-print "grh" "git reset HEAD"
end

function help-vim
    echo "Showing vim help"
    echo "----------------"
    echo
    help-print "CTRL+p" "Search & open files"
    help-print "(CTRL+n)*c" "Multiple cursors"
    help-print ",+c+SPACE" "Toggles comment line (also ,cc for comment and ,cu for uncomment)"
    help-print "CTRL+v + select lines with cursor + previous command" "Toggles comment multiple lines"
end

function help-gradle
    echo "Showing gradle help"
    echo "-------------------"
    echo "All commands works with ./gradlew if the file exists or gradle, the command autocompletion is enabled"
    echo
    help-print "gradle init" "Project generator based on some templates"
    help-print "gradle tasks" "Lists all available tasks"
    help-print "gradle COMMAND" "Executes the given command"
    help-print "gradle dependencies" "Displays all project dependencies"
    help-print "gradle bootRun/run" "Runs the application if it contains the bootRun command for sprintboot apps/application"
    help-print "gradle clean test --tests \"com.lm.ApplicationConfigTest\"" "Run a single test"
    help-print "gradle build --continuous" "Automatically builds the project for every file change"
    help-print "gradle clean build -x test" "Excludes test phase"
    help-print "gradle build --refresh-dependencie" "Forces to refresh all project dependencies"
    help-print "gradle wrapper --gradle-version 5.2.1" "Updates the project gradle wraper to that version"
    help-print "If you have issues like \"Failed to run Gradle Worker Daemon\"" "Stop gradle daemon with gradle --stop and then remove the ~/.gradle/caches folder"
end

function help-terraform
    echo "Showing terraform help"
    echo "----------------------"
    echo
    help-print "terraform init" "Initializes the terraform project"
    help-print "terraform workspace list" "Lists all available workspaces"
    help-print "terraform workspace new staging" "Creates a new workspace"
    help-print "terraform workspace select staging" "Activates the given workspace"
    help-print "terraform plan -var-file='environment/staging.tfvars'" "Plans the terraform changes for the given environment"
    help-print "terraform apply -var-file='environment/staging.tfvars'" "Applys the changes for the given environment"
end

function help-serverless
    echo "Showing serverless help"
    echo "------------------------"
    echo
    help-print "sls package --package artifact" "Creates the serverless zip into the artifact folder, to check what will be deployed (only if node)"
    help-print "sls deploy --stage dev --verbose" "Deploys for dev environment"
    help-print "sls remove --stage dev --verbose" "Removes the dev stack"
end

function help-docker
    echo "Showing docker help"
    echo "-------------------"
    echo
    echo 'You must start OrbStack first (OrbStack replaced Colima as the Docker runtime)'
    echo 'If the command requires ECR login, run: aws ecr get-login-password --region eu-west-1 | docker login --username AWS --password-stdin <account>.dkr.ecr.eu-west-1.amazonaws.com'
    help-print "docker images -a" "In order to list all docker images"
    help-print "docker rmi IMAGE_NAME" "To delete an image, use --force to force it"
    help-print "docker build -t IMAGE_NAME -f ./config/docker/Dockerfile ." "To build a new docker image"
    echo "docker run -it IMAGE_NAME /bin/bash"
    echo "docker pull XXX"
end
