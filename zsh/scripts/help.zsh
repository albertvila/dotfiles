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
  echo "\nDeleting a branch"
  echo "local -> git branch -d XXX"
  echo "remote -> git push origin --delete XXX"

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
  echo "gstd stash@{0} -> git stash drop stash@{0}"
  echo "gstk -> git stash --keep-index"
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

function help-serverless {
  echo "Showing serverless help"
  echo "----------------------"
  echo "sls package --package artifact -> Creates the serverless zip into the artifact folder, to check what will be deployed (only if node)"
  echo "sls deploy --stage dev --verbose -> Deploys for dev environment"
  echo "sls remove --stage dev --verbose -> Removes the dev stack"
}

function help-docker {
  echo "Showing docker help"
  echo "-------------------"
  echo "You must start Docker.app first"
  echo "If the command requires login, just run $(aws ecr get-login --no-include-email --region eu-west-1)"
  echo "docker images -a -> In order to list all docker images"
  echo "docker rmi IMAGE_NAME -> To delete an image, use --force to force it"
  echo "docker build -t IMAGE_NAME -f ./config/docker/Dockerfile . -> To build a new docker image"
  echo "docker run -it IMAGE_NAME /bin/bash"
  echo "docker pull XXX"
}
