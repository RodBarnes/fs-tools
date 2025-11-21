#!/bin/bash

# Script to facilitate building the swap partition if it is not working

swap_device=/dev/sda3
os_device=/dev/sda2
boot_device=/dev/sda1

# Mount the devices
sudo mkswap $device
SWAP_UUID=$(blkid -s UUID -o value $device)
sudo mount $os_device /mnt
sudo mount $boot_device /mnt/boot/efi

# Bind the system directories
for d in dev proc sys run; do sudo mount --bind /$d /mnt/$d; done

# Update /etc/fstab
sed -i "s/UUID=.*[[:space:]]\+none[[:space:]]\+swap/UUID=$SWAP_UUID none swap/" /mnt/etc/fstab

# Update for hibernation
echo "RESUME=UUID=$SWAP_UUID" | sudo tee /mnt/etc/initramfs-tools/conf.d/resume

# Update initramfs
sudo chroot /mnt update-initramfs -u -k all

# Unmount the system directories
for d in dev proc sys run boot/efi; do sudo umount /mnt/$d; done

# Unmount the OS device
sudo umount /mnt