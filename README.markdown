lvmsnapshot.sh
==============

A shellscript to automatically create and mount LVM snapshots. See this
[post](http://maff.ailoo.net/2009/07/backup-virtual-machines-lvm-snapshots-ftplicity-duplicity/) for
details.

Usage
-----

    ~# lvmsnapshot -h
    lvmsnapshot version 0.3

    LVM VG:     /dev/vmstore
    MOUNT PATH: /mnt/lvmsnapshot/vmstore

    DESCRIPTION:
      Automated creation and removal of LVM snapshots.

    USAGE:
      lvmsnapshot <options> <command> <volumename>

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
      lvmsnapshot -c /etc/lvmsnapshot.conf create vm01
      lvmsnapshot -m block -i 1 -g vmstore create vm01
      lvmsnapshot remove vm01

The script has changed a little since the blog post and now additionally supports block devices in KMV/qemu style. Basic usage is still the following:

    lvmsnapshot create vm01
    lvmsnapshot remove vm01

Configuration
-------------

You'll have to define some config values to match your environment first. The easiest way to do so is to create a config file in <code>/etc/lvmsnapshot/lvmsnapshot.conf</code> and setting the needed values for your environment there. For a list of available config values just see the default values section in the upper part of the script. Additionally you can set part of the config values with command line options or with a custom config file (see the <code>-c</code> option).