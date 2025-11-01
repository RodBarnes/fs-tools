#!/usr/bin/env bash

set -euo pipefail

source /usr/local/lib/colors

# List of filesystems supported by fsarchiver
supported_fstypes="ext2|ext3|ext4|xfs|btrfs|ntfs|vfat|fat16|fat32|reiserfs"

function printx {
  printf "${YELLOW}$1${NOCOLOR}\n"
}

# Check for --include-active flag
include_active=false
if [[ $# -gt 0 && "$1" == "--include-active" ]]; then
  include_active=true
  shift
fi

source_disk=${1:-}
backup_dir=${2:-}
if [[ -z "$source_disk" || -z "$backup_dir" ]]; then
  echo "Create a backup of selected partitions using fsarchiver."
  echo "Syntax: $0 [--include-active] <source_disk> <backup_dir>"
  echo "Where:  [--include-active] is an option to force inclusion of partitions that are active; i.e., online."
  echo "        <source_disk> is the disk containing the partitions to be included in the backup."
  echo "        <backup_dir> is the full-path to where the backup should be stored."
  exit
fi

if [[ ! -b "$source_disk" ]]; then
  printx "Error: $source_disk not a block device."
  exit 2
fi

# Backup partition table function
backup_pt() {
  local disk=$1 imgdir=$2
  if fdisk -l "$disk" 2>/dev/null | grep -q '^Disklabel type: gpt'; then
    sgdisk --backup="$imgdir/disk-pt.gpt" "$disk"
    echo "gpt" > "$imgdir/pt-type"
  else
    sfdisk --dump "$disk" > "$imgdir/disk-pt.sf"
    echo "dos" > "$imgdir/pt-type"
  fi
  echo "Saved partition table to $imgdir/"
}

# Get the active root partition
root_part=$(findmnt -n -o SOURCE /)

# Get partitions, excluding unsupported filesystems and optionally the active partition
partitions=()
while IFS= read -r part; do
  fstype=$(lsblk -fno fstype "$part" | head -n1)
  if [[ -n "$fstype" && $fstype =~ ^($supported_fstypes)$ ]]; then
    if [[ "$part" == "$root_part" && "$include_active" == "false" ]]; then
      printf "Note: Skipping $part (active root partition; use --include-active to back up)"
    else
      partitions+=("$part")
    fi
  else
    printf "Note: Skipping $part (filesystem '$fstype' not supported by fsarchiver)"
  fi
done < <(sfdisk --list "$source_disk" | awk '/^\/dev\// && $1 ~ /'"${source_disk##*/}"'[0-9]/ {print $1}' | sort)

if [[ ${#partitions[@]} -eq 0 ]]; then
  printx "No supported filesystems found on $source_disk"
  exit 2
fi

# Prepare whiptail checklist items: "index" "partition" "state"
menu_items=()
for i in "${!partitions[@]}"; do
  menu_items+=("$((i+1))" "${partitions[i]}" "ON")
done

# Interactive selection with forced TERM
export TERM=xterm
selection=$(whiptail --title "Select Partitions to Backup" --checklist "Choose one or more:" 15 60 ${#partitions[@]} \
  "${menu_items[@]}" 3>&1 1>&2 2>&3)
if [[ $? -ne 0 ]]; then
  printx "Cancelled: No backup directory created"
  exit
fi

# Convert selected tags (indices) to partition names
IFS=' ' read -ra selected_tags <<< "$selection"
selected=()
for tag in "${selected_tags[@]}"; do
  # Remove quotes from tag
  tag_clean=${tag//\"/}
  if [[ $tag_clean =~ ^[0-9]+$ ]]; then
    index=$((tag_clean-1))
    if [[ $index -ge 0 && $index -lt ${#partitions[@]} ]]; then
      selected+=("${partitions[index]}")
    else
      printx "Warning: Invalid tag '$tag_clean' ignored"
    fi
  else
    printx "Warning: Non-numeric tag '$tag_clean' ignored"
  fi
done

if [[ ${#selected[@]} -eq 0 ]]; then
  printx "Error: No valid partitions selected"
  exit
fi

# Create backup directory and save partition table only after selection
imgdir="$backup_dir/$(date +%Y%m%d_%H%M%S)_$(hostname -s)"
mkdir -p "$imgdir"
backup_pt "$source_disk" "$imgdir"

echo "Backing up selected partitions to $imgdir/ ..."

for part in "${selected[@]}"; do
  # Detect if mounted RW
  mounted_rw=false
  mount_point=$(awk -v part="$part" '$1 == part {print $2}' /proc/mounts)
  if [[ -n "$mount_point" ]]; then
    if awk -v part="$part" '$1 == part {print $4}' /proc/mounts | grep -q '^rw'; then
      mounted_rw=true
      printx "Warning: $part is mounted RW at $mount_point (live backup may have minor inconsistencies)"
      printx "Consider remounting read-only with: mount -o remount,ro $mount_point"
    else
      echo "Note: $part is mounted read-only at $mount_point"
    fi
  fi

  suffix=${part##$source_disk}
  fsa_file="$imgdir/${source_disk##*/}$suffix.fsa"

  options="-v -j$(nproc) -Z3"
  if $mounted_rw; then
    options="$options -A"
  fi

  echo "Backing up $part -> $fsa_file"
  if ! fsarchiver savefs $options "$fsa_file" "$part"; then
    printx "Error: Failed to back up $part"
    continue
  fi
done

echo "✅ Backup complete: $imgdir"
ls -lh "$imgdir"