#!/bin/bash
#
# LVM Snapshot & Mount Script
# Version 0.1.3
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
    # (useful to distinguish automatic backups from others)
    IDENTIFIER=lvmsnapshot

    # Paths to needed commands
    WHICH="`which which`"
    LVDISPLAY="`${WHICH} lvdisplay`"
    LVCREATE="`${WHICH} lvcreate`"
    LVREMOVE="`${WHICH} lvremove`"
    MOUNT="`${WHICH} mount`"
    UMOUNT="`${WHICH} umount`"
    GREP="`${WHICH} grep`"
    WC="`${WHICH} wc`"

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
ME_VERSION="0.1.2"

#=====================================================================
# Set up shell
#=====================================================================

if tty -s; then
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

function error {
    echo -e "${COL_FAILURE}$@${COL_NORMAL}" 2>&1
    exit 1
}

function checkmount {
    LINES=`$MOUNT | $GREP $@ | $WC -l`
    if [ $LINES -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

function checkvolume {
    echo "Checking availability of Volume '$@'..."
    echo -ne "  "

    $LVDISPLAY $@ > /dev/null
    rc=$?
    if [ $rc -ne 0 ]; then
        echo "...not available"
        error "Volume '$LVMVOLUME' does not exist."
    fi

    echo "...successful"
    echo
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
    echo "Please specify a LVM Volume name."
    echo
    usage_info
    exit 1
fi

LVMVOLUME=$LVMPATH/${2}${LVMEXTENSION}
LVMSNAPSHOT=${2}${LVMEXTENSION}-snapshot-$IDENTIFIER
SNAPSHOTMOUNT=$MOUNTPATH/$2

#=====================================================================
# Program logic
#=====================================================================

if [ $1 = "create" ]; then

    #=====================================================================
    # Create Snapshot
    #=====================================================================

    echo -ne "Checking if $LVMVOLUME is mounted..."

    checkmount $SNAPSHOTMOUNT
    rc=$?

    if [ $rc -eq 1 ]; then
        echo "Yes...Aborting"
        error "Volume is mounted. Please unmount and re-run."
    else
        echo "No"
    fi

    checkvolume $LVMVOLUME

    echo "Creating LVM snapshot at $LVMPATH/$LVMSNAPSHOT..."
    $LVCREATE -L $SNAPSHOTSIZE -s -n $LVMSNAPSHOT $LVMVOLUME
    rc=$?

    if [ $rc -eq 0 ]; then
        echo "...successful"
        echo
        echo "Mounting LVM snapshot for backup..."

        if [ -d $SNAPSHOTMOUNT ]; then
            echo "  Mount directory exists, ommiting mkdir..."
            else
            echo -ne "  Creating mount directory at $SNAPSHOTMOUNT..."

            mkdir -p $SNAPSHOTMOUNT

            if [ $rc -eq 0 ]; then
                echo "OK"
                else
                echo "Error"
                error "Error on creating mount directory"
            fi
        fi

        $MOUNT $LVMPATH/$LVMSNAPSHOT $SNAPSHOTMOUNT
        rc=$?

        if [ $rc -ne 0 ]; then
            $LVREMOVE -f $LVMPATH/$LVMSNAPSHOT
            error "Error on mounting LVM snapshot"
        fi

        echo "...successful"
    else
        error "Error on creating LVM snapshot"
    fi

elif [ $1 = "remove" ]; then

    #=====================================================================
    # Remove Snapshot
    #=====================================================================

    echo -ne "Checking if $LVMPATH/$LVMSNAPSHOT is mounted..."

    checkmount $SNAPSHOTMOUNT
    rc=$?

    if [ $rc -eq 1 ]; then
        echo "Yes"
        else
        echo "No...Aborting"
        error "Volume is not mounted. Please mount and re-run."
    fi

    checkvolume $LVMVOLUME

    echo "Unmounting LVM snapshot after backup..."
    $UMOUNT $SNAPSHOTMOUNT
    rc=$?

    if [ $rc -ne 0 ]; then
        echo "Error on unmounting LVM snapshot"
        echo "Please unmount and remove LVM snapshot manually!"
        exit 1
    else
        echo -ne "  Deleting mount directory at $SNAPSHOTMOUNT..."
        rm -rf $SNAPSHOTMOUNT
        rc=$?

        if [ $rc -eq 0 ]; then
            echo "OK"
        else
            echo "Error"
            exit
        fi
    fi

    echo "...successful"
    echo

    echo "Deleting LVM snapshot $LVMSNAPSHOT"
    $LVREMOVE -f $LVMPATH/$LVMSNAPSHOT
    rc=$?

    if [ $rc -ne 0 ]; then
        echo "Error on deleting LVM snapshot"
        echo "Please delete LVM snapshot manually"
        exit
    fi

    echo "...successful"

else

    echo "Unknown command: $1"
    echo
    usage_info
fi
exit