#!/bin/zsh
# scroll_bench.sh <app> [page] [label]: trackpad-like scrolling of a Settings page (default widgets),
# down and up, 1440 pt/s; prints the app's coalition CPU % and mW while it scrolls (coalition.py).
# WATCH=1: no measuring, scrolls for ~40 s so Activity Monitor (Energy tab) can be read meanwhile.
# Needs ws/smooth (swiftc -O ws/smooth.swift -o ws/smooth). Fresh launch, 30 s settle first.
cd "$(dirname "$0")"; export NI_APP="$1"; PAGE="${2:-widgets}"; LABEL="${3:-run}"
pkill -x NotchIsland; sleep 1; open -g -a "$NI_APP"; sleep 30
python3 drive.py settings/$PAGE 2
if [[ "$WATCH" == 1 ]]; then
  for k in 1 2 3 4 5 6 7 8 9 10; do ./ws/smooth 1100 600 12 240; ./ws/smooth 1100 600 -12 240; done
else
  ./ws/smooth 1100 600 12 120; ./ws/smooth 1100 600 -12 120; sleep 0.5
  (python3 coalition.py 12 12 > /tmp/scroll_bench-$LABEL.txt &); sleep 0.1
  for k in 1 2 3; do ./ws/smooth 1100 600 12 240; ./ws/smooth 1100 600 -12 240; done
  sleep 1
  echo "$LABEL $(tail -1 /tmp/scroll_bench-$LABEL.txt | awk '{print "cpu", $3, "mW", $13+$17+$19}')"
fi
python3 drive.py close
