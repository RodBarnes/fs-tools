#!/usr/bin/env bash

# Install fs-tools on the local system.
# Intended to be copied to the target and invoked remotely by fs-deploy.sh.
# Must be run as a user with sudo privileges.

lib_dest=/usr/local/lib
sbin_dest=/usr/local/sbin
remote_home=/home/rod

lib_files=(
  fs-shared.sh
)

prog_files=(
  fs-backup.sh
  fs-delete.sh
  fs-list.sh
  fs-restore.sh
)

echo "Installing fs-tools..."

sudo -v

echo "Installing library files to $lib_dest..."
for file in "${lib_files[@]}"; do
  sudo chown root:root "$remote_home/$file"
  sudo mv "$remote_home/$file" "$lib_dest/$file"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to install $file to $lib_dest"
    exit 1
  fi
done

echo "Installing program files to $sbin_dest..."
for file in "${prog_files[@]}"; do
  target="${file%.sh}"
  sudo chown root:root "$remote_home/$file"
  sudo chmod +x "$remote_home/$file"
  sudo mv "$remote_home/$file" "$sbin_dest/$target"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to install $file to $sbin_dest"
    exit 1
  fi
done

echo "Cleaning up..."
rm -f "$remote_home/fs-install.sh"

echo "✅ fs-tools installation complete."
