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
# instead of server_path and data_path.
# Consolidated the scripts backup-rotate and backup-rsync into one single script.
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

#List of files/directories to include and/or exclude
INCLUDES=./includes.txt

# Interval for backup folder naming d=daily, w=weekly, m=monthly, y=yearly
INTERVAL=d
MAXINT=7

# Additional rsync options.
# Example: EXTRAOPT="--bwlimit=196" to limit bandwidth-usage
EXTRAOPT=""

# Read parameter options
OPTIND=1
while getopts ":s:e:o:d:i:n" opt; do
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
		n)
			INCLUDES="$OPTARG"
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

##################################
## START ROTATING
##################################

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
#MAXVAL=$MAXINT-1
#for OLD in {$MAXVAL..1..-1}	; do
for (( OLD=$MAXINT-1; OLD>=1; OLD-- )) do
	echo "$DESTINATION/$INTERVAL.$OLD in progress"
	logger "$DESTINATION/$INTERVAL.$OLD in progress"
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

##################################
## END ROTATING
##################################

##################################
## START RSYNCING
##################################

# Make sure file for excludelist exists
if [ -f $EXCLUDES ] ; then
	echo "Using excludelist: $EXCLUDES"
	logger "Using excludelist: $EXCLUDES"
	EXCLUDES = "--exclude-from=\"$EXCLUDES\""
else
	# Fail
	echo "Could not find excludelist $EXCLUDES"
	logger "Could not find excludelist $EXCLUDES"
	EXCLUDES = ""
fi

# Make sure file for includelist exists
if [ -f $INCLUDES ] ; then
	echo "Using includelist: $INCLUDES"
	logger "Using includelist: $INCLUDES"
	INCLUDES = "--include-from=\"$INCLUDES\""
else
	# Fail
	echo "Could not find includelist $INCLUDES"
	logger "Could not find includelist $INCLUDES"
	INCLUDES = ""
fi

# create directory if needed
if ! [ -d $DESTINATION/$INTERVAL.0 ] ; then
	mkdir -p $DESTINATION/$INTERVAL.0
fi

# Here we go: rsync crates a full backup
echo "Starting rsync backup ..."
logger "Starting rsync backup ..."

echo "rsync -avz --numeric-ids -e ssh \
--delete --delete-excluded	\
--out-format="%t %f" \
$EXCLUDES $EXTRAOPT \
$SOURCE \
$DESTINATION/$INTERVAL.0"
logger "rsync -avz --numeric-ids -e ssh \
--delete --delete-excluded	\
--out-format="%t %f" \
$EXCLUDES $EXTRAOPT \
$SOURCE \
$DESTINATION/$INTERVAL.0"

rsync -avz --numeric-ids -e ssh \
	--delete --delete-excluded	\
	--out-format="%t %f" \
	$EXCLUDES $EXTRAOPT \
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


##################################
## END RSYNCING
##################################

# Remount disk as read-only
if $MOUNT_RO ; then
	if `mount -o remount,ro $MOUNT_DEVICE $DESTINATION` ; then
		echo "Error: Could not remount $MOUNT_DEVICE readonly"
		logger "Error: Could not remount $MOUNT_DEVICE readonly"
		exit
	fi
fi