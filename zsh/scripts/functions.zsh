function infinite {
  while true
  do
    eval "$1"
    sleep 2
  done
}

function pr_stats {
  echo 'Listing the stats from the last 500 PR for the current repository'
  gh pr list -L 500 --state closed --json number,createdAt,closedAt,author | jq 'group_by(.author) | map({ author: .[0].author, total_prs: length, avg_duration: (map(select(.closedAt)) | map((.closedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) | add / length / 3600)})'
}

function pr_stats_full {
  echo 'Listing the stats from the last 500 PR for the current repository with more detailed information'

  gh pr list -L 500 -s closed --json number,createdAt,closedAt,author,title |
  jq 'group_by(.author) |
    map({
      author: .[0].author,
      total_prs: length,
      avg_duration_in_hours: (
        map(select(.closedAt))
        | map((.closedAt | fromdateiso8601) - (.createdAt | fromdateiso8601))
        | add / length / 3600
      ),
      prs: (
        map({ number, title, createdAt, closedAt, duration_in_hours: (((.closedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) / 3600)})
        | sort_by(-.duration_in_hours)
      )
    })'
}

function looooooooong {
    START=$(gdate +%s.%N)
    $*
    EXIT_CODE=$?
    END=$(gdate +%s.%N)
    DIFF=$(echo "$END - $START" | bc)
    RES=$(python3 -c "diff = $DIFF; min = int(diff / 60); print('%s min' % min)")
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

function dotfiles-health-check {
  local dotfiles_dir="${DOTFILES_DIR:-$HOME/workspace/dotfiles}"
  local ok=0 warn=0

  _hc_ok()   { echo "  ✅  $1"; (( ok++ )) }
  _hc_warn() { echo "  ⚠️   $1"; (( warn++ )) }

  echo "\n🔍  Dotfiles health check\n"

  # --- Symlinks ---
  echo "── Symlinks ──"
  local symlinks=(
    "$HOME/.gitconfig:$dotfiles_dir/git/gitconfig"
    "$HOME/.gitignore:$dotfiles_dir/git/gitignore"
    "$HOME/.gitmessage:$dotfiles_dir/git/gitmessage"
    "$HOME/.zshrc:$dotfiles_dir/zsh/zshrc"
    "$HOME/.zpreztorc:$dotfiles_dir/zsh/zpreztorc"
    "$HOME/.scripts:$dotfiles_dir/zsh/scripts"
    "$HOME/.vim:$dotfiles_dir/vim"
    "$HOME/.vimrc:$dotfiles_dir/vim/vimrc"
    "$HOME/.config/starship.toml:$dotfiles_dir/zsh/starship.toml"
  )
  for entry in "${symlinks[@]}"; do
    local link="${entry%%:*}" target="${entry##*:}"
    if [[ "$(readlink "$link")" == "$target" ]]; then
      _hc_ok "$link → $target"
    else
      _hc_warn "$link is not linked to $target"
    fi
  done

  # --- Key tools ---
  echo "\n── Tools ──"
  local tools=(git gh vim starship fasd direnv jq brew node npm python3 pyenv jenv nodenv)
  for tool in "${tools[@]}"; do
    if command -v "$tool" &>/dev/null; then
      _hc_ok "$tool $(${tool} --version 2>/dev/null | head -1)"
    else
      _hc_warn "$tool not found"
    fi
  done

  echo "\n── Result ──"
  echo "  ✅  $ok passed   ⚠️   $warn warnings\n"
}
