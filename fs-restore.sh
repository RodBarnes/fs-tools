#!/usr/bin/env bash

# Restore an fs-backup

source /usr/local/lib/fs-shared.sh

VERSION="20260411"

show_syntax() {
  echo "Restore a backup created by fs-backup"
  echo "Syntax: $0 <backup_device> <target_disk> [-a|--archive archivename]"
  echo "Where:  <backup_device> can be a backupdevice designator (e.g., /dev/sdb6), a UUID, filesystem LABEL, or partition UUID"
  echo "        <target_disk> is the disk to which the restore should be applied."
  echo "        [-a|--archive archivename] is the name of the specific archive to restore."
  echo "        [-v|--verbose] will display the output log in process."
  echo "        [-V|--version] will display the version."
  exit
}

restore_partition_table() {
  local disk=$1
  local path=$2
  local type=$3

  if [[ "$type" == "gpt" ]]; then
    if [[ ! -f "$path/disk-pt.gpt" ]]; then
      showx "Error: $path/disk-pt.gpt not found."
      exit 1
    fi
    sgdisk --load-backup="$path/disk-pt.gpt" "$disk" &>> "$g_logfile"
  elif [[ "$type" == "dos" ]]; then
    if [[ ! -f "$path/disk-pt.sf" ]]; then
      showx "Error: $path/disk-pt.sf not found."
      exit 1
    fi
    sfdisk "$disk" < "$path/disk-pt.sf" &>> "$g_logfile"
  fi

  partprobe "$disk"
}

restore_filesystem() {
  local part=$1
  local path=$2
  local root=$3

  local device="/dev/$part"
  local filepath="$path/$part.fsa"
  local mount
  local yn

  if [[ ! -f "$filepath" ]]; then
    showx "Error: $filepath not found, skipping $device"
    return
  fi
  if [[ ! -b "$device" ]]; then
    showx "Error: $device not a block device, skipping"
    return
  fi

  mount=$(findmnt -n -o TARGET "$device")
  if [[ -n "$mount" ]]; then
    showx "Error: $device is mounted at $mount."
    readx -p "Proceed and unmount it first? [y/N] " yn
    if [[ "$yn" =~ ^[yY]$ ]]; then
      if ! umount "$mount"; then
        showx "Error: Failed to unmount $mount, skipping $device"
      fi
    else
      showx "Skipping restoration of $device"
    fi
  fi

  if [[ "$device" == "$root" ]]; then
    showx "Warning: Restoring active root partition $device may cause system instability"
  fi
  show "Restoring $filepath -> $device"
  fsarchiver restfs "$filepath" id=0,dest="$device" &>> "$g_logfile"
  if [[ $? -ne 0 ]]; then
    showx "Error: Failed to restore $device"
  fi
}

