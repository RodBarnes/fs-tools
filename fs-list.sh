#!/usr/bin/env bash

# List the fs-backkups

source /usr/local/lib/fs-shared.sh

show_syntax() {
  echo "List backups created by fs-backup"
  echo "Syntax: $0 <backup_device>"
  echo "Where:  <backup_device> can be a device designator (e.g., /dev/sdb6), a UUID, filesystem LABEL, or partition UUID"
  exit
}

list_archives() {
  local device=$1 path=$2

  # Get the archives
  local archives=() note name
  local i=0

  if [[ ! -d $path ]]; then
    showx "There are no backups on $device" >&2
  else
    while IFS= read -r name; do
      if [[ $i -eq 0 ]]; then
        echo "Backup files on $device" >&2
      fi
      if [[ -f $path/$name/$g_descfile ]]; then
        note=$(cat "$path/$name/$g_descfile")
      else
        note="<no desc>"
      fi
      echo "$name: $note" >&2
      ((i++))
    done < <( ls -1 "$path" | sort )

    if [[ $i -eq 0 ]]; then
      showx "There are no backups on $device" >&2
    fi
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
list_archives "$backupdevice" "$g_backuppath/$g_backupdir"

