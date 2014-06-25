#!/bin/sh

DEV=""
MKFS_OPTIONS=""
MOUNT_OPTIONS=""
MNT=""

_fail()
{
	echo $1
	exit 1
}

check_run()
{
	test -z $DEV && _fail "Please set a valid device"
	test -z $MNT && _fail "Please set a valid Mountpoint"
	if [ `whoami` != "root" ];then
		_fail "Root required!"
	fi
}

scratch_mount()
{
	umount $DEV >& /dev/null
	mkfs.btrfs -f $DEV >& /dev/null || _fail "fail to mkfs"
	mount $DEV $MNT || _fail "fail to mount"
}

# test if -l option can list tree roots.
test_list_tree_roots()
{
	scratch_mount
	for i in $(seq 1 10);
	do
		btrfs sub snapshot $MNT $MNT/$i >& /dev/null
	done
	umount $DEV || _fail "umount failure"

	# Lazy check, we only verify if number matches.
	root_item_cnt=`btrfs restore -l $DEV | wc -l`
	test $root_item_cnt -ne 15 && _fail "-l option test failed"
	return 0
}

# simple test whether restore Regex path search works.
test_restore_regrex_file()
{
	scratch_mount

	touch $MNT/bar $MNT/wang $MNT/BaR
	umount $DEV
	cnt=`btrfs restore -Dv --path-regex "bar" $DEV -o /tmp  | grep -c bar`
	if [ $cnt -ne 1 ];then
		_fail "test --path-regrex failed"
	fi
	cnt=`btrfs restore -Dvc  --path-regex "bar" $DEV -o /tmp | grep -ci bar`
	if [ $cnt -ne 2 ];then
		_fail "test --path-regrex failed, expect bar, BaR"
	fi
	return 0
}

# test super block mirror
test_super_mirror_restore()
{
	umount $DEV >& /dev/null
	mkfs.btrfs -f $DEV -b 1g >& /dev/null || _fail "fail to mkfs"

	#only expect 2 mirrors work here.
	for i in $(seq 0 3);
	do
		btrfs restore -u $i $DEV -o /tmp >& /dev/null
		if [ $? -ne 0 ];then
			test $i -lt 1 && _fail "btrfs restore should succeed for mirror(<=1)"
		fi
	done
	return 0
}

# Unit test for -d option.
# Not sure why we need this option, with this option, 
# btrfs restore will search tree explictly.
test_find_dir_option()
{
	scratch_mount

	touch $MNT/aa
	umount $DEV
	test "$(btrfs restore $DEV -d -o /tmp | grep -c 256)" -ne 1 && _fail "-d test failure"
	return 0
}

#-t,-r/-f option test.
#-t option should be used for debug purpose for the most time,
# but -r/-f option is very useful to restore directories and files
# under specified Subvolume/snapshot.
test_find_root_option()
{

	scratch_mount
	umount $DEV
	# get tree root bytenr by btrfs-debug-tree firstly.
	btrfs restore -t "$(btrfs-debug-tree $DEV -r | sed -n '/root tree/p' | awk '{print $3}')" \
		-o /dev/sda9 /tmp || _fail "use root tree should succeed"

	# ok now test whether -r/-f option works.
	mount $DEV $MNT &&  btrfs sub snapshot $MNT $MNT/snap >&/dev/null && touch $MNT/bar
	bytenr=$(btrfs-debug-tree -r /dev/sda9 | sed -n '/file tree/p' | awk '{print $7}')
	objectid=$(btrfs-debug-tree /dev/sda9 -r | grep "file tree" | cut -f4 -d ' ' | cut -d '(' -f2)
	# only restore files from snapshot, and make sure we skip the file bar.
	rm -rf ./test
	mkdir ./test
	umount $DEV
	btrfs restore -r $objectid -o $DEV ./test || _fail "restore should succeed"
	test -z $(ls \./test) || _fail "restore should not recover anything"
	btrfs restore -r 5 -o $DEV ./test >&/dev/null || _fail "restore should succeed"
	test -z $(ls \./test) && _fail "restore should recover files"
	rm -rf ./test
	mkdir ./test
	btrfs restore -f $bytenr -o $DEV ./test || _fail "restore should succeed"
	test -z $(ls \./test) || _fail "restore should not recover anything"

	return 0
}

test_restore_directories_files()
{

	scratch_mount

	# create a strange fs firstly, btrfs restore only retore
	# directories and files, so ignore links now.
	cp /lib/modules/`uname -r` $MNT -rL
	umount $DEV

	rm -rf ./test && mkdir ./test
	btrfs restore -s $DEV -o ./test
	mount $DEV $MNT
	diff ./test $MNT -r || _fail "fails to restore, differency is detected!"
	return 0
}
check_run
test_list_tree_roots && echo "[PASS] List tree roots"
test_restore_regrex_file && echo "[PASS] Restore regrex file"
test_super_mirror_restore && echo "[PASS] Restore using backup super"
test_find_dir_option && echo "[PASS] Find dir option"
test_find_root_option && echo "[PASS] Use root option"
test_restore_directories_files && echo "[PASS] Restore directories and files"
