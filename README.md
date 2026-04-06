# fs-tools
## General
A collection of `bash` scripts to create partition-level backups using fsarchiver.  These are written for bash on debian-based distros.  They may work as is or should be easily modified to work on other distros.

### Installation
To install these tools on a remote server, run `bash ./fs-deploy.sh <hostname>`.  It will copy the files to the server and install them in `/usr/local/sbin` and `/usr/local/lib`.  It will also install the required dependencies `fsarchiver` and `gdisk` and [display.sh](https://github.com/RodBarnes/tools/blob/main/display.sh) and [device.sh](https://github.com/RodBarnes/tools/blob/main/device.sh) libraries (found in the [tools](https://github.com/RodBarnes/tools) repository).

To install on the local (development) system, run `bash ./fs-install.sh --local`.

### .git/hooks/pre-commit
A Git pre-commit hook is included that automatically updates the `VERSION` variable in any staged script file (and `TS_SHARED_VERSION` in `ts-shared.sh`) to the current date (`YYYYMMDD`) at commit time.

After a fresh clone, install it manually:
```bash
cp git_hooks_pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

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