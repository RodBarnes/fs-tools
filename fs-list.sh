#!/usr/bin/env bash

# List the fs-backups

source /usr/local/lib/fs-shared.sh

show_syntax() {
  echo "List backups created by fs-backup"
  echo "Syntax: $0 <backup_device>"
  echo "Where:  <backup_device> can be a device designator (e.g., /dev/sdb6), a UUID, filesystem LABEL, or partition UUID"
  exit
}

list_archives() {
  local device=$1
  local path=$2

  local comment
  local hostname
  local name
  local i=0
  local entries=()
  local infopath
  local hostnamedir

  # Collect all entries as "hostname|archivename|comment" for sorting by hostname then name
  while IFS= read -r hostnamedir; do
    while IFS= read -r name; do
      infopath="$hostnamedir/$name/$g_infofile"
      if [ -f "$infopath" ]; then
        hostname=$(jq -r '.hostname' "$infopath")
        comment=$(jq -r '.comment' "$infopath")
      else
        hostname="unknown"
        comment="<no desc>"
      fi
      entries+=("$hostname|$name|$comment")
    done < <( find "$hostnamedir" -mindepth 1 -maxdepth 1 -type d | xargs -I{} basename {} | sort )
  done < <( find "$path" -mindepth 1 -maxdepth 1 -type d | sort )

  if [ ${#entries[@]} -eq 0 ]; then
    showx "There are no backups on $device"
    return
  fi

  show_device_space "$device"

  show "Backup files:"

  # Sort by hostname then archive name and display
  while IFS='|' read -r hostname name comment; do
    show "$hostname  $name: $comment"
    ((i++))
  done < <( printf '%s\n' "${entries[@]}" | sort )
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
