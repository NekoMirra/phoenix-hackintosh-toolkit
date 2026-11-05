#!/bin/sh
log show --start "2026-11-04 16:58:15" --end "2026-11-04 16:58:40" --predicate 'process == "NTFSExtension" OR process == "fskitd"' 2>&1 | grep -viE "libxpc|BoardServices|lifs_|retrying lookup" | grep -iE "option|hiber|dirty|refus|read-write|read-only|EPERM|probe" | tail -25
