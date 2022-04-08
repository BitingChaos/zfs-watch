#!/bin/sh
#
# ZFS pool check script for FreeBSD and Linux (limited testing on macOS)
#
# run this in a cronjob every X minutes (or hours)
#
# DON'T FORGET TO ADJUST SETTINGS BELOW
#
# What does this do?
# checks zfs pool status:
# pool status good? do nothing.
# pool status bad? do this:
# check log file timestamp. timestamp less than X? do nothing.
# log file not exist or timestamp older than X? do this:
# 1) send email notice that pool may need attention
# 2) update log file with current timestamp
#
# You can add this to your crontab to run every few minutes or hours
# to query every 10 minutes:
# */10 * * * * /opt/scripts/zfs_watch.sh > /dev/null 2>&1
#
# (It will only email you as often as specified in this file.)
#
# 2022-04-08
# * added time/date to zpool status output
# * runs zpool status through sed to correct missing percent sign
# * updated changelog date format and other text
#
# 2019-09-20
# * updated email output to mention pool in subject and
#   script name in message body.
#
# 2019-06-19
# * added OS checks to adjust commands as needed so that
#   one script can run on many platforms without modification.
# * switched from bash to sh
# * updated output formatting
#
# 2019-05-23
# * improved the way mail is sent under BSD
#
# 2018-10-19
# * updated script with Linux support
#
# 2018-09-04
# * re-did script to auto check all pools.
#   (no need to specify pool on command line.)
# * added check for zpool command
#
# 2018-08-30
# * moved more commands to variables
# * switched from echo to printf
#
# 2018-06-19
# * changed it so you can add pool name on command line
#   (to make it easier to monitor multiple pools in crontab)
# * added pool name check
# * added pool name to check file
#
# 2015-05-19
# * added more commands as variables
#
# 2015-05-15
# * added email address option
# * added hostname check
#
# 2015-05-08
# * first version
#
# Nicholas Caito
# ncaito@gmail.com
#

# ----- user variables -----

# user or email address to send notice to
USER="root"

# how far apart should notifications emails be sent, in seconds.
# 21600 = 6 hours
# 43200 = 12 hours
EMAILTIME=21600

# location for email log file
FILELOC="/tmp"

# status to look for. usually "ONLINE"
# for debugging: you can change this to something else to test the script.
STATUS="ONLINE"


# ----- first things, first -----

# are you root?
if [ $(whoami) != "root" ]; then
	printf "\nPlease run this script as root (or using sudo).\n\n"
	exit 1
fi

# does zpool exist?
if [ -z "$(which zpool)" ]; then
	printf "\nThe \"zpool\" binary was not found. Is it installed?\n\n"
	exit 1
fi

# determine OS and set commands

case $(uname | tr '[:upper:]' '[:lower:]') in
 linux*)
  export OS="Linux"
  export MAILCMD="/usr/sbin/sendmail"
  export ST="/usr/bin/stat --printf %Y"
  export SD="/bin/sed"
  ;;
 freebsd*)
  export OS="FreeBSD"
  export MAILCMD="/usr/bin/mail -s"
  export ST="/usr/bin/stat -f %Sm -t %s -n"
  export SD="/usr/bin/sed"
  ;;
 darwin*)
  export OS="macOS"
  export MAILCMD="/usr/bin/mail -s"
  export ST="/usr/bin/stat -f %Sm -t %s -n"
  export SD="/usr/bin/sed"
  ;;
 *)
  # export OS="Unknown"
  printf "\nUnknown OS detected!\n\n"
  exit 1
  ;;
esac

# /bin/uname : Linux
# /usr/bin/uname : BSD/Darwin

# set up some commands
WH="/usr/bin/whoami"
PF="/usr/bin/printf"
ZP="/sbin/zpool"

# other command variables
TC="/usr/bin/touch"

# get current timestamp
CURRENT=$(/bin/date +%s)

# get full hostname
HOST=$(/bin/hostname -f)

# -----

$PF "\nZFS check for [$HOST] ($OS)\n\n"


# crontab note
$PF "You can add \"> /dev/null 2>&1\" to end of this command entry in\n"
$PF "crontab to prevent receiving the detailed output (you will still\n"
$PF "receive an email if an error is detected).\n"

# list pools
LISTPOOLS="$(${ZP} list -H -o name)"

# exit if there are no pools
if [ ! "$LISTPOOLS" ]; then
	$PF "\nNo pools were found!\n\n"
	exit 0
fi

# -----

$PF "\nListing all pools and their current status.\n"

for POOL in ${LISTPOOLS}; do

	# pool ok init
	OK="YES"

	# send mail init
	SEND="NO"

	# check pool health
	HEALTH="$(${ZP} list -H -o health ${POOL})"
  
	$PF "\n************************************************************\n"

	$PF "Pool: [${POOL}], Status: $HEALTH"

	if [ "$HEALTH" = "$STATUS" ]; then
		$PF " - It looks good!\n"
		# do nothing
	else
		$PF " - Expecting \"$STATUS\", found \"$HEALTH\". Not good!\n"
		OK="NO"
		# if status is wrong, then go to the file
	fi

	# --- check file ---
	if [ $OK = "NO" ]; then

		# set log file
		FILE="$FILELOC/zfs-status-pool-${POOL}.log"

		$PF "Pool status was not OK. Checking for log file... ($FILE)\n"

		# check if file exists
		if [ -f $FILE ]; then

			$PF "Log file exists, checking timestamp...\n"
			# get file timestamp
			FILETIME=$($ST $FILE)

			# $PF "File time: $FILETIME\n"

			# compare time
			if [ $(($CURRENT-$FILETIME)) -ge $EMAILTIME ]; then

				$PF "The log file is old! Will send email.\n"

				# send mail
				SEND="YES"

			else
				# log file is recent
				$PF "The log file is recent. Will not send email this time.\n"
			fi

		else
			# file does not exist
			$PF "Log file does not exist. Will send email.\n"

			# send mail
			SEND="YES"

		fi
		# end file check
	fi

	# need to send email?
	if [ $SEND = "YES" ]; then

		# get status and fix percent sign for printf
		POOLSTATUS=$(${ZP} status -T d ${POOL} | ${SD} "s/%/%%/g")

		# show zpool status in body of email
		FULLSTATUS="The zfs-watch script has detected a potential problem:\n\n$POOLSTATUS\n"

		# send mail
		$PF "Sending email...\n"

		if [ $OS = "FreeBSD" ] || [ $OS = "macOS" ]; then

			$($PF "$FULLSTATUS" | $MAILCMD "ZFS alert for ${POOL} on $HOST!" $USER)

		else

			$($PF "From: $USER\nTo: $USER\nSubject: ZFS alert for ${POOL} on $HOST!\n\n$FULLSTATUS" | $MAILCMD $USER)

		fi

		# update file
		$PF "Updating log file...\n"

		# update time stamp
		$TC $FILE
	fi

# done checking each pool
done   

$PF "\n"

# EoF
