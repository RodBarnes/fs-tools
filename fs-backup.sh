#!/usr/bin/env bash

# Create a backup of one or more partitions from a drive using fsarchiver

source /usr/local/lib/fs-shared.sh
LIB_VERSION="$VERSION"

VERSION="20260505"

show_syntax() {
  echo "Create a backup of selected partitions using fsarchiver."
  echo "Syntax: $0 <backup_device> <source_disk> [system_name] [-a|--include-active] [-c|--comment \"comment\"]"
  echo "Where:  <backup_device> can be a backupdevice designator (e.g., /dev/sdb6), a UUID, filesystem LABEL, or partition UUID"
  echo "        <source_disk> is the disk containing the partitions to be included in the backup."
  echo "        [system_name] is the name to use for the backup subdirectory; prompted if not supplied."
  echo "        [-a|--include-active] is an option to force inclusion of partitions that are active; i.e., online."
  echo "        [-c|--comment \"comment\"] is a quote-bounded comment for the archive."
  echo "        [-v|--verbose] will display the output log in process."
  echo "        [-V|--version] will display the version."
  exit
}

backup_partition_table() {
  local disk=$1
  local path=$2

  # Get the partition info
  if fdisk -l "$disk" 2>/dev/null | grep -q '^Disklabel type: gpt'; then
    sgdisk --backup="$path/disk-pt.gpt" "$disk"
    echo "gpt" > "$path/pt-type"
  else
    sfdisk --dump "$disk" > "$path/disk-pt.sf"
    echo "dos" > "$path/pt-type"
  fi
}

