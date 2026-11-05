log show --last 5m --predicate 'process == "NTFSExtension"' 2>&1 | grep -viE "libxpc|BoardServices|lifs_" | grep -iE "unclean|dirty|activated NTFS|check:" | tail -20
