#!/usr/bin/env bash

# Shared code and variables for fs-tools

source /usr/local/lib/display.sh
source /usr/local/lib/device.sh

FS_SHARED_VERSION="20260404"

g_infofile=info.json
g_backuppath=/mnt/backup
g_backupdir="fs"

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

select_archive() {
  local device=$1
  local path=$2

  local archives=()
  local comment
  local hostname
  local name
  local count
  local hostnamedir
  local archive
  local infopath
  local sorted_archives=()
  local entry
  local labels=()
  local selection
  local idx

  # Enumerate all hostname subdirectories, then archives within each
  while IFS= read -r hostnamedir; do
    while IFS= read -r archive; do
      infopath="$hostnamedir/$archive/$g_infofile"
      if [ -f "$infopath" ]; then
        hostname=$(jq -r '.hostname' "$infopath")
        comment=$(jq -r '.comment' "$infopath")
      else
        hostname="unknown"
        comment="<no desc>"
      fi
      archives+=("${hostnamedir##*/}/$archive|$hostname  $archive: $comment")
    done < <( find "$hostnamedir" -mindepth 1 -maxdepth 1 -type d | xargs -I{} basename {} | sort )
  done < <( find "$path" -mindepth 1 -maxdepth 1 -type d | sort )

  if [ ${#archives[@]} -eq 0 ]; then
    showx "There are no backups on $device"
    return
  fi

  # Sort entries by the display portion (hostname first, then timestamp) and rebuild array
  while IFS= read -r entry; do
    sorted_archives+=("$entry")
  done < <( printf '%s\n' "${archives[@]}" | sort -t'|' -k2 )

  # Build display-only labels for select
  for entry in "${sorted_archives[@]}"; do
    labels+=("${entry##*|}")
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
        # Map selected label back to its hostname/archive path token
        idx=$(( REPLY - 1 ))
        name="${sorted_archives[$idx]%%|*}"
        break
      fi
    else
      showx "Invalid selection. Please enter a number between 1 and $count."
    fi
  done

  # name is "hostname/archivename"
  echo "$name"
}
