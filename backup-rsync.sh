#!/bin/bash
#
# This script creates rsync backups of a server
#
# Original authors: https://www.heinlein-support.de
# Original source: https://www.heinlein-support.de/projekte/rsync-backup/backup-rsync
#
# Translated and enhanced by Mattanja Kern <https://github.com/mattanja/rsync-backup-and-rotate>
#
# Modified for local use by s-kestler <https://github.com/s-kestler/rsync-backup-and-rotate>
# I also renamed a few variables to keep them in line with rsync naming (e.g. source and destination
# instead of server_path and data_path
#
# Usage: backup-rsync [-s /path/to/source] [-e path/to/excludelist] [-o additional options] [-d /path/to/destination] [-i d, w, m, y for daily, weekly, monthly, yearly]
#

# ### Configuration
# Check available space?
CHECK_HDMINFREE=true
HDMINFREE=95

# Mount backup partition as readonly after writing the backup?
MOUNT_RO=false
MOUNT_DEVICE=/dev/sdb

# Backup path (server name and rotation dirs will be appended)
DESTINATION=/mnt/backup

# Liste von Dateipattern, die nicht gebackupt werden sollen
EXCLUDES=./exclude.txt

# Interval for backup folder naming d=daily, w=weekly, m=monthly, y=yearly
INTERVAL=d

# Additional rsync options.
# Example: EXTRAOPT="--bwlimit=196" to limit bandwidth-usage
EXTRAOPT=""

# Read parameter options
OPTIND=1
while getopts ":s:e:o:d:i:" opt; do
	case $opt in
		s)
			SOURCE="$OPTARG"
			;;
		e)
			EXCLUDES="$OPTARG"
			;;
		o)
			EXTRAOPT="$OPTARG"
			;;
		d)
			DESTINATION="$OPTARG"
			;;
		i)
			INTERVAL="$OPTARG"
			;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			logger "Invalid option: -$OPTARG" >&2
			echo "Use backup-rsync [-s /path/to/source] [-e path/to/excludelist] [-o additional options] [-d /path/to/destination] [-i d, w, m, y for daily, weekly, monthly, yearly]"
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
echo "Extra options: $EXTRAOPT"
logger "Extra options: $EXTRAOPT"
echo "Source path: $SOURCE"
logger "Source path: $SOURCE"
echo "Backup path: $DESTINATION"
logger "Backup path: $DESTINATION"

# if [ -n "$SSH_ADDRESS" ] ; then
# # If parameter -s is provided, use it as target address for rsync command (including username)
	# echo "SSH_ADDRESS provided: $SSH_ADDRESS"
	# RSYNCSERVERPATH="$SSH_ADDRESS:/"
# elif [ $TARGETNAME = "localhost" ] ; then
# # If server is localhost, use simple local path
	# echo "Targetname localhost"
	# RSYNCSERVERPATH="/"
# else
	# echo "Targetname provided: $TARGETNAME"
	# RSYNCSERVERPATH="$TARGETNAME:/"
# fi

# Make sure file for excludelist exists
if [ -f $EXCLUDES ] ; then
	echo "Using excludelist: $EXCLUDES"
	logger "Using excludelist: $EXCLUDES"
else
	# Fail
	echo "Could not find excludelist $EXCLUDES"
	logger "Could not find excludelist $EXCLUDES"
	exit 1
fi

# ### Let´s Rock`n`Roll

# Check disk space
GETPERCENTAGE='s/.* \([0-9]\{1,3\}\)%.*/\1/'
if $CHECK_HDMINFREE ; then
	KBISFREE=`df /$DESTINATION | tail -n1 | sed -e "$GETPERCENTAGE"`
	INODEISFREE=`df -i /$DESTINATION | tail -n1 | sed -e "$GETPERCENTAGE"`
	if [ $KBISFREE -ge $HDMINFREE -o $INODEISFREE -ge $HDMINFREE ] ; then
		echo "Fatal: Not enough space left for rsyncing backups!"
		logger "Fatal: Not enough space left for rsyncing backups!"
		exit 1
	fi
fi

# Mount disk as read/write if configured
if $MOUNT_RO ; then
	if `mount -o remount,rw $MOUNT_DEVICE $DESTINATION` ; then
	echo mount -o remount,rw $MOUNT_DEVICE $DESTINATION
		echo "Error: Could not remount $MOUNT_DEVICE readwrite"
		logger "Error: Could not remount $MOUNT_DEVICE readwrite"
		exit
	fi
fi

# Ggf. Verzeichnis anlegen
if ! [ -d $DESTINATION/$INTERVAL.0 ] ; then
	mkdir -p $DESTINATION/$INTERVAL.0
fi

# Los geht`s: rsync zieht ein Vollbackup
echo "Starting rsync backup ..."
logger "Starting rsync backup ..."

echo "rsync -avz --numeric-ids -e ssh \
--delete --delete-excluded	\
--out-format="%t %f" \
--exclude-from="$EXCLUDES" $EXTRAOPT \
$SOURCE \
$DESTINATION/$INTERVAL.0"
logger "rsync -avz --numeric-ids -e ssh \
--delete --delete-excluded	\
--out-format="%t %f" \
--exclude-from="$EXCLUDES" $EXTRAOPT \
$SOURCE \
$DESTINATION/$INTERVAL.0"

rsync -avz --numeric-ids -e ssh \
	--delete --delete-excluded	\
	--out-format="%t %f" \
	--exclude-from="$EXCLUDES" $EXTRAOPT \
	$SOURCE \
	$DESTINATION/$INTERVAL.0

# Validate return code
# 0 = no error,
# 24 is fine, happens when files are being touched during sync (logs etc)
# all other codes are fatal -- see man (1) rsync
if ! [ $? = 24 -o $? = 0 ] ; then
	echo "Fatal: rsync finished with errors!"
	logger "Fatal: rsync finished with errors!"
fi

# Touch dir to set backup date
touch $DESTINATION/$INTERVAL.0

# Done
echo "Finished rsync backup ..."
logger "Finished rsync backup ..."

# Sync disks to make sure data is written to disk
sync

# Remount disk as read-only
if $MOUNT_RO ; then
	if `mount -o remount,ro $MOUNT_DEVICE $DESTINATION` ; then
		echo "Error: Could not remount $MOUNT_DEVICE readonly"
		logger "Error: Could not remount $MOUNT_DEVICE readonly"
		exit
	fi
fi