#!/bin/sh
diskutil unmount /Volumes/Ventoy >/dev/null 2>&1; sleep 1
diskutil mount /dev/disk3s1 >/dev/null 2>&1; sleep 2
log show --last 90s --info --debug --predicate 'process == "NTFSExtension"' 2>&1 | grep -E "probe disk3s1" | tail -3
mount | grep disk3s1
