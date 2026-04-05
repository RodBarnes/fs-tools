#!/usr/bin/env bash

# Install fs-tools on the local system.
# Intended to be copied to the target and invoked remotely by fs-deploy.sh,
# or run directly on the development system using the --local flag.
# Must be run as a user with sudo privileges.

lib_dest=/usr/local/lib
sbin_dest=/usr/local/sbin
tools_dir=~/src/mine/tools

fs_lib_files=(
  fs-shared.sh
)

tools_lib_files=(
  device.sh
  display.sh
)

prog_files=(
  fs-backup.sh
  fs-delete.sh
  fs-list.sh
  fs-restore.sh
)

# Parse arguments
local_install=false
if [[ "$1" == "--local" ]]; then
  local_install=true
fi

# Set source directory and file operation based on mode
if [[ "$local_install" == true ]]; then
  source_dir=.
  file_op=cp
else
  source_dir=/home/$USER
  file_op=mv
fi

echo "Installing fs-tools..."

sudo -v || exit 1

packages=(fsarchiver gdisk jq parted)
missing=()
for pkg in "${packages[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null; then
    missing+=("$pkg")
  fi
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Installing missing packages: ${missing[*]}"
  sudo apt-get install -y "${missing[@]}" || { echo "Error: Package installation failed"; exit 1; }
fi

echo "Installing library files to $lib_dest..."
for file in "${fs_lib_files[@]}"; do
  sudo $file_op "$source_dir/$file" "$lib_dest/$file"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to install $file to $lib_dest"
    exit 1
  fi
  sudo chown root:root "$lib_dest/$file"
done
for file in "${tools_lib_files[@]}"; do
  if [[ "$local_install" == true ]]; then
    sudo cp "$tools_dir/$file" "$lib_dest/$file"
  else
    sudo $file_op "$source_dir/$file" "$lib_dest/$file"
  fi
  if [ $? -ne 0 ]; then
    echo "Error: Failed to install $file to $lib_dest"
    exit 1
  fi
  sudo chown root:root "$lib_dest/$file"
done

echo "Installing program files to $sbin_dest..."
for file in "${prog_files[@]}"; do
  target="${file%.sh}"
  sudo $file_op "$source_dir/$file" "$sbin_dest/$target"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to install $file to $sbin_dest"
    exit 1
  fi
  sudo chown root:root "$sbin_dest/$target"
  sudo chmod +x "$sbin_dest/$target"
done

if [[ "$local_install" == false ]]; then
  echo "Cleaning up..."
  rm -f "$source_dir/fs-install.sh"
fi

echo "✅ fs-tools installation complete."
