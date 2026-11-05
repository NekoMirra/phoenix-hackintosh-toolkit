#!/bin/sh
for d in rdisk0s2 rdisk0s6 rdisk2s1 rdisk3s1; do
  echo "===== /dev/$d ====="
  dd if=/dev/$d bs=512 count=1 2>/dev/null | xxd -s 0 -l 96 | head -6
  echo "--- 总扇区(0x28) / MFT LCN(0x30) / 序列号(0x48) ---"
  dd if=/dev/$d bs=512 count=1 2>/dev/null | xxd -s 0x28 -l 0x28
  echo
done
