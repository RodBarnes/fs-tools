# fs-tools
A collection of `bash` scripts to create partition-level backups using fsarchiver.  These are written for bash on debian-based distros.  They may work as is or should be easily modified to work on other distros.

They require `fsarchiver` and `gdisk` be installed as well as expecting the `display` and `device` libraries (found in the [tools](https://github.com/RodBarnes/tools) repository) be in `/usr/local/lib`.

To install these tools on a remote server, run `bash ./fs-deploy.sh <hostname>`.  It will copy the files to the server and install them in `/usr/local/sbin` and `/usr/local/lib`.

To install on the local (development) system, run `bash ./fs-install.sh --local`.

## fs-backup.sh
Usage: `sudo fs-backup <backup_device> <source_disk> [-a|--include-active] [-c|--comment "comment"] [-v|--verbose] [-V|--version]`

Creates a full archive of that includes the selected partitions.

## fs-delete.sh
Usage: `sudo fs-delete <backup_device> [-V|--version]`

Lists the archives (created by `fs-backup`) found on the designated device and allows selecting one for deletion.

## fs-list.sh
Usage: `sudo fs-list <backup_device> [-V|--version]`

Lists the archives (created by `fs-backup`) found on the designated device.

## fs-restore.sh
Usage: `sudo fs-restore <backup_device> <target_disk> [-a|--archive archivename] [-v|--verbose] [-V|--version]`

Restores an archive (created by `fs-backup`) and allows selecting the specific partitions to restore.  **This must be run from a server's recovery partition or live media.**

## fs-shared.sh
Shared functions and variables for `fs-tools` expected to be in `/usr/local/lib`.