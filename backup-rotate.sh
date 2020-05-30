#!/bin/bash
#
# This script rotates the backup directories.
#
# Original authors: https://www.heinlein-support.de
# Original source: https://www.heinlein-support.de/projekte/rsync-backup/backup-rotate
#
# Translated and enhanced by Mattanja Kern <https://github.com/mattanja/rsync-backup-and-rotate>
#
# Modified for local use by s-kestler <https://github.com/s-kestler/rsync-backup-and-rotate>
# I also renamed a few variables to keep them in line with rsync naming (e.g. source and destination
# instead of server_path and data_path
#
# Usage: backup-rotate [-p /backup/path] [-i d, w, m, y for daily, weekly, monthly, yearly]
#

# ### Configuration
# Check available space?
CHECK_HDMINFREE=true
HDMINFREE=95

# Mount backup partition as readonly after writing the backup?
MOUNT_RO=false
MOUNT_DEVICE=/dev/md3

# Backup path (server name and rotation dirs will be appended)
DESTINATION=/mnt/backup

# Interval for backup folder naming d=daily, w=weekly, m=monthly, y=yearly
INTERVAL=d
MAXINT=7

# Read parameter options
OPTIND=1
while getopts ":d:i:" opt; do
	case $opt in
		d)
			DESTINATION="$OPTARG"
			;;
		i)
			INTERVAL="$OPTARG"
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			logger "Invalid option: -$OPTARG" >&2
			exit 1
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			logger "Option -$OPTARG requires an argument." >&2
			exit 1
			;;
	esac
done
shift $((OPTIND-1))

case $INTERVAL in
	d)
		INTERVAL="daily"
		MAXINT=7
		;;
	w)
		INTERVAL="weekly"
		MAXINT=4
		;;
	m)
		INTERVAL="monthly"
		MAXINT=12
		;;
	y)
		INTERVAL="yearly"
		MAXINT=50
		;;
	:)
		echo "Invalid argument for option Interval." >&2
		logger "Invalid argument for option Interval." >&2
		exit 1
		;;
esac

# Log config info
echo "Backup path: $SOURCE"
logger "Backup path: $SOURCE"
echo "Backup path: $DESTINATION"
logger "Backup path: $DESTINATION"

# ### Let`s Rock`n`Roll....

# Check available space and inodes
GETPERCENTAGE='s/.* \([0-9]\{1,3\}\)%.*/\1/'
if $CHECK_HDMINFREE ; then
	KBISFREE=`df /$DESTINATION | tail -n1 | sed -e "$GETPERCENTAGE"`
	INODEISFREE=`df -i /$DESTINATION | tail -n1 | sed -e "$GETPERCENTAGE"`
	if [ $KBISFREE -ge $HDMINFREE -o $INODEISFREE -ge $HDMINFREE ] ; then
		echo "Fatal: Not enough space left for rotating backups!"
		logger "Fatal: Not enough space left for rotating backups!"
		exit
	fi
fi

# Mount as read/write if configured
if $MOUNT_RO ; then
	if `mount -o remount,rw $MOUNT_DEVICE $DESTINATION` ; then
		echo "Error: Could not remount $MOUNT_DEV readwrite"
		logger "Error: Could not remount $MOUNT_DEV readwrite"
		exit
	fi
fi

# Create backup dir
if ! [ -d $DESTINATION/$INTERVAL.0 ] ; then
	mkdir -p $DESTINATION/$INTERVAL.0
fi

STARTDATE=$(date +'%Y-%m-%d %T')
echo "$STARTDATE Rotating snapshots ..."
logger "$STARTDATE Rotating snapshots ..."

# Delete oldest daily backup
if [ -d $DESTINATION/$INTERVAL.$MAXINT ] ; then
	rm -rf $DESTINATION/$INTERVAL.$MAXINT
fi

# Shift all other daily backups ahead one day
#for OLD in 6 5 4 3 2 1	; do
for OLD in {$(($MAXINT-1))..1}	; do
	if [ -d $DESTINATION/$INTERVAL.$OLD ] ; then
		NEW=$(($OLD+1))

		echo "Moving $DESTINATION/$INTERVAL.$OLD to $DESTINATION/$INTERVAL.$NEW"
		logger "Moving $DESTINATION/$INTERVAL.$OLD to $DESTINATION/$INTERVAL.$NEW"

		# Backup last date
		# ISSUE: touch does not support options on synology (busybox) system
		#touch $DESTINATION/.timestamp -r $DESTINATION/$INTERVAL.$OLD
		mv $DESTINATION/$INTERVAL.$OLD $DESTINATION/$INTERVAL.$NEW
		# Restore timestamp
		#touch $DESTINATION/$INTERVAL.$NEW -r $DESTINATION/.timestamp

	fi
done

# Copy hardlinked snapshot of level 0 to level 1 (before updating 0 via rsync)
if [ -d $DESTINATION/$INTERVAL.0 ] ; then

	echo "Copying hardlinks from $DESTINATION/$INTERVAL.0 to $DESTINATION/$INTERVAL.1"
	logger "Copying hardlinks from $DESTINATION/$INTERVAL.0 to $DESTINATION/$INTERVAL.1"

	cp -al $DESTINATION/$INTERVAL.0 $DESTINATION/$INTERVAL.1
fi

ENDDATE=$(date +'%Y-%m-%d %T')
echo "$ENDDATE Finished rotating snapshots ..."
logger "$ENDDATE Finished rotating snapshots ..."

# Mount as read-only if configured
if $MOUNT_RO ; then
	if `mount -o remount,ro $MOUNT_DEVICE $DESTINATION` ; then
		echo "Error: Could not remount $MOUNT_DEV readonly"
		logger "Error: Could not remount $MOUNT_DEV readonly"
		exit
	fi
fi
