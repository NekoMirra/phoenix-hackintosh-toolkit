#!/bin/sh
log show --last 20m --predicate 'process == "NTFSExtension"' 2>&1 | grep -iE "dirty=|hibernated=" | tail -10
