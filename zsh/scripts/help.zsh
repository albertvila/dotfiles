function help-print {
  printf '%-70s   %2s\n' $1 $2
}

function help-dotfiles {
  echo "Showing general dotfiles help"
  echo "-----------------------------\n"

  help-print "z [WRITE+TAB]" "Use it to switch between folders, it autocompletes paths"
  help-print ".." "Instead of cd .."
  help-print "-" "Goes back to the previous folder"
  help-print "help-[TAB]" "Displays other available helps"
  help-print "fixSound" "Fixes an issue with OSX when the sound does not work"
}

function help-git {
  echo "Showing git help"
  echo "----------------\n"

  echo "Merge from a branch into master"
  echo "\tgit checkout master\n\tgit pull -r\n\tgit merge branch_name\n\tgit rebase -i\n\tgit pull -r\n\tgit push"
  echo "Move last 2 local commits into a branch"
  echo "\tgit branch new_branch_name \n\tgit reset --hard HEAD~2"
  echo "Creating a branch from another branch"
  echo "\tgcb new_branch_name origin/from_branch\n\tggp\n"
  help-print "git rebase -i" "Squash commits"
  help-print "git reset --soft HEAD~1" "Rollback last local commit to stagged phase"
  help-print "git branch -d XXX" "Deletes a branch locally"
  help-print "git push origin --delete XXX" "Deletes a branch remotely"

  echo "\nzsh git plugin"
  echo "--------------\n"

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
}

function help-vim {
  echo "Showing vim help"
  echo "----------------\n"

  help-print "CTRL+p" "Search & open files"
  help-print "(CTRL+n)*c" "Multiple cursors"
  help-print ",+c+SPACE" "Toggles comment line (also ,cc for comment and ,cu for uncomment)"
  help-print "CTRL+v + select lines with cursor + previous command" "Toggles comment multiple lines"
}

function help-gradle {
  echo "Showing gradle help"
  echo "----------------"
  echo "All commands works with ./gradlew if the file exists or gradle, the command autocompletion is enabled\n"

  help-print "gradle init" "Project generator based on some templates"
  help-print "gradle tasks" "Lists all available gradle tasks"
  help-print "gradle COMMAND" "Executes the given command"
  help-print "gradle dependencies" "Displays all project dependencies"
  help-print "gradle bootRun/run" "Runs the application if it contains the bootRun command for sprintboot apps/application"
  help-print "gradle clean test --tests \"com.lm.ApplicationConfigTest\"" "Run a single test"
  help-print "gradle build --continuous" "Automatically builds the project for every file change"
  help-print "gradle clean build -x test" "Excludes test phase"
  help-print "gradle build --refresh-dependencie" "Forces to refresh all project dependencies"
  help-print "gradle wrapper --gradle-version 5.2.1" "Updates the project gradle wraper to that version"
}

function help-terraform {
  echo "Showing terraform help"
  echo "----------------------\n"

  help-print "terraform init" "Initializes the terraform project"
  help-print "terraform workspace list" "Lists all available workspaces"
  help-print "terraform workspace new staging" "Creates a new workspace"
  help-print "terraform workspace select staging" "Activates the given workspace"
  help-print "terraform plan -var-file='environment/staging.tfvars'" "Plans the terraform changes for the given environment"
  help-print "terraform apply -var-file='environment/staging.tfvars'" "Applys the changes for the given environment"
}

function help-serverless {
  echo "Showing serverless help"
  echo "----------------------\n"

  help-print "sls package --package artifact" "Creates the serverless zip into the artifact folder, to check what will be deployed (only if node)"
  help-print "sls deploy --stage dev --verbose" "Deploys for dev environment"
  help-print "sls remove --stage dev --verbose" "Removes the dev stack"
}

function help-docker {
  echo "Showing docker help"
  echo "-------------------\n"

  echo "You must start Docker.app first"
  echo "If the command requires login, just run $(aws ecr get-login --no-include-email --region eu-west-1)"
  help-print "docker images -a" "In order to list all docker images"
  help-print "docker rmi IMAGE_NAME" "To delete an image, use --force to force it"
  help-print "docker build -t IMAGE_NAME -f ./config/docker/Dockerfile ." "To build a new docker image"
  echo "docker run -it IMAGE_NAME /bin/bash"
  echo "docker pull XXX"
}
