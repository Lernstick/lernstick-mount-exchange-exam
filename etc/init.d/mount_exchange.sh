#!/bin/sh 
### BEGIN INIT INFO
# Provides:          live-mount-exchange
# Required-Start:    $local_fs $remote_fs dbus
# Required-Stop:     $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      
# Short-Description: Automatically mounts the lernstick exchange partition
# Description:       Automatically mounts the lernstick exchange partition
# X-Start-Before:    kdm gdm
### END INIT INFO
#
# description: Automatically mounts the lernstick exchange partition
#

# this tends to change from release to release...
LIVE_MOUNTPOINT="/run/live/medium"

get_partition() {
	NUMBER=$1
	# examples (with NUMBER=1):
	# "/dev/sda3" -> "/dev/sda1"
	# "/dev/nvme0n1p3" -> "/dev/nvme0n1p1"
	echo "${SYSTEM_PARTITION}" | sed "s|[0-9]*$|${NUMBER}|"
}

get_partition_label() {
	PARTITION=$1
	/sbin/blkid "${PARTITION}" -o udev | grep "ID_FS_LABEL=" | awk -F= '{ print $2 }'
}

get_partition_fstype() {
	PARTITION=$1
	/sbin/blkid "${PARTITION}" -o udev | grep "ID_FS_TYPE=" | awk -F= '{ print $2 }'
}

check_fstype() {
	PARTITION=$1
        FS_TYPE="$(get_partition_fstype "${PARTITION}")"
	echo "file system type of ${PARTITION}: \"${FS_TYPE}\"" >> ${LOG}
	if [ "${FS_TYPE}" = "vfat" ] || [ "${FS_TYPE}" = "exfat" ] || [ "${FS_TYPE}" = "ntfs" ]
	then
		EXCHANGE_PARTITION=${PARTITION}
	else
	        echo "${PARTITION} is not the exchange partition, exiting..." >> ${LOG}
	        exit 1
	fi
}

start_it_up()
{
	# use a log file
	LOG=/var/log/mount_exchange
	: > ${LOG}

	# the only reliable info about our boot medium is the system partition
	SYSTEM_PARTITION=$(grep ${LIVE_MOUNTPOINT} /proc/mounts | awk '{ print $1 }')
	echo "system partition: \"${SYSTEM_PARTITION}\"" >> ${LOG}

	# get infos about first partition
	FIRST_PARTITION="$(get_partition 1)"
	echo "first partition: \"${FIRST_PARTITION}\"" >> ${LOG}
	FIRST_LABEL="$(get_partition_label "${FIRST_PARTITION}")"
	echo "first label: \"${FIRST_LABEL}\"" >> ${LOG}
	SECOND_PARTITION="$(get_partition 2)"
	echo "second partition: \"${SECOND_PARTITION}\"" >> ${LOG}


	if [ "${FIRST_LABEL}" = "boot" ] || [  "${FIRST_LABEL}" = "EFI" ] || [ "${FIRST_LABEL}" = "Lernstick" ]
	then
		# system uses the current partitioning schema with a separate boot/EFI partition
		# check if the second partition is the exchange partition
		check_fstype "${SECOND_PARTITION}"

	else
		SECOND_LABEL="$(get_partition_label "${SECOND_PARTITION}")"
		echo "second label: \"${SECOND_LABEL}\"" >> ${LOG}
		if [ "${SECOND_LABEL}" = "boot" ] || [ "${SECOND_LABEL}" = "EFI" ] || [ "${SECOND_LABEL}" = "Lernstick" ]
		then
			# system uses the current partitioning schema with a separate boot/EFI partition
			# but for legacy (removable) USB flash drives
			# the first partition is the exchange partition
			EXCHANGE_PARTITION=${FIRST_PARTITION}

		else
			# system uses the legacy partitioning schema without a separate boot/EFI partition
			# check if the first partition is the system partition (also FAT32)
			if [ "${FIRST_PARTITION}" = "${SYSTEM_PARTITION}" ]
			then
			        echo "No exchange partition available, exiting..." >> ${LOG}
			        exit 1
			else
				# check file system of first partition (persistency partition would be ext2, ext3 or ext4)
				check_fstype "${FIRST_PARTITION}"
			fi
		fi
	fi

	# mount exchange partition
	echo "mounting ${EXCHANGE_PARTITION}" >> ${LOG}
	CONFIG_FILE="/etc/lernstickWelcome"
	if [ -f ${CONFIG_FILE} ]
	then
	        . ${CONFIG_FILE}
	fi
	MOUNT_DIR="/exchange/"
	MOUNT_POINT="${MOUNT_DIR}/partition"
	mkdir -p "${MOUNT_POINT}"
	chown root.root "${MOUNT_DIR}"
	FS_TYPE="$(get_partition_fstype "${EXCHANGE_PARTITION}")"
	echo "file system of exchange partition: \"${FS_TYPE}\"" >> ${LOG}
	if [ "${FS_TYPE}" = "vfat" ]
	then
		# In Linux kernel 4.7 the default iocharset for vfat changed from utf8
		# to ascii. This freaked out rdiff-backup because it then detected that case
		# sensitivity on the destination file system is off and therefore encoded
		# all upper-case letters with a combination of semicolon and decimal ascii
		# code, e.g. "B" -> ";66". This again freaked out Windows that was no longer
		# able to read or delete files on the exchange partition.
		# Therefore we now enforce the iocharset of utf8 for vfat file systems.
		MOUNT_OPTIONS="iocharset=utf8"
	fi
	if [ "${ExchangeAccess}" = "true" ]
	then
		MODE="755"
		if [ "${FS_TYPE}" = "vfat" ]
		then
			MOUNT_OPTIONS="${MOUNT_OPTIONS},umask=000"
		fi
	else
		MODE="700"
	fi
	chmod ${MODE} "${MOUNT_DIR}"

	if [ -n "${MOUNT_OPTIONS}" ]
	then
		mount -o "${MOUNT_OPTIONS}" "${EXCHANGE_PARTITION}" "${MOUNT_POINT}" >> ${LOG} 2>&1
	else
		mount "${EXCHANGE_PARTITION}" "${MOUNT_POINT}" >> ${LOG} 2>&1
	fi

	echo "done." >> ${LOG}
}

case "$1" in
  start)
    start_it_up
  ;;
  *)
    echo "Usage: /etc/init.d/mount_exchange start" >&2
    exit 2
  ;;
esac

