# rsync-backup-and-rotate

This script provides a simple way to run rsync and rotate the backups to keep copies of modified files.

The rotation is done with hardlinks, which means that the disk space is only used for multiple copies of
an unchanged file in multiple backup sets (daily, monthly, yearly). Only changed files contribute to the disk space.

## Usage

Use crontab or similar for calling the script with parameters periodically.

### Configuration

rsync

    backup-rsync
        -s                      # path to source
        -d /backup/path         # (optional) path to destination, default is "/mnt/backup"
        -e exclude.txt          # (optional) path to excludefile, default is ./exclude.txt
        -i d                    # (optional) interval: d = daily, w = weekly, m = monthly, y = yearly, 
                                # default is d; only for correct naming of directories!
                                # Configure run interval via crontab!
        -o extra rsync options  # (optional) additional rsync parameters (see "man rsync")

The backup will be written into the directory `/backup/path/daily.0/`

Excludefile sample

    + /etc
    + /var/
    + /var/www
    - /var/www/backup
    + /var/vmail
    - /var/*
    - /*
    - @*
    - *.bak

### On Synology box (busybox system)

Busybox / Synology systems do not have bash installed (by default), but
"ash". To execute the scripts, you simply have to call ash to execute
the scripts.

Example to run script on home Synology to backup web server:

    ash /volume1/data/bin/rsync-backup-and-rotate/backup-rsync -e /volume1/data/bin/server-backup.excludelist -p /volume1/data/Data my.server.com &> /volume1/data/Data/server-backup-rsync.log

This script can be scheduled and executed via Task Scheduler (Control Panel/Task Scheduler, Create "User-defined script").

## Credits

The original version of these scripts have been created by Heinlein Support and were
published to the German Linux Magazine 09/2004.
https://www.heinlein-support.de/howto/backups-und-snapshots-von-linux-servern-mit-rsync-und-ssh
