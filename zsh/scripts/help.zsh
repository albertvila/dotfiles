function help-git {
  echo "Showing git help"
  echo "----------------"

  echo "\nSquash commits"
  echo "git rebase -i"
  echo "\nMerge from a branch into master"
  echo "git checkout master\ngit pull -r\ngit merge branch_name\ngit rebase -i\ngit pull -r\ngit push"
  echo "\nMove last 2 local commits into a branch"
  echo "git branch new_branch_name \ngit reset --hard HEAD~2"
  echo "\nRollback last local commit to stagged phase"
  echo "git reset --soft HEAD~1"
  echo "\nCreating a branch from another branch"
  echo "gcb new_branch_name origin/from_branch\nggp"

  echo "\nzsh git plugin"
  echo "--------------"
  echo "gb -> git branch"
  echo "gcb -> git checkout -b xxx"
  echo "gco xxx -> git chekout xxx"
  echo "gcm -> git checkout master"
  echo "ggu -> git pull --rebase"
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

function help-vim {
  echo "Showing vim help"
  echo "----------------"

  echo "ctrl+p -> Search & open files"
  echo "(ctrl+n)*c -> Multiple cursors"
  echo ",+c+space Toggle comment line (also ,cc for comment and ,cu for uncomment)"
  echo "ctrl+v + select lines with cursor + previous command to toggle comment multiple lines"
}

function help-tmux {
  echo "Showing tmux/tmuxinator help"
  echo "----------------"

  echo "tmx -> Attaches last tmux session or creates a new one (because of the alias)"
  echo "mux list -> List tmuxinator projects"
  echo "mux X -> Starts tmuxinator project X"
  echo "mux stop X -> Stops tmuxinator project X"
  echo "ctrl+b n -> Next window"
  echo "ctrl+b p -> Previous window"
  echo "ctrl+b arrows -> Select panel"
}

function help-gradle {
  echo "Showing gradle help"
  echo "----------------"
  echo " All commands works with ./gradlew if the file exists or gradle"
  echo "gradle bootRun -> Runs the application"
  echo "gradle clean test --tests \"*ApplicationConfigTest\" -> Run a single test"
  echo "gradle build --continuous"
  echo "gradle clean build -x test -> Excludes test phase"
}

function help-terraform {
  echo "Showing terraform help"
  echo "----------------------"
  echo "terraform init"
  echo "terraform workspace list"
  echo "terraform workspace new staging"
  echo "terraform workspace select staging"
  echo "terraform plan -var-file='environment/staging.tfvars'"
  echo "terraform apply -var-file='environment/staging.tfvars'"
}
