#!/bin/sh
# 抓取上次挂载尝试前后的完整 FSKit 日志（含设备打开阶段）
log show --start "2026-11-04 16:30:15" --end "2026-11-04 16:30:23" --predicate 'process == "NTFSExtension" OR process == "fskitd"' 2>&1 | grep -iE "open|device|resource|mount|error|denied|permit|fail|probe|activate|volume" | grep -viE "lifs_|retrying lookup|libxpc" | head -40
