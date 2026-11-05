#!/bin/sh
log show --last 3m --info --predicate 'process == "NTFSExtension"' 2>&1 | grep -viE "libxpc|BoardServices|lifs_" | grep -iE "disk0s2|read-write|read-only|refus|fallback|falling|EPERM|EIO|error|verif|mirror|MFT" | tail -18
