#!/usr/bin/env bash

set -euo pipefail

source /usr/local/lib/colors

function printx {
  printf "${YELLOW}$1${NOCOLOR}\n"
}

function show_syntax {
  echo "Restore a backup created by fs_backup"
  echo "Syntax: $0 [--include-active] <target_disk> <backup_dir>"
  echo "Where:  [--include-active] is an option to direct restoring to partitions that are active; i.e., online."
  echo "        <target_disk> is the disk to whicih the restore should be applied."
  echo "        <backup_dir> is the full path to the directory containing the backup files."
  exit
}

function parse_arguments {
  # Check for --include-active flag
  include_active=false
  if [[ $# -gt 0 && "$1" == "--include-active" ]]; then
    include_active=true
    shift
  fi

  target_disk=${1:-}
  backup_dir=${2:-}
}

parse_arguments
if [[ -z "$target_disk" || -z "$backup_dir" ]]; then
  show_syntax
fi

if [[ ! -b "$target_disk" ]]; then
  printx "Error: $target_disk not a block device."
  exit 2
fi

if [[ ! -d "$backup_dir" ]]; then
  printx "Error: $backup_dir not a directory."
  exit 2
fi

# Check for partition table backup
if [[ ! -f "$backup_dir/pt-type" ]]; then
  printx "Error: $backup_dir/pt-type not found."
  exit 3
fi

pt_type=$(cat "$backup_dir/pt-type")
if [[ "$pt_type" != "gpt" && "$pt_type" != "dos" ]]; then
  printx "Error: Invalid partition table type in $backup_dir/pt-type: $pt_type"
  exit 3
fi

# Find available .fsa files
fsa_files=($(ls -1 "$backup_dir"/*.fsa 2>/dev/null))
if [[ ${#fsa_files[@]} -eq 0 ]]; then
  printx "Error: No .fsa files found in $backup_dir"
  exit 3
fi

# Get the active root partition
root_part=$(findmnt -n -o SOURCE /)

# Filter .fsa files, excluding the active partition unless --include-active is used
partitions=()
menu_items=()
for i in "${!fsa_files[@]}"; do
  fsa_file=${fsa_files[i]}
  partition=$(basename "$fsa_file" .fsa)
  partition_device="/dev/$partition"
  if [[ "$partition_device" == "$root_part" && "$include_active" == "false" ]]; then
    echo "Note: Skipping $partition (active root partition; use --include-active to restore)"
  else
    partitions+=("$partition")
    menu_items+=("$((i+1))" "$partition" "ON")
  fi
done

if [[ ${#partitions[@]} -eq 0 ]]; then
  printx "Error: No valid partitions available for restoration"
  exit 3
fi

# Interactive selection with forced TERM
export TERM=xterm
selection=$(whiptail --title "Select Partitions to Restore" --checklist "Choose one or more:" 15 60 ${#partitions[@]} \
  "${menu_items[@]}" 3>&1 1>&2 2>&3)
if [[ $? -ne 0 ]]; then
  echo "Cancelled: No restoration performed"
  exit
fi

# Convert selected tags (indices) to partition names
IFS=' ' read -ra selected_tags <<< "$selection"
selected=()
for tag in "${selected_tags[@]}"; do
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

# Restore partition table
echo "Restoring partition table to $target_disk ..."
if [[ "$pt_type" == "gpt" ]]; then
  if [[ ! -f "$backup_dir/disk-pt.gpt" ]]; then
    printx "Error: $backup_dir/disk-pt.gpt not found."
    exit 1
  fi
  sgdisk --load-backup="$backup_dir/disk-pt.gpt" "$target_disk"
elif [[ "$pt_type" == "dos" ]]; then
  if [[ ! -f "$backup_dir/disk-pt.sf" ]]; then
    printx "Error: $backup_dir/disk-pt.sf not found."
    exit 1
  fi
  sfdisk "$target_disk" < "$backup_dir/disk-pt.sf"
fi
echo "Partition table restoration complete."

# Inform kernel of partition table changes
partprobe "$target_disk"

# Restore selected filesystems
for part in "${selected[@]}"; do
  partition_device="/dev/$part"
  fsa_file="$backup_dir/$part.fsa"
  if [[ ! -f "$fsa_file" ]]; then
    printx "Error: $fsa_file not found, skipping $partition_device"
    continue
  fi
  if [[ ! -b "$partition_device" ]]; then
    printx "Error: $partition_device not a block device, skipping"
    continue
  fi
  # Check if partition is mounted
  mount_point=$(awk -v part="$partition_device" '$1 == part {print $2}' /proc/mounts)
  if [[ -n "$mount_point" ]]; then
    printx "Error: $partition_device is mounted at $mount_point."
    read -p "Proceed and unmount it first? [y/N] " response
    if [[ "$response" =~ ^[yY]$ ]]; then
      if ! umount "$mount_point"; then
        printx "Error: Failed to unmount $mount_point, skipping $partition_device"
        continue
      fi
    else
      printx "Skipping restoration of $partition_device"
      continue
    fi
  fi
  if [[ "$partition_device" == "$root_part" ]]; then
    printx "Warning: Restoring active root partition $partition_device may cause system instability"
  fi
  echo "Restoring $fsa_file -> $partition_device"
  if ! fsarchiver restfs "$fsa_file" id=0,dest="$partition_device"; then
    printx "Error: Failed to restore $partition_device"
    continue
  fi
done

echo "✅ Restoration complete: $target_disk"
lsblk -f "$target_disk"