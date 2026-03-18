#!/usr/bin/env bash

# Delete one or more fs-backups

source /usr/local/lib/fs-shared.sh

show_syntax() {
  echo "Delete a backup created by fs-backup"
  echo "Syntax: $0 <backup_device>"
  echo "Where:  <backup_device> can be a device designator (e.g., /dev/sdb6), a UUID, filesystem LABEL, or partition UUID"
  exit
}

delete_archive() {
  local path=$1
  local subpath=$2

  local archive_dir="$path/$subpath"
  local name="${subpath##*/}"
  local yn

  showx "This will completely DELETE the archive '$name' and is not recoverable."
  readx "Are you sure you want to proceed? (y/N) " yn
  if [[ $yn != "y" && $yn != "Y" ]]; then
    show "Operation cancelled."
  else
    show "Deleting '$name'"
    rm -Rf "$archive_dir"
  fi
}

cleanup() {
  unmount_device_at_path "$g_backuppath"
}

# --------------------
# ------- MAIN -------
# --------------------

trap 'cleanup' EXIT

# Get the arguments
if [ $# -ge 1 ]; then
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

show_device_space "$backupdevice"

while true; do
  # select_archive returns "hostname/archivename"
  archivesubpath=$(select_archive "$backupdevice" "$g_backuppath/$g_backupdir")
  if [[ -n $archivesubpath ]]; then
    delete_archive "$g_backuppath/$g_backupdir" "$archivesubpath"
  else
    exit
  fi
done
