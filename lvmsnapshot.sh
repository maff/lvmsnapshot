#!/bin/bash
#
# LVM Snapshot & Mount Script
# Version 0.3

# Copyright (c) 2011 Mathias Geat <mathias@ailoo.net>
# with additions by Felix Moche <felix@moches.de>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#=====================================================================
# Changelog
#=====================================================================
#
# ver 0.3       (2011-03-13)
#       - Added snapshot/mount option for block volumes (KVM style)
#       - Config options can be set in config file or on command line
#
# ver 0.2       (2010-10-12)
#       - Check if root is running the script
#       - Improved error handling
#       - Improved output
#       - Optional config file
#
# ver 0.1.3     (2010-01-04)
#       - Fix wrong debug output in remove action
#
# ver 0.1.2     (2009-07-09)
#       - Add config options for needed commands
#
# ver 0.1.1     (2009-07-09)
#       - Bugfix for "lvdisplay not found"
#
# ver 0.1       (2009-07-08)
#       - Initial release
#
#=====================================================================

ME=$(basename $0)
ME_VERSION="0.3"

EXIT_SUCCESS=0
EXIT_FAILURE=1
EXIT_ERROR=2
EXIT_BUG=3

# will override default config if file exists
CONFIGFILE="/etc/lvmsnapshot/lvmsnapshot.conf"

#=====================================================================
# Default config values
# These values can be overridden by command line options and/or by
# config file (either in the above location or by using the -c option)
#=====================================================================

# Show debug output
DEBUG=0

# Don't show any output
QUIET=0

# Mode can be either partition (Xen style) or block (KVM style)
# Partition will be mounted directly, while block will be mapped
# with kpartx first and then mounted
MODE=partition

# Name of LVM volume group
GROUPNAME=vmstore

# LVM base path
LVMPATH=/dev

# LVM extension
# An extension which all LVM Volumes share, will be appended to the Volume name
LVMEXTENSION="-disk"

# Mount path
# Path where snapshots will be mounted to
MOUNTPATH=/mnt/lvmsnapshot

# Snapshot size
SNAPSHOTSIZE=1G

# Mapper base path
MAPPERPATH=/dev/mapper

# Number of mapped device (the number which will appended by kpartx to the
# partition which should be mounted.
MAPPERINDEX=1

# Identifier
# An identifier which will be appended to every snapshot
# (make sure you set a value!)
IDENTIFIER="-snapshot-lvmsnapshot"

# Paths to needed commands
LVDISPLAY=/sbin/lvdisplay
LVCREATE=/sbin/lvcreate
LVREMOVE=/sbin/lvremove
MOUNT=/bin/mount
UMOUNT=/bin/umount
GREP=/bin/grep
WC=/usr/bin/wc
RM=/bin/rm
KPARTX=/sbin/kpartx

#=====================================================================
# Set up shell
#=====================================================================

if `tty >/dev/null 2>&1` ; then
    COL_SUCCESS="\\033[1;32m"
    COL_ERROR="\\033[1;31m"
    COL_NORMAL="\\033[0;39m"
else
    COL_SUCCESS=""
    COL_ERROR=""
    COL_NORMAL=""
fi

#=====================================================================
# Common functions
#=====================================================================

function output {
    if [ ! $QUIET -eq 1 ]; then
        echo $@
    fi
}

function outputne {
    if [ ! $QUIET -eq 1 ]; then
        echo -ne $@
    fi
}

function echo_success {
    outputne "${COL_SUCCESS}$@${COL_NORMAL}"
}

function echo_error {
    echo -ne "${COL_ERROR}$@${COL_NORMAL}" >&2
}

function status_success {
    outputne "${COL_SUCCESS}$@${COL_NORMAL}\n"
}

function status_error {
    echo -ne "${COL_ERROR}$@${COL_NORMAL}\n" >&2
}

function error {
    status_error "$@"
    exit $EXIT_ERROR
}

function checkmount {
    LINES=`$MOUNT | $GREP $@ | $WC -l`
    if [ $LINES -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

function checkvolume {
    outputne "Checking availability of volume..."

    $LVDISPLAY $@ > /dev/null 2>&1
    if [ $? -ne 0  ]; then
        status_error "failed"
        error "Volume '$VOLUMEPATH' does not exist."
    else
        status_success "ok"
    fi
}

function cleanup {
    outputne "Deleting mount directory at $MOUNTPOINT..."
    $RM -rf $MOUNTPOINT

    if [ $? -eq 0 ]; then
        status_success "ok"
    else
        status_error "failed"
    fi
}

function usage {
    cat <<USAGE
$(version_info)

LVM VG:     ${LVMPATH}/${GROUPNAME}
MOUNT PATH: ${MOUNTPATH}/${GROUPNAME}

DESCRIPTION:
  Automated creation and removal of LVM snapshots.

USAGE:
  $ME <options> <command> <volumename>

OPTIONS:
  -c CONFIGFILE     Use specified config file
  -d                Debug output
  -e LVMEXTENSION   LVM volume extension, which will be appended to the volume name
  -g GROUPNAME      LVM volume group name
  -h                Show this help
  -i MAPPERINDEX    Mapper index when using block device mode
  -m MODE           Mode to use, either block or partition
  -q                Be quiet

COMMANDS:
  create:     create LVM snapshot and mount to MOUNTPATH
  remove:     remove LVM snapshot

EXAMPLES:
  $ME -c /etc/lvmsnapshot.conf create vm01
  $ME -m block -i 1 -g vmstore create vm01
  $ME remove vm01
USAGE

    exit $1 || exit $EXIT_FAILURE
}

function version_info {
    cat <<END
$ME version $ME_VERSION

END
}

#=====================================================================
# Make sure only root can run our script
#=====================================================================

if [ "$(id -u)" != 0 ]; then
    error "This script must be run as root."
fi

#=====================================================================
# Parse options
#=====================================================================

while getopts ':m:e:g:c:i:ndqh' OPTION ; do
    case $OPTION in
        m)
            if [[ $OPTARG == "partition" || $OPTARG == "block" ]]; then
                OPT_MODE=$OPTARG
            else
                error "-m: invalid argument $OPTARG"
            fi
            ;;

        g)
            OPT_GROUPNAME=$OPTARG
            ;;

        e)
            OPT_LVMEXTENSION=$OPTARG
            ISSET_OPT_LVMEXTENSION="True"
            ;;

        c)
            if [ -r $OPTARG ]; then
                CONFIGFILE=$OPTARG
            else
                error "Could not read config file $OPTARG"
            fi
            ;;

        i)
            OPT_MAPPERINDEX=$OPTARG
            ;;

        n)
            OPT_NOACTION=1
            ;;

        d)
            OPT_DEBUG=1
            ;;

        q)
            OPT_QUIET=1
            ;;

        h)
            usage
            ;;
        \?)
            echo " \"-$OPTARG\"." >&2
            usage $EXIT_ERROR
            ;;
        :)
            echo "\"-$OPTARG\" needs an argument." >&2
            usage $EXIT_ERROR
            ;;
        *)
            status_error "This shouldn't have happened."
            usage $EXIT_BUG
            ;;
    esac
done

# Shift arguments
shift $(( OPTIND - 1 ))

#=====================================================================
# Read config file
#=====================================================================

if [ -r $CONFIGFILE ]; then
    source $CONFIGFILE
fi

#=====================================================================
# Map options to config
#=====================================================================

if [ ! -z $OPT_MODE ]; then
    MODE=$OPT_MODE
fi

if [ ! -z $OPT_GROUPNAME ]; then
    GROUPNAME=$OPT_GROUPNAME
fi

if [ ! -z $OPT_MAPPERINDEX ]; then
    MAPPERINDEX=$OPT_MAPPERINDEX
fi

if [ ! -z $ISSET_OPT_LVMEXTENSION ]; then
    LVMEXTENSION=$OPT_LVMEXTENSION
fi

if [ ! -z $OPT_DEBUG ]; then
    DEBUG=$OPT_DEBUG
fi

if [ ! -z $OPT_QUIET ]; then
    QUIET=$OPT_QUIET
fi

#=====================================================================
# Parse parameters
#=====================================================================

if [ -z $1 ]; then
    echo_error "Please specify a command.\n"
    usage $EXIT_ERROR
fi

if [ -z $2 ]; then
    echo_error "Please specify a volume name.\n"
    usage $EXIT_ERROR
fi

#=====================================================================
# Init
#=====================================================================

MOUNTPOINT=$MOUNTPATH/$GROUPNAME/$2

VOLUMENAME=${2}${LVMEXTENSION}
VOLUMEPATH=$LVMPATH/$GROUPNAME/$VOLUMENAME

SNAPSHOTNAME=${VOLUMENAME}${IDENTIFIER}
SNAPSHOTPATH=$LVMPATH/$GROUPNAME/$SNAPSHOTNAME

if [[ $MODE == "block" ]]; then
    MAPPEDNAME=${GROUPNAME}-${SNAPSHOTNAME//-/--}${MAPPERINDEX}
    MAPPEDPATH=$MAPPERPATH/$MAPPEDNAME
fi

#=====================================================================
# Status output
#=====================================================================

if [ $DEBUG -eq 1 ]; then
    cat <<END
  MOUNTPOINT:   $MOUNTPOINT
  VOLUMEPATH:   $VOLUMEPATH
  SNAPSHOTPATH: $SNAPSHOTPATH
END

    if [[ $MODE == "block" ]]; then

        echo "  MAPPEDPATH:   $MAPPEDPATH"
    fi
fi

#=====================================================================
# Program logic
#=====================================================================

if [ ! -z $OPT_NOACTION ]; then
    exit $EXIT_SUCCESS
fi

checkvolume $VOLUMEPATH

if [ $1 = "create" ]; then

    #=====================================================================
    # Create Snapshot
    #=====================================================================

    outputne "Checking if mountpoint is mounted..."

    checkmount $MOUNTPOINT
    if [ $? -eq 0 ]; then
        status_error "yes"
        error "Mountpoint is mounted. Please unmount and re-run."
    else
        status_success "no"
    fi

    outputne "Creating snapshot..."
    $LVCREATE -L $SNAPSHOTSIZE -s -n $SNAPSHOTNAME $VOLUMEPATH > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        status_success "ok"

        if [[ $MODE == "block" ]]; then
            outputne "Mapping snapshot partitions..."
            $KPARTX -a $SNAPSHOTPATH > /dev/null 2>&1

            if [ $? -eq 0 ]; then
                status_success "ok"

                if [ -b $MAPPEDPATH ]; then
                    status_success "Found mapped device."
                else
                    error "Could not find mapped device"
                fi
            else
                status_error "failed"
                error "Error while mapping block device partitions."
            fi
        fi

        if [ -d $MOUNTPOINT ]; then
            output "Mount directory exists, ommiting mkdir."
        else
            outputne "Creating mountpoint directory..."

            mkdir -p $MOUNTPOINT > /dev/null 2>&1
            if [ $? -eq 0 ]; then
                status_success "ok"
            else
                status_error "failed"
                error "Error while creating mountpoint directory."
            fi
        fi

        outputne "Mounting snapshot..."

        if [[ $MODE == "block" ]]; then
            $MOUNT $MAPPEDPATH $MOUNTPOINT > /dev/null 2>&1
        else
            $MOUNT $SNAPSHOTPATH $MOUNTPOINT > /dev/null 2>&1
        fi

        if [ $? -eq 0 ]; then
            status_success "ok"
            exit 0
        else
            status_error "failed"
            cleanup
            error "Error while mounting snapshot."
        fi
    else
        status_error "failed"
        error "Error while creating snapshot."
    fi

elif [ $1 = "remove" ]; then

    #=====================================================================
    # Remove Snapshot
    #=====================================================================

    outputne "Checking if mountpoint is mounted..."

    checkmount $MOUNTPOINT
    if [ $? -eq 0 ]; then
        status_success "yes"
    else
        status_error "no"
        error "Mountpoint is not mounted. Please mount and re-run."
    fi

    outputne "Unmounting snapshot..."
    $UMOUNT $MOUNTPOINT > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        status_success "ok"

        if [[ $MODE == "block" ]]; then
            outputne "Unmapping snapshot partitions..."
            $KPARTX -d $SNAPSHOTPATH > /dev/null 2>&1

            if [ $? -eq 0 ]; then
                status_success "ok"
            else
                status_error "failed"
                error "Error while unmapping block device partitions."
            fi
        fi

        cleanup

        outputne "Removing snapshot..."
        $LVREMOVE -f $SNAPSHOTPATH > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            status_success "ok"
        else
            status_error "failed"
            error "Error while removing snapshot, please remove manually."
        fi
    else
        status_error "failed"
        error "Error while unmounting snapshot."
    fi

else
    error "Unknown command: $1"
    echo
    usage $EXIT_ERROR
fi
exit $EXIT_SUCCESS
