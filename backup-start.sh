#!/bin/bash
#

# Rotate directories
./backup-rotate.sh -d /mnt/backup2 -i w >> ../logs/log-rotate.log

# Start backup
./backup-rsync.sh -s /mnt/hdd3/scripts/test -e ./exclude.txt -d /mnt/backup2 -i w &> ../logs/log-rsync.log
