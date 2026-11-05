log show --last 3m --predicate 'process == "NTFSExtension"' 2>&1 | grep -viE "libxpc|BoardServices|lifs_" | grep -iE "hibernat|unclean|dirty|activated NTFS|check:|option" | tail -20
