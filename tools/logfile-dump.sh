#!/bin/sh
# $MFT 偏移 3221225472；记录2($LogFile) = +2048
dd if=/dev/rdisk0s2 bs=512 skip=$(((3221225472+2048)/512)) count=2 2>/dev/null | xxd | head -20
