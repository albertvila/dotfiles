# Configure iTerm2 tab titles based on current directory, example /Users/Albert/workspace/dotfiles -> ~/p/dotfiles
function precmd () {
  window_title="\e]0;${${PWD/#"$HOME"/~}/workspace/w}\a"
  echo -ne "$window_title"
}

# Next function copied from https://github.com/apjanke/oh-my-zsh/blob/master/lib/git.zsh to avoid
#  error "command not found: git_current_branch"

# Outputs the name of the current branch
# Usage example: git pull origin $(git_current_branch)
# Using '--quiet' with 'symbolic-ref' will not cause a fatal error (128) if
# it's not a symbolic ref, but in a Git repo.
function git_current_branch() {
  local ref
  ref=$(command git symbolic-ref --quiet HEAD 2> /dev/null)
  local ret=$?
  if [[ $ret != 0 ]]; then
    [[ $ret == 128 ]] && return  # no git repo.
    ref=$(command git rev-parse --short HEAD 2> /dev/null) || return
  fi
  echo ${ref#refs/heads/}
}

function prompt_terraform() {

  if [[ -n *.tf(#qN) ]]; then
    WORKSPACE=$("terraform" workspace show 2> /dev/null) || return
    "$1_prompt_segment" "$0" "$2" "$DEFAULT_COLOR" "red" "tf:$WORKSPACE"
  fi
}

function infinite {
  while true
  do
    eval $1
    sleep 2
  done
}

function looooooooong {
    START=$(date +%s.%N)
    $*
    EXIT_CODE=$?
    END=$(date +%s.%N)
    DIFF=$(echo "$END - $START" | bc)
    RES=$(python -c "diff = $DIFF; min = int(diff / 60); print('%s min' % min)")
    result="$1 completed in $RES, exit code $EXIT_CODE."
    echo -e "\n⏰  $result"
    ( say -r 250 $result 2>&1 > /dev/null & )
}

# an osx substitution for linux 'free' command
function free {

  # Use vm_stat and sysctl to get system info
  vmstat=($(vm_stat | egrep -o "[0-9]+"))

  pfree=$vmstat[2] # Pages free
  pwired=$vmstat[7] # Pages wired down
  pinact=$vmstat[4] # Pages inactive
  panon=$vmstat[15] # Anonymous pages
  pcomp=$vmstat[17] # Pages occupied by compressor
  ppurge=$vmstat[8] # Pages purgeable
  pfback=$vmstat[14] # File-backed pages

  total_mem=$(sysctl -n hw.memsize)

  # Arithmetics
  total_mem=$(($total_mem/1073741824))
  pfree=$(($pfree*4096/1073741824))
  pwired=$(($pwired * 4096 / 1073741824))
  pinact=$(($pinact * 4096 / 1073741824))
  panon=$(($panon * 4096 / 1073741824))
  pcomp=$(($pcomp * 4096 / 1073741824))
  ppurge=$(($ppurge * 4096 / 1073741824))
  pfback=$(($pfback * 4096 / 1073741824))

  # OSX Activity monitor formulas
  free=$(($pfree + $pinact))
  cached=$(($pfback + $ppurge))
  appmem=$(($panon - $ppurge))
  used=$(($appmem + $pwired + $pcomp))

  # Display the hud
  printf '                 total     used     free   appmem    wired   compressed\n'
  printf 'Mem:          %6.2fGb %6.2fGb %6.2fGb %6.2fGb %6.2fGb %6.2fGb\n' $total_mem $used $free $panon $pwired $pcomp
  printf '+/- Cache:             %6.2fGb %6.2fGb\n' $cached $pinact
  sysctl -n -o vm.swapusage | awk '{   if( $3+0 != 0 )  printf( "Swap(%2.0f%s):    %6.0fMb %6.0fMb %6.0fMb\n", ($6+0)*100/($3+0), "%", ($3+0), ($6+0), $9+0); }'
  sysctl -n -o vm.loadavg | awk '{printf( "Load Avg:        %3.2f %3.2f %3.2f\n", $2, $3, $4);}'
}