backup_filesystem() {
  local partfs=$1
  local path=$2
  local disk=$3

  local mount_point
  local partition_device="/dev/$partfs"
  local mounted_rw=false
  local suffix=${partfs##$disk}
  local fsa_file="$path/$suffix.fsa"
  local options="-v -j$(nproc) -Z3"

  # Detect if mounted RW
  mount_point=$(awk -v part="$partition_device" '$1 == part {print $2}' /proc/mounts)
  if [[ -n "$mount_point" ]]; then
    if awk -v part="$partition_device" '$1 == part {print $4}' /proc/mounts | grep -q '^rw'; then
      mounted_rw=true
      showx "Warning: $partition_device is mounted RW at $mount_point (live backup may have minor inconsistencies)"
    else
      show "Note: $partition_device is mounted read-only at $mount_point"
    fi
  fi

  if $mounted_rw; then
    options="$options -A"
  fi

  show "Backing up $partition_device to archive..."
  fsarchiver savefs $options "$fsa_file" "$partition_device" &>> "$g_logfile"
  if [ $? -ne 0 ]; then
    showx "\nError: Failed to back up $partition_device"
  fi
}

select_backup_partitions() {
  local disk=$1
  local root=$2
  local active=$3

  local supported_fstypes="ext2|ext3|ext4|xfs|btrfs|ntfs|vfat|fat16|fat32|reiserfs"
  local partitions=()
  local fstype
  local partition
  local selected=()
  local yn

  while IFS= read -r partition; do
    fstype=$(lsblk -fno fstype "$partition" | head -n1)
    if [[ -n "$fstype" && $fstype =~ ^($supported_fstypes)$ ]]; then
      if [[ -z $active && "$partition" == "$root" ]]; then
        show "Note: Skipping $partition (active root partition; use --include-active to back up)"
      else
        partitions+=("${partition#/dev/}")
      fi
    fi
  done < <(lsblk -lno NAME,TYPE "$disk" | awk '$2 == "part" {print "/dev/" $1}' | sort)

  if [[ ${#partitions[@]} -eq 0 ]]; then
    showx "No supported filesystems found on $disk"
    exit 2
  fi

  for i in "${!partitions[@]}"; do
    read -p "Backup partition ${partitions[i]}? (y/N)" yn
    if [[ $yn == "y" || $yn == "Y" ]]; then
      selected+=("${partitions[i]}")
    fi
  done

  for i in "${!selected[@]}"; do
    echo "${selected[i]}"
  done
}

verify_available_space() {
  local device=$1
  local path=$2
  local minspace=$3

  local line
  local dev
  local size
  local used
  local avail
  local pcent
  local mount
  local space
  local yn

  line=$(df "$path" -BG | sed -n '2p;')
  IFS=' ' read dev size used avail pcent mount <<< $line
  space=${avail%G}
  if [[ $space -lt $minspace ]]; then
    showx "The backup device '$device' has only $avail space left of the total $size."
    read -p "Do you want to proceed? (y/N) " yn
    if [[ $yn != "y" && $yn != "Y" ]]; then
      show "Operation cancelled."
      exit
    else
      echo "User acknowledged that backup device has less than ${minspace}GB space but proceeded." &>> "$g_logfile"
    fi
  else
    echo "Backup device has $avail available; proceeding with backup." &>> "$g_logfile"
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
arg_short=avc:V
arg_long=include-active,verbose,comment:,version
arg_opts=$(getopt --options "$arg_short" --long "$arg_long" --name "$0" -- "$@")
if [ $? != 0 ]; then
  show_syntax
  exit 1
fi

eval set -- "$arg_opts"
while true; do
  case "$1" in
    -V|--version)
      echo "$(basename $0) v$VERSION, fs-shared.sh v$LIB_VERSION"
      exit 0
      ;;
    -a|--include-active)
      include_active=true
      shift
      ;;
    -c|--comment)
      comment="$2"
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
  sourcedisk="$2"
  systemname="$3"
else
  show_syntax
fi

verify_sudo

if [[ ! -b $backupdevice ]]; then
  printx "No valid backup device was found for '$backupdevice'."
  exit
fi

if [[ ! -b $sourcedisk ]]; then
  printx "No valid source device was found for '$sourcedisk'."
  exit
fi

if [[ -z "$systemname" ]]; then
  default_hostname=$(hostname -s)
  read -rp "System name [${default_hostname}]: " systemname
  if [[ -z "$systemname" ]]; then
    systemname="$default_hostname"
  fi
fi
sourcehostname="$systemname"

archivename="$(date +%Y%m%d_%H%M%S)"

# Initialize the log file
g_logfile="/tmp/$(basename $0)_$archivename.log"
echo -n &> "$g_logfile"

# Start tailing if requested
if [[ -n "$verbose" ]]; then
  tail -f "$g_logfile" &
  tail_pid=$!
fi

minimum_space=10 # Minimum required space in GB

mount_device_at_path "$backupdevice" "$g_backuppath"

verify_available_space "$backupdevice" "$g_backuppath" "$minimum_space"

# Get the active root partition
root_part=$(findmnt -n -o SOURCE /)

# Select the partitions to backup
readarray -t selected < <(select_backup_partitions "$sourcedisk" "$root_part" "$include_active")

if [[ ${#selected[@]} -eq 0 ]]; then
  printx "Error: No valid partitions selected"
  exit
fi

# Create backup directory: fs/<system_name>/<archivename>
archivepath="$g_backuppath/$g_backupdir/$sourcehostname/$archivename"
mkdir -p "$archivepath"

echo "Saving partition table to $archivepath/..."
backup_partition_table "$sourcedisk" "$archivepath"

echo "Backing up selected partitions to $archivepath/ ..."
for partition in "${selected[@]}"; do
  backup_filesystem "$partition" "$archivepath" "$sourcedisk"
done

# Write info.json
if [[ -z $comment ]]; then
  comment="<no desc>"
fi
source_uuid=$(blkid -s UUID -o value "$sourcedisk")
machine_id=$(cat /etc/machine-id)
json=$(jq -nc --arg comment "$comment" --arg device "$sourcedisk" --arg uuid "$source_uuid" --arg machine_id "$machine_id" '{comment: $comment, device: $device, uuid: $uuid, machine_id: $machine_id}')
echo "$json" > "$archivepath/$g_infofile"

echo "✅ Backup complete: $archivepath"
echo "Details of the operation can be viewed in the file $g_logfile"
