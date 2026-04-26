#!/usr/bin/env bash

# List the fs-backups

source /usr/local/lib/fs-shared.sh

VERSION="20260425"

show_syntax() {
  echo "List backups created by fs-backup"
  echo "Syntax: $0 <backup_device>"
  echo "Where:  <backup_device> can be a device designator (e.g., /dev/sdb6), a UUID, filesystem LABEL, or partition UUID"
  echo "        [-V|--version] will display the version."
  exit
}

list_archives() {
  local device=$1
  local path=$2

  local entry
  local key
  local comment

  collect_archives "$path"

  show_device_space "$device"

  if [ ${#g_archives[@]} -eq 0 ]; then
    showx "There are no backups on $device"
    return
  fi

  show ""

  for entry in "${g_archives[@]}"; do
    key="${entry%%|*}"
    comment="${entry##*|}"
    format_archive_line "$key" "$comment" ""
  done
}

cleanup() {
  unmount_device_at_path "$g_backuppath"
}

# --------------------
# ------- MAIN -------
# --------------------

trap 'cleanup' EXIT

# Get the arguments
if [[ "$1" == "-V" || "$1" == "--version" ]]; then
  echo "$(basename $0) v$VERSION, fs-shared.sh v$FS_SHARED_VERSION"
  exit 0
elif [ $# -ge 1 ]; then
  backupdevice=$(get_device "$1")
else
  show_syntax
fi

verify_sudo

if [[ ! -b $backupdevice ]]; then
  printx "No valid backup device was found for '$backupdevice'."
  exit
fi

mount_device_at_path "$backupdevice" "$g_backuppath"
list_archives "$backupdevice" "$g_backuppath/$g_backupdir"
