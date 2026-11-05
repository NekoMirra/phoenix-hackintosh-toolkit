echo "== 苹果 ntfs.fs 探测顺序 =="
plutil -p /System/Library/Filesystems/ntfs.fs/Contents/Info.plist 2>/dev/null | sed -n '/FSMediaTypes/,/};/p' | grep -E "Windows_NTFS|EBD0|FSProbeOrder|Partitionless"
echo
echo "== ntfs4mac 探测顺序 =="
plutil -p /Applications/NTFS4Mac.app/Contents/Extensions/NTFSExtension.appex/Contents/Info.plist 2>/dev/null | sed -n '/FSMediaTypes/,/};/p' | grep -E "Windows_NTFS|EBD0|FSProbeOrder|Partitionless"
echo
echo "== 控制测试：FAT32 分区能否用 mount -F -t msdos =="
diskutil unmount force /Volumes/VTOYEFI >/dev/null 2>&1
mkdir -p /Volumes/fattest
/sbin/mount -F -t msdos /dev/disk3s2 /Volumes/fattest 2>&1
echo "exit=$?"
mount | grep disk3s2
diskutil unmount force /Volumes/fattest >/dev/null 2>&1
