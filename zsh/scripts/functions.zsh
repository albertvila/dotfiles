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
