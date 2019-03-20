function print {
  printf '%-70s   %2s\n' $1 $2
}

function help-dotfiles {
  echo "Showing general dotfiles help"
  echo "-----------------------------\n"

  print "z [WRITE+TAB]" "Use it to switch between folders, it autocompletes paths"
  print ".." "Instead of cd .."
  print "-" "Goes back to the previous folder"
  print "help-[TAB]" "Displays other available helps"
  print "fixSound" "Fixes an issue with OSX when the sound does not work"
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
  print "git rebase -i" "Squash commits"
  print "git reset --soft HEAD~1" "Rollback last local commit to stagged phase"
  print "git branch -d XXX" "Deletes a branch locally"
  print "git push origin --delete XXX" "Deletes a branch remotely"

  echo "\nzsh git plugin"
  echo "--------------\n"

  print "gb" "git branch"
  print "gcb" "git checkout -b xxx"
  print "gco xxx" "git chekout xxx"
  print "gcm" "git checkout master"
  print "ggu" "git pull --rebase"
  print "gm" "git merge"
  print "grbi" "git rebase -i"
  print "grbc" "git rebase --continue"
  print "grbs" "git rebase --skip"
  print "gst" "git status"
  print "glol" "git log --graph --pretty"
  print "gd" "git diff"
  print "ga" "git add"
  print "gcmsg 'xxx'" "git commit -m 'xxx'"
  print "ggp" "git push"
  print "gsta" "git stash save"
  print "gstp" "git stash pop"
  print "gstl" "git stash list"
  print "gstd stash@{0}" "git stash drop stash@{0}"
  print "gstk" "git stash --keep-index"
  print "grh" "git reset HEAD"
}

function help-vim {
  echo "Showing vim help"
  echo "----------------\n"

  print "CTRL+p" "Search & open files"
  print "(CTRL+n)*c" "Multiple cursors"
  print ",+c+SPACE" "Toggles comment line (also ,cc for comment and ,cu for uncomment)"
  print "CTRL+v + select lines with cursor + previous command" "Toggles comment multiple lines"
}

function help-gradle {
  echo "Showing gradle help"
  echo "----------------"
  echo "All commands works with ./gradlew if the file exists or gradle, the command autocompletion is enabled\n"

  print "gradle init" "Project generator based on some templates"
  print "gradle tasks" "Lists all available gradle tasks"
  print "gradle COMMAND" "Executes the given command"
  print "gradle dependencies" "Displays all project dependencies"
  print "gradle bootRun/run" "Runs the application if it contains the bootRun command for sprintboot apps/application"
  print "gradle clean test --tests \"com.lm.ApplicationConfigTest\"" "Run a single test"
  print "gradle build --continuous" "Automatically builds the project for every file change"
  print "gradle clean build -x test" "Excludes test phase"
  print "gradle build --refresh-dependencie" "Forces to refresh all project dependencies"
  print "gradle wrapper --gradle-version 5.2.1" "Updates the project gradle wraper to that version"
}

function help-terraform {
  echo "Showing terraform help"
  echo "----------------------\n"

  print "terraform init" "Initializes the terraform project"
  print "terraform workspace list" "Lists all available workspaces"
  print "terraform workspace new staging" "Creates a new workspace"
  print "terraform workspace select staging" "Activates the given workspace"
  print "terraform plan -var-file='environment/staging.tfvars'" "Plans the terraform changes for the given environment"
  print "terraform apply -var-file='environment/staging.tfvars'" "Applys the changes for the given environment"
}

function help-serverless {
  echo "Showing serverless help"
  echo "----------------------\n"

  print "sls package --package artifact" "Creates the serverless zip into the artifact folder, to check what will be deployed (only if node)"
  print "sls deploy --stage dev --verbose" "Deploys for dev environment"
  print "sls remove --stage dev --verbose" "Removes the dev stack"
}

function help-docker {
  echo "Showing docker help"
  echo "-------------------\n"

  echo "You must start Docker.app first"
  echo "If the command requires login, just run $(aws ecr get-login --no-include-email --region eu-west-1)"
  print "docker images -a" "In order to list all docker images"
  print "docker rmi IMAGE_NAME" "To delete an image, use --force to force it"
  print "docker build -t IMAGE_NAME -f ./config/docker/Dockerfile ." "To build a new docker image"
  echo "docker run -it IMAGE_NAME /bin/bash"
  echo "docker pull XXX"
}
