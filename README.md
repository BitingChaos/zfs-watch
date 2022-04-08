## zfs-watch
 
## ZFS pool check and email script for FreeBSD and Linux
I wanted a way to get notifications if any of my ZFS pools had an issue (usually because of failing hard drives). Not all of my systems reported when a drive was experiencing issues, so I had to rely on the OS itself.


## To use
1. Copy `zfs-watch.sh` somewhere on your system (`/opt/scripts`, for example) and make it executable (`chmod +x zfs-watch.sh`)
2. Modify any settings in the file to your liking (such as how often to receive emails or who to send the emails to)
3. Add a line to your crontab so that the script runs every few minutes, such as `*/10 * * * * /opt/scripts/zfs_watch.sh > /dev/null 2>&1`

## Other
I'm sure there are better ways of doing what this script does, but I've been using this for several years on the FreeBSD and Linux systems that I use.

