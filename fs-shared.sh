#!/usr/bin/env bash

# Shared code and variables for fs-tools

source /usr/local/lib/display.sh
source /usr/local/lib/device.sh

VERSION="20260416"

g_infofile=info.json
g_backuppath=/mnt/backup
g_backupdir="fs"
g_archives=()

verify_sudo() {
  if [[ "$EUID" != 0 ]]; then
    showx "This must be run as sudo.\n"
    exit 1
  fi
}

get_device() {
  echo "/dev/$(lsblk -ln -o NAME,UUID,PARTUUID,LABEL | grep "${1#/dev/}" | tr -s ' ' | cut -d ' ' -f1)"
}

show_device_space() {
  local device=$1
  df -h --output=source,size,used,avail,pcent "$device" | tail -1 | \
    awk '{printf "Device %s: %s total, %s used, %s available (%s)\n", $1, $2, $3, $4, $5}'
}

collect_archives() {
  local path=$1

  local systemname
  local archive
  local infopath
  local comment
  local hostnamedir

  g_archives=()

  while IFS= read -r hostnamedir; do
    systemname="${hostnamedir##*/}"
    while IFS= read -r archive; do
      infopath="$hostnamedir/$archive/$g_infofile"
      if [ -f "$infopath" ]; then
        comment=$(jq -r '.comment' "$infopath")
      else
        comment="<no desc>"
      fi
      g_archives+=("$systemname|$archive|$comment")
    done < <( find "$hostnamedir" -mindepth 1 -maxdepth 1 -type d | xargs -I{} basename {} | sort )
  done < <( find "$path" -mindepth 1 -maxdepth 1 -type d | sort )
}

select_archive() {
  local device=$1
  local path=$2

  local sorted_archives=()
  local labels=()
  local entry
  local systemname
  local archive
  local comment
  local count
  local selection
  local idx
  local name

  collect_archives "$path"

  if [ ${#g_archives[@]} -eq 0 ]; then
    showx "There are no backups on $device"
    return
  fi

  # Sort by system name then archive name
  while IFS= read -r entry; do
    sorted_archives+=("$entry")
  done < <( printf '%s\n' "${g_archives[@]}" | sort )

  # Build display labels
  for entry in "${sorted_archives[@]}"; do
    IFS='|' read -r systemname archive comment <<< "$entry"
    labels+=("$systemname  $archive: $comment")
  done

  show "Archive files..."

  count="${#labels[@]}"
  ((count++))

  COLUMNS=1
  select selection in "${labels[@]}" "Cancel"; do
    if [[ "$REPLY" =~ ^[0-9]+$ && "$REPLY" -ge 1 && "$REPLY" -le $count ]]; then
      if [[ "$selection" == "Cancel" ]]; then
        echo "Operation cancelled." >&2
        break
      else
        idx=$(( REPLY - 1 ))
        IFS='|' read -r systemname archive comment <<< "${sorted_archives[$idx]}"
        name="$systemname/$archive"
        break
      fi
    else
      showx "Invalid selection. Please enter a number between 1 and $count."
    fi
  done

  # name is "system_name/archivename"
  echo "$name"
}
