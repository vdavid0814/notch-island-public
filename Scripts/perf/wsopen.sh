#!/bin/bash
# wsopen.sh [n]: WindowServer's and NotchIsland's CPU over n open/close pairs of the home panel
A="$(cd "$(dirname "$0")/../.." && pwd)/build/NotchIsland.app"; n=${1:-10}
ws() { ps -o time= -p $(pgrep -x WindowServer) | awk -F: '{print $1*60+$2}'; }
ni() { ps -o time= -p $(pgrep -x NotchIsland) | awk -F: '{print $1*60+$2}'; }
w0=$(ws); sleep 5; w1=$(ws); base=$(echo "($w1-$w0)/5" | bc -l)
w0=$(ws); n0=$(ni); t0=$(date +%s.%N)
for i in $(seq 1 $n); do open -g -a "$A" "notchisland://open?page=home"; sleep 0.8; open -g -a "$A" "notchisland://close"; sleep 0.8; done
sleep 1; w1=$(ws); n1=$(ni); t1=$(date +%s.%N)
printf "per open+close: WindowServer extra %4.0f ms, NotchIsland %4.0f ms\n" "$(echo "(($w1-$w0) - $base*($t1-$t0))*1000/$n" | bc -l)" "$(echo "($n1-$n0)*1000/$n" | bc -l)"
