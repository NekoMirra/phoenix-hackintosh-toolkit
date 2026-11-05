#!/bin/sh
cd /Users/mirra/WorkBuddy/2026-11-03-20-03-17/tools
for d in /dev/rdisk0s2 /dev/rdisk3s1 /dev/rdisk2s1 /dev/rdisk0s6; do
  echo "########## $d ##########"
  ./ntfslog show $d 2>&1
  echo
done
