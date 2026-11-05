#!/bin/sh
diskutil mount /dev/disk0s6 >/dev/null 2>&1
diskutil mount /dev/disk2s1 >/dev/null 2>&1
diskutil unmount /Volumes/系统 >/dev/null 2>&1; sleep 1
diskutil mount /dev/disk0s2 >/dev/null 2>&1
sleep 2
log show --last 2m --info --debug --predicate 'process == "NTFSExtension"' 2>&1 | grep -iE "dirty=|hibernat|probe" | tail -12
