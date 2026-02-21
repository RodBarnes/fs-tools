# fs-tools
A collection of `bash` scripts to create partition-level backups using fsarchiver.  These are sysadmin tools and should reside in `/usr/local/sbin`.

This requires `fsarchiver` and `gdisk` be installed as well as expecting the `display` and `device` libraries (found in the [tools](https://github.com/RodBarnes/tools) repository) be in `/usr/local/lib`.

These are written for bash on debian-based distros.  They may work as is or should be easily modified to work on other distros.

## fs-backup.sh
Usage: `sudo fs-backup <backup_device> <source_disk> [-a|--include-active] [-c|--comment "comment"] [-v|--verbose]`

Creates a full archive of that includes the selected partitions.

## fs-delete.sh
Usage: `sudo fs-delete <backup_device>`

Lists the archives (created by `fs-backup`) found on the designated device and allows selecting one for deletion.

## fs-list.sh
Usage: `sudo fs-list <backup_device>`

Lists the archvies (created by `fs-backup`) found on the designated device.

## fs-restore.sh
Usage: `sudo fs-restore <backup_device> <target_disk> [-a|--include-active] [-b|--backup] [-v|--verbose]`

Restores an archive (created by `fs-backup`) and allows selecting the specific partitions to restore.  Allows for backing up active (online) partitions.  **This must be run from a server's recovery partition or live media.**

## fs-shared.sh
Shared functions and variables for `fs-tools` expected to be in `/usr/local/lib`.