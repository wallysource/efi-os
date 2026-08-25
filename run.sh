#!/bin/bash

# Exit immediately if any command fails
set -e

# Prompt for the source file location
read -p "Enter the full path to the source file (e.g., /path/to/main.c): " SOURCE_FILE

# Derive filenames from the source file
BASE_NAME=$(basename "$SOURCE_FILE" .c)
OBJ_FILE="$BASE_NAME.o"
SO_FILE="$BASE_NAME.so"
EFI_FILE="$BASE_NAME.efi"
BOOT_IMG="boot.img"
MOUNT_DIR=$(mktemp -d)
BIOS_PATH="/usr/share/ovmf/OVMF.fd"
GNU_EFI_LIB="/usr/lib"
GNU_EFI_INCLUDE="/usr/include/efi"

# Step 1: Compile the source file to an object file
echo "Compiling $SOURCE_FILE to $OBJ_FILE..."
gcc -I"$GNU_EFI_INCLUDE" -fpic -ffreestanding -fno-stack-protector -fno-stack-check \
    -fshort-wchar -mno-red-zone -maccumulate-outgoing-args -c "$SOURCE_FILE" -o "$OBJ_FILE"

echo "Compilation complete."

# Step 2: Link the object file to a shared object
echo "Linking $OBJ_FILE to $SO_FILE..."
ld -shared -Bsymbolic -L"$GNU_EFI_LIB"/x86_64/lib -L"$GNU_EFI_LIB"/x86_64/gnuefi \
    -T"$GNU_EFI_LIB"/elf_x86_64_efi.lds "$GNU_EFI_LIB"/crt0-efi-x86_64.o "$OBJ_FILE" \
    -L/usr/lib \
    -o "$SO_FILE" -lgnuefi -lefi

echo "Linking complete."

# Step 3: Convert the shared object to an EFI application
echo "Generating $EFI_FILE from $SO_FILE..."
objcopy -j .text -j .sdata -j .data -j .rodata -j .dynamic -j .dynsym \
        -j .rel -j .rela -j .rel.* -j .rela.* -j .reloc \
        -I elf64-x86-64 -O efi-app-x86_64 --subsystem=10 "$SO_FILE" "$EFI_FILE"

echo "EFI file creation complete."

# Step 4: Create and prepare the bootable image
echo "Creating and preparing $BOOT_IMG..."
dd if=/dev/zero of="$BOOT_IMG" bs=1M count=128
parted --script "$BOOT_IMG" mklabel gpt mkpart ESP fat32 1MiB 100% set 1 esp on

LOOP_DEV=$(sudo losetup --find --show --partscan "$BOOT_IMG")
sudo mkfs.vfat -F 32 "${LOOP_DEV}p1"
sudo mount "${LOOP_DEV}p1" "$MOUNT_DIR"
sudo mkdir -p "$MOUNT_DIR/EFI/BOOT"
sudo cp "$EFI_FILE" "$MOUNT_DIR/EFI/BOOT/BOOTX64.EFI"
sudo umount "$MOUNT_DIR"
sudo losetup -d "$LOOP_DEV"
rmdir "$MOUNT_DIR"

echo "Bootable image created successfully."

# Step 5: Ask user to test the image in QEMU
echo "Do you want to test the bootable image in QEMU? (y/n)"
read -r RUN_QEMU 
if [ "$RUN_QEMU" == "y" ]; then
    qemu-system-x86_64 -drive file="$BOOT_IMG",format=raw -bios "$BIOS_PATH"
else
    echo "Skipping QEMU test."
fi

# Final message
echo "Process complete. Enjoy testing your EFI application!"
sudo rm /home/wally/Documents/paperOS/newgen.so
sudo rm /home/wally/Documents/paperOS/newgen.o
sudo rm /home/wally/Documents/paperOS/boot.img
sudo mv /home/wally/Documents/paperOS/newgen.efi /home/wally/Documents/
sudo chown --reference=/home/wally/Documents/Hollow.Knight.v1.5.12620 /home/wally/Documents/newgen.efi

