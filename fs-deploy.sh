#!/usr/bin/env bash

# Deploy fs-tools to a target system.
# Copies library and program files to the target, then runs fs-install.sh remotely.
# Syntax: fs-deploy <target>
# Where:  <target> is the hostname or IP of the target system.

# Path to the tools repo containing display.sh and device.sh
TOOLS_DIR=~/src/mine/tools

# Files to deploy
tools_lib_files=(
  display.sh
  device.sh
)

lib_files=(
  fs-shared.sh
)

prog_files=(
  fs-backup.sh
  fs-delete.sh
  fs-list.sh
  fs-restore.sh
  fs-install.sh
)

# --------------------
# ------- MAIN -------
# --------------------

if [ $# -lt 1 ]; then
  echo "Syntax: $(basename $0) <target>"
  exit 1
fi

target=$1
remote_user=rod
remote_home=/home/$remote_user

echo "Deploying fs-tools to $target..."

echo "Copying tools library files..."
for file in "${tools_lib_files[@]}"; do
  scp "$TOOLS_DIR/$file" "$remote_user@$target:$remote_home/$file"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to copy $file to $target"
    exit 1
  fi
done

echo "Copying library files..."
for file in "${lib_files[@]}"; do
  scp "$file" "$remote_user@$target:$remote_home/$file"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to copy $file to $target"
    exit 1
  fi
done

echo "Copying program files..."
for file in "${prog_files[@]}"; do
  scp "$file" "$remote_user@$target:$remote_home/$file"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to copy $file to $target"
    exit 1
  fi
done

echo "Running fs-install.sh on $target..."
ssh -t "$remote_user@$target" "bash $remote_home/fs-install.sh"
if [ $? -ne 0 ]; then
  echo "Error: Installation failed on $target"
  exit 1
fi

echo "✅ fs-tools deployment to $target complete."
