#!/bin/bash

# Переменные
ORIGINAL_ISO="windows10.iso"
AUTOUNATTEND_XML="autounattend.xml"
MODIFIED_ISO="windows10_autounattend.iso"

# Проверка наличия необходимых файлов
if [[ ! -f "$ORIGINAL_ISO" || ! -f "$AUTOUNATTEND_XML" ]]; then
  echo "Ошибка: Файлы $ORIGINAL_ISO и/или $AUTOUNATTEND_XML не найдены."
  exit 1
fi

# Создание модифицированного ISO-образа с autounattend.xml
WORK_DIR=$(mktemp -d)
ISO_ORIGINAL=$(realpath "$ORIGINAL_ISO")
AUTOUNATTEND_XML=$(realpath "$AUTOUNATTEND_XML")

mkdir -p "$WORK_DIR/iso"
mkdir -p "$WORK_DIR/new_iso"

# Монтирование ISO-образа и копирование содержимого
sudo mount -o loop "$ISO_ORIGINAL" "$WORK_DIR/iso"
cp -r "$WORK_DIR/iso/"* "$WORK_DIR/new_iso/"
cp "$AUTOUNATTEND_XML" "$WORK_DIR/new_iso/"
sudo umount "$WORK_DIR/iso"

# Создание нового ISO-образа
genisoimage -o "$MODIFIED_ISO" -b boot/etfsboot.com -no-emul-boot -boot-load-seg 0x07C0 -boot-load-size 8 -iso-level 2 -relaxed-filenames -allow-limited-size -volid "WIN10_CUSTOM" "$WORK_DIR/new_iso"

# Удаление временной рабочей директории
rm -rf "$WORK_DIR"

echo "Модифицированный ISO-образ создан: $MODIFIED_ISO"
