#!/bin/bash
#
# LVM Snapshot & Mount Script
# Version 0.1.2
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
# 0.1.3         Fix wrong debug output in remove action
# 0.1.2         Add config options for needed commands
# 0.1.1         Bugfix for "lvdisplay not found"
# 0.1           Initial release
#
#=====================================================================
# Set the following variables to your system needs
#=====================================================================

# LVM base path (Volume Group)
LVMPATH=/dev/lvmstore

# LVM extension
# An extension which all LVM Volumes share, will be appended to the Volume name
LVMEXTENSION="-disk"

# Mount path
# Path where snapshots will be mounted to
MOUNTPATH=/mnt/lvm

# Snapshot size
SNAPSHOTSIZE=5G

# Identifier
# An identifier which will be appended every snapshot
# (useful to distinguish automatic backups from others)
IDENTIFIER=lvmsnapshot

# Paths to needed commands
CMD_LVDISPLAY=/sbin/lvdisplay
CMD_LVCREATE=/sbin/lvcreate
CMD_LVREMOVE=/sbin/lvremove
CMD_MOUNT=/bin/mount
CMD_UMOUNT=/bin/umount
CMD_GREP=/bin/grep
CMD_WC=/usr/bin/wc

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
# Common functions
#=====================================================================

function error {
  echo -e "\n--- Fatal error: $@ ---"
  exit -1
}

function checkmount {
  LINES=`$CMD_MOUNT | $CMD_GREP $@ | $CMD_WC -l`
  if [ $LINES -gt 0 ]; then
    return 1
  else
    return 0
  fi
}

function checkvolume {
  echo "Checking availability of Volume '$@'..."
  echo -ne "  "

  $CMD_LVDISPLAY $@ > /dev/null
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
  
DESCRIPTION: 
  Automated creation and removal of LVM snapshots.
  
  LVM VG:         ${LVMPATH}
  MOUNT PATH:     ${MOUNTPATH}
      
USAGE:
    $ME <command> <lvmvolume>
             
COMMANDS:
  create:     create a LVM snapshot and mount to MOUNT PATH
  remove:     remove a LVM snapshot
USAGE
}

function version_info {
  cat <<END
  $ME version $ME_VERSION

END
}

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
  $CMD_LVCREATE -L $SNAPSHOTSIZE -s -n $LVMSNAPSHOT $LVMVOLUME
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
    
    $CMD_MOUNT $LVMPATH/$LVMSNAPSHOT $SNAPSHOTMOUNT
    rc=$?
    if [ $rc -ne 0 ]; then
      $CMD_LVREMOVE -f $LVMPATH/$LVMSNAPSHOT
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
  $CMD_UMOUNT $SNAPSHOTMOUNT
  rc=$?
  if [ $rc -ne 0 ]; then
    echo "Error on unmounting LVM snapshot"
    echo "Please unmount and remove LVM snapshot manually!"
    exit
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
  $CMD_LVREMOVE -f $LVMPATH/$LVMSNAPSHOT
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
