#!/bin/bash
#
# LVM Snapshot & Mount Script
# Version 0.2
# Copyright (c) 2009 Mathias Geat <mathias@ailoo.net>
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
# Set the following variables to your system needs
#=====================================================================

CONFIGFILE="/etc/lvmsnapshot/lvmsnapshot.conf"

if [ -r ${CONFIGFILE} ]; then
    # Read the configfile if it's existing and readable
    source ${CONFIGFILE}
else
    # do inline-config otherwise
    # To create a configfile just copy the code between "### START CFG ###" and "### END CFG ###"
    # to /etc/lvmsnapshot/lvmsnapshot.conf. After that you're able to upgrade this script
    # (copy a new version to its location) without the need for editing it.

    ### START CFG ###

    # LVM base path (Volume Group)
    LVMPATH=/dev/lvmstore

    # LVM extension
    # An extension which all LVM Volumes share, will be appended to the Volume name
    LVMEXTENSION="-disk"

    # Mount path
    # Path where snapshots will be mounted to
    MOUNTPATH=/mnt/lvm

    # Snapshot size
    SNAPSHOTSIZE=1G

    # Identifier
    # An identifier which will be appended every snapshot
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

    ### END CFG ###
fi

#=====================================================================
#=====================================================================
#=====================================================================
#
# Should not need to be modified from here!
#
#=====================================================================
#=====================================================================
#=====================================================================

ME=$(basename $0)
ME_VERSION="0.2"

#=====================================================================
# Set up shell
#=====================================================================

if `tty >/dev/null 2>&1` ; then
    COL_SUCCESS="\\033[1;32m"
    COL_FAILURE="\\033[1;31m"
    COL_NORMAL="\\033[0;39m"
else
    COL_SUCCESS=""
    COL_FAILURE=""
    COL_NORMAL=""
fi

#=====================================================================
# Common functions
#=====================================================================

function echo_success {
    echo -ne "${COL_SUCCESS}$@${COL_NORMAL}"
}

function echo_error {
    echo -ne "${COL_FAILURE}$@${COL_NORMAL}"
}

function status_success {
    echo -ne "${COL_SUCCESS}$@${COL_NORMAL}\n"
}

function status_failure {
    echo -ne "${COL_FAILURE}$@${COL_NORMAL}\n"
}

function error {
    echo -ne "\n" 2>&1
    echo_error "ERROR: $@" 2>&1
    echo -ne "\n" 2>&1
    exit 1
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
    echo -ne "Checking availability of volume..."

    $LVDISPLAY $@ > /dev/null 2>&1
    if [ $? -ne 0  ]; then
        status_failure "failed"
        error "Volume '$LVMVOLUME' does not exist."
    else
        status_success "ok"
    fi
}

function cleanup {
    echo -ne "Deleting mount directory at $MOUNTPOINT..."
    $RM -rf $MOUNTPOINT

    if [ $? -eq 0 ]; then
        status_success "ok"
    else
        status_failure "failed"
    fi
}

function usage_info {
    cat <<USAGE
VERSION:
$(version_info)

LVM VG:     ${LVMPATH}
MOUNT PATH: ${MOUNTPATH}

DESCRIPTION:
  Automated creation and removal of LVM snapshots.

USAGE:
  $ME <command> <lvmvolume>

COMMANDS:
  create:     create a LVM snapshot and mount to MOUNTPATH
  remove:     remove a LVM snapshot
USAGE
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
    error "This script must be run as root"
fi

#=====================================================================
# Parse params
#=====================================================================

if [ -z $1 ]; then
    echo "Please specify a command."
    echo
    usage_info
    exit 1
fi

if [ -z $2 ]; then
    echo "Please specify a volume name."
    echo
    usage_info
    exit 1
fi

MOUNTPOINT=$MOUNTPATH/$2
LVMVOLUME=$LVMPATH/${2}${LVMEXTENSION}
LVMSNAPSHOT=${2}${LVMEXTENSION}${IDENTIFIER}

    cat <<END
SETTINGS:
  MOUNTPOINT:   $MOUNTPOINT
  LVMVOLUME:    $LVMVOLUME
  LVMSNAPSHOT:  $LVMSNAPSHOT

END

checkvolume $LVMVOLUME

#=====================================================================
# Program logic
#=====================================================================

if [ $1 = "create" ]; then

    #=====================================================================
    # Create Snapshot
    #=====================================================================

    echo -ne "Checking if mountpoint is mounted..."

    checkmount $MOUNTPOINT
    if [ $? -eq 0 ]; then
        status_failure "yes"
        error "Mountpoint is mounted. Please unmount and re-run."
    else
        status_success "no"
    fi

    echo -ne "Creating snapshot..."
    $LVCREATE -L $SNAPSHOTSIZE -s -n $LVMSNAPSHOT $LVMVOLUME > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        status_success "ok"

        if [ -d $MOUNTPOINT ]; then
            echo "Mount directory exists, ommiting mkdir."
        else
            echo -ne "Creating mountpoint directory..."

            mkdir -p $MOUNTPOINT
            if [ $? -eq 0 ]; then
                status_success "ok"
            else
                status_failure "failed"
                error "Error while creating mountpoint directory."
            fi
        fi

        echo -ne "Mounting snapshot..."
        $MOUNT $LVMPATH/$LVMSNAPSHOT $MOUNTPOINT

        if [ $? -eq 0 ]; then
            status_success "ok"
            exit 0
        else
            status_failure "failed"
            cleanup
            error "Error while mounting snapshot."
        fi
    else
        status_failure "failed"
        error "Error while creating snapshot."
    fi

elif [ $1 = "remove" ]; then

    #=====================================================================
    # Remove Snapshot
    #=====================================================================

    echo -ne "Checking if mountpoint is mounted..."

    checkmount $MOUNTPOINT
    if [ $? -eq 0 ]; then
        status_success "yes"
    else
        status_failure "no"
        error "Mountpoint is not mounted. Please mount and re-run."
    fi

    echo -ne "Unmounting snapshot..."
    $UMOUNT $MOUNTPOINT

    if [ $? -eq 0 ]; then
        status_success "ok"

        cleanup

        echo -ne "Removing snapshot..."
        $LVREMOVE -f $LVMPATH/$LVMSNAPSHOT > /dev/null 2>&1

        if [ $? -eq 0 ]; then
            status_success "ok"
        else
            status_failure "failed"
            error "Error while removing snapshot, please remove manually."
        fi
    else
        status_failure "failed"
        error "Error while unmounting snapshot."
    fi

else
    echo "Unknown command: $1"
    echo
    usage_info
fi
exit