#!/usr/bin/env bash

set -eo pipefail

source fs_functions.sh

backuppath=/mnt/backup
descfile=comment.txt

show_syntax() {
  echo "List backups created by fs_backup"
  echo "Syntax: $0 <backup_device>"
  echo "Where:  <backup_device> is the device containing the backup files."
  exit
}

list_archives() {
  local device=$1 path=$2

  # Get the archives
  local archives=() note name
  local i=0
  while IFS= read -r name; do
    if [ $i -eq 0 ]; then
      echo "Backup files on $device" >&2
    fi
    if [ -f "$path/$name/$descfile" ]; then
      note=$(cat "$path/$name/$descfile")
    else
      note="<no desc>"
    fi
    echo "$name: $note" >&2
    ((i++))
  done < <( ls -1 "$path" )

  if [ $i -eq 0 ]; then
    printx "There are no backups on $device" >&2
  fi
}

# --------------------
# ------- MAIN -------
# --------------------

trap 'unmount_device_at_path "$backuppath"' EXIT

# Get the arguments
if [ $# -ge 1 ]; then
  backupdevice=${1:-}
  shift 1
else
  show_syntax >&2
  exit 1
fi

# echo "backupdevice=$backupdevice"
# echo "backuppath=$backuppath"

if [[ -z "$backupdevice" ]]; then
  show_syntax
fi

if [[ ! -b "$backupdevice" ]]; then
  printx "Error: The specified backup device '$backupdevice' is not a block device."
  exit 2
fi

mount_device_at_path "$backupdevice" "$backuppath"
list_archives "$backupdevice" "$backuppath/$backupdir"

