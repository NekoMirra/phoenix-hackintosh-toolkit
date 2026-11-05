#!/bin/sh
# $MFTMirr LCN=2, 记录3 → 2*4096 + 3*1024 = 11264
for d in rdisk0s2 rdisk3s1 rdisk2s1; do
  echo "===== /dev/$d 的 \$MFTMirr 记录3 ====="
  dd if=/dev/$d bs=512 skip=22 count=2 2>/dev/null | xxd | sed -n '1,2p;21,24p'
done
