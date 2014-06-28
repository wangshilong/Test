#!/bin/sh

DEV="/dev/sdb"
MKFS_OPTIONS=""
MOUNT_OPTIONS=""
MNT="/mnt"
run_time=$((60 * 10))

declare -a process_pids

_fail()
{
	echo $1
	exit 1
}

killall_background()
{
	for i in ${process_pids[@]};
	do
		kill -9 $i
	done
	# still not safe to allow us umount.
	sleep 10
	umount $DEV
	btrfs check $DEV  || _fail "Filesystem is inconsistency"
}

trap "killall_background ; exit 0" 0 1 2 3 15

check_run()
{
	test -z $DEV && _fail "Please set a valid device"
	test -z $MNT && _fail "Please set a valid Mountpoint"
	if [ `whoami` != "root" ];then
		_fail "Root required!"
	fi
}

change_val()
{
	local var_name=$1
	local var=$2
	eval $var_name=$var
}

# since balance operations will be slowed down if
# there are too many snapshots, so donnot create snapshot
# so fast.
run_snapshots()
{
	i=1
	need_stop=0
	trap 'change_val need_stop 1' INT TERM HUP
	while [ 1 ]
	do
		btrfs sub snapshot $MNT $MNT/snap_$i
		# destroy some snapshots randomly.
		if [ $[$i/10] -eq 0 ];then
			btrfs sub  delete $MNT/snap_$i
		fi
		test $need_stop -eq 1 && break
		((i++))
		sleep 5
	done
}

# select one kind of profile and then run balance randomly.
# Now duplicate mode only applies to one device, it is not
# considered in here.
run_balance()
{
	need_stop=0
	trap 'change_val need_stop 1' INT TERM HUP

	meta_profile=(single raid1 raid0 raid10 raid5 raid6)
	data_profile=(single raid1 raid0 raid10 raid5 raid6)
	sys_profile=(single raid1 raid0 raid10 raid5 raid6)

	meta_len=${#meta_profile[@]}
	data_len=${#data_profile[@]}
	sys_len=${#data_profile[@]}

	while [ 1 ] 
	do
		meta_index=$(($RANDOM%$meta_len))
		data_index=$(($RANDOM%$data_len))
		sys_index=$(($RANDOM%$sys_len))

		btrfs balance start -dconvert=${data_profile[$data_index]}\
			-mconvert=${meta_profile[$meta_index]} \
			-sconvert=${sys_profile[$sys_index]} \
			/mnt -f >&/dev/null || exit 1
		sleep 2
		test $need_stop -eq 1 && break
	done
}

run_scrub()
{
	need_stop=0
	trap 'change_val need_stop 1' INT TERM HUP
	while [ 1 ] 
	do
		btrfs scrub start $MNT >& /dev/null
		sleep 10
		test $need_stop -eq 1 && break
	done
}

run_fsstress()
{
	need_stop=0
	trap 'change_val need_stop 1' INT TERM HUP
	while [ 1 ]
	do
		./fsstress -d $MNT -w -p 10 -n 100
		test $need_stop -eq 1 && break
	done
}

test_setup()
{
	mkfs.btrfs -f $DEV /dev/sdc /dev/sdd /dev/sde >& /dev/null || _fail "fail to mkfs"
	btrfs device scan >& /dev/null
	mount $DEV $MNT -o "nodatacow,autodefrag" || _fail "fail to mount"
}

check_run
test_setup
index=0
run_snapshots &
process_pids[$((index++))]=$!
run_balance &
process_pids[$((index++))]=$!
run_scrub &
process_pids[$((index++))]=$!
run_fsstress &
process_pids[$((index++))]=$!
sleep $run_time
