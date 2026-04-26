#!/usr/bin/env bash

# Shared code and variables for fs-tools

source /usr/local/lib/display.sh
source /usr/local/lib/device.sh

VERSION="20260425"

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

# Print a single formatted archive line to stderr.
# With prefix="": fs-list style   — name  archivename  description
# With prefix="N) ": fs-restore/delete style — N)  name  archivename  description
# Column widths: name=8, archivename=15 (YYYYMMDD_HHMMSS), description fills to COLUMNS.
format_archive_line() {
  local key=$1
  local comment=$2
  local prefix=$3

  local sysname
  local archive
  local desc_width
  local truncated

  sysname="${key%/*}"
  archive="${key##*/}"

  if [ -n "$prefix" ]; then
    # 4 (num field) + 8 (name) + 2 (gap) + 15 (archive) + 2 (gap) = 31
    desc_width=$(( COLUMNS - 31 ))
  else
    # 8 (name) + 2 (gap) + 15 (archive) + 2 (gap) = 27
    desc_width=$(( COLUMNS - 27 ))
  fi

  if [ "$desc_width" -lt 10 ]; then
    desc_width=10
  fi

  if [ "${#comment}" -gt "$desc_width" ]; then
    truncated="${comment:0:$(( desc_width - 3 ))}..."
  else
    truncated="$comment"
  fi

  printf "%s${WHITE}%-8s${NOCOLOR}  ${LTCYAN}%s${NOCOLOR}  ${YELLOW}%s${NOCOLOR}\n" \
    "$prefix" "$sysname" "$archive" "$truncated" >&2
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
      g_archives+=("$systemname/$archive|$comment")
    done < <( find "$hostnamedir" -mindepth 1 -maxdepth 1 -type d | xargs -I{} basename {} | sort )
  done < <( find "$path" -mindepth 1 -maxdepth 1 -type d | sort )
}

select_archive() {
  local device=$1
  local path=$2

  local entry
  local key
  local comment
  local count
  local cancel
  local idx
  local reply
  local name
  local sorted=()

  collect_archives "$path"

  if [ ${#g_archives[@]} -eq 0 ]; then
    showx "There are no backups on $device"
    return
  fi

  # Sort g_archives by key (systemname/archive)
  while IFS= read -r entry; do
    sorted+=("$entry")
  done < <( printf '%s\n' "${g_archives[@]}" | sort -k1 )
  g_archives=("${sorted[@]}")

  show ""

  count="${#g_archives[@]}"
  cancel=$(( count + 1 ))

  idx=0
  for entry in "${g_archives[@]}"; do
    key="${entry%%|*}"
    comment="${entry##*|}"
    idx=$(( idx + 1 ))
    format_archive_line "$key" "$comment" "$(printf '%2d)  ' $idx)"
  done

  printf "%2d)  Cancel\n" "$cancel" >&2
  show ""

  while true; do
    printf "${YELLOW}Select [1-$cancel]:${NOCOLOR} " >&2
    read -r reply
    if [[ "$reply" =~ ^[0-9]+$ && "$reply" -ge 1 && "$reply" -le "$cancel" ]]; then
      if [ "$reply" -eq "$cancel" ]; then
        show "Operation cancelled."
        name=""
        break
      else
        name="${g_archives[$(( reply - 1 ))]%%|*}"
        break
      fi
    else
      showx "Invalid selection. Please enter a number between 1 and $cancel."
    fi
  done

  # name is "systemname/archivename"
  echo "$name"
}