select_restore_partitions() {
  local path=$1
  local root=$2

  local fsa_files
  local partitions=()
  local filename
  local partname
  local device
  local selected=()
  local yn

  fsa_files=($(ls -1 "$path"/*.fsa 2>/dev/null))
  if [[ ${#fsa_files[@]} -eq 0 ]]; then
    showx "Error: No .fsa files found in $path"
    exit 3
  fi

  for i in "${!fsa_files[@]}"; do
    filename=${fsa_files[i]}
    partname=$(basename "$filename" .fsa)
    device="/dev/$partname"
    if [[ $device == $root ]]; then
      showx "Note: Skipping $partname because it is the currently active partition."
      showx "To restore this partition, run this program from another partition."
    else
      partitions+=("$partname")
    fi
  done

  if [[ ${#partitions[@]} -eq 0 ]]; then
    showx "Error: No valid partitions available for restore."
    exit 3
  elif [[ ${#partitions[@]} -eq 1 ]]; then
    echo "${partitions[0]}"
    return
  else
    for i in "${!partitions[@]}"; do
      read -p "Restore partition ${partitions[i]}? (y/N)" yn
      if [[ $yn == "y" || $yn == "Y" ]]; then
        selected+=("${partitions[i]}")
      fi
    done
    for i in "${!selected[@]}"; do
      echo "${selected[i]}"
    done
  fi
}

cleanup() {
  unmount_device_at_path "$g_backuppath"
  [[ -n "$tail_pid" ]] && kill "$tail_pid" 2>/dev/null
}

# --------------------
# ------- MAIN -------
# --------------------

trap 'cleanup' EXIT

# Get the arguments
arg_short=va:V
arg_long=verbose,archive:,version
arg_opts=$(getopt --options "$arg_short" --long "$arg_long" --name "$0" -- "$@")
if [ $? != 0 ]; then
  show_syntax
  exit 1
fi

eval set -- "$arg_opts"
while true; do
  case "$1" in
    -V|--version)
      echo "$(basename $0) v$VERSION, fs-shared.sh v$FS_SHARED_VERSION"
      exit 0
      ;;
    -a|--archive)
      archivename="$2"
      shift 2
      ;;
    -v|--verbose)
      verbose=true
      shift
      ;;
    --) # End of options
      shift
      break
      ;;
    *)
      echo "Internal error parsing arguments: arg=$1"
      exit 1
      ;;
  esac
done

if [ $# -ge 2 ]; then
  backupdevice=$(get_device "$1")
  restoredevice="$2"
else
  show_syntax
fi

verify_sudo

if [[ ! -b $backupdevice ]]; then
  printx "No valid backup device was found for '$backupdevice'."
  exit
fi

if [[ ! -b $restoredevice ]]; then
  printx "No valid restore device was found for '$restoredevice'."
  exit
fi

mount_device_at_path "$backupdevice" "$g_backuppath"

# If an archive name was specified, find which system_name subdir contains it
if [ -n "$archivename" ]; then
  matched_subpath=$(find "$g_backuppath/$g_backupdir" -mindepth 2 -maxdepth 2 -type d -name "$archivename" | head -1)
  if [ -z "$matched_subpath" ]; then
    printx "There is no archive '$archivename' on '$backupdevice'."
    unset archivename
  else
    archivesubpath="${matched_subpath#$g_backuppath/$g_backupdir/}"
  fi
fi

# Since an archive was not specified, present a list for selection
if [ -z "$archivename" ]; then
  # select_archive returns "system_name/archivename"
  archivesubpath=$(select_archive "$backupdevice" "$g_backuppath/$g_backupdir")
fi

if [ -n "$archivesubpath" ]; then

  archivepath="$g_backuppath/$g_backupdir/$archivesubpath"
  archivename="${archivesubpath##*/}"
  systemname="${archivesubpath%%/*}"

  # Initialize the log file
  g_logfile="/tmp/$(basename $0)_$archivename.log"
  echo -n &> "$g_logfile"

  # Start tailing if requested
  if [[ -n "$verbose" ]]; then
    tail -f "$g_logfile" &
    tail_pid=$!
  fi

  # Read metadata from info.json
  infofile="$archivepath/$g_infofile"
  if [[ ! -f "$infofile" ]]; then
    printx "Error: $infofile not found."
    exit 2
  fi

  # Sanity check: warn if backup was made on a different machine
  backup_machine_id=$(jq -r '.machine_id' "$infofile")
  current_machine_id=$(cat /etc/machine-id)
  if [ "$backup_machine_id" != "$current_machine_id" ]; then
    showx "WARNING: This backup was made on a different machine (system name: $systemname)."
    showx "Restoring it to this machine may produce an unbootable or misconfigured system."
    readx "Do you want to proceed anyway? (y/N)" yn
    if [[ $yn != "y" && $yn != "Y" ]]; then
      show "Operation cancelled."
      exit
    fi
  fi

  echo "Restoring '$systemname' $archivename to '$restoredevice'..."

  # Check for partition table backup
  if [[ ! -f "$archivepath/pt-type" ]]; then
    printx "Error: $archivepath/pt-type not found."
    exit 3
  fi

  pt_type=$(cat "$archivepath/pt-type")
  if [[ "$pt_type" != "gpt" && "$pt_type" != "dos" ]]; then
    printx "Error: Invalid partition table type in $archivepath/pt-type: $pt_type"
    exit 3
  fi

  # Get the active root partition
  root_part=$(findmnt -n -o SOURCE /)

  # Select the partitions to restore
  readarray -t selected < <(select_restore_partitions "$archivepath" "$root_part")

  if [[ "${#selected[@]}" -gt 0 ]]; then
    echo "Restoring partition table to $restoredevice ..."
    restore_partition_table "$restoredevice" "$archivepath" "$pt_type"

    for partition in "${selected[@]}"; do
      restore_filesystem "$partition" "$archivepath" "$root_part"
    done

    echo "✅ Restoration complete."
    echo "Details of the operation can be viewed in the file $g_logfile"
  else
    printx "No partitions were selected for restore."
  fi
fi
