#!/bin/sh
cd /Users/mirra/WorkBuddy/2026-11-03-20-03-17/tools
for d in /dev/rdisk0s2 /dev/rdisk0s6 /dev/rdisk2s1; do
  echo "############ $d ############"
  ./ntfsdirty show $d 2>&1
  echo
done
