log show --last 3m --predicate 'process == "NTFSExtension"' 2>&1 | grep -viE "libxpc|BoardServices|lifs_" | grep -iE "activate|dirty|read-only|readonly|volume|error|fail|journal|refuse" | tail -25
