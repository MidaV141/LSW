#!/bin/bash
set -euo pipefail

# Переменные
ORIGINAL_ISO="windows10.iso"
AUTOUNATTEND_XML="autounattend.xml"
MODIFIED_ISO="windows10_autounattend.iso"

if [[ -z "${LSW_USERNAME:-}" || -z "${LSW_PASSWORD:-}" ]]; then
  echo "Ошибка: переменные окружения LSW_USERNAME и LSW_PASSWORD должны быть заданы." >&2
  echo "Пример: LSW_USERNAME=localuser LSW_PASSWORD='StrongPassw0rd!' ./create_iso.sh" >&2
  exit 1
fi

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\\&/]/\\&/g'
}

PASSWORD_BASE64=$(printf '%s' "$LSW_PASSWORD" | iconv -f UTF-8 -t UTF-16LE | base64)

# Проверка наличия необходимых файлов
if [[ ! -f "$ORIGINAL_ISO" || ! -f "$AUTOUNATTEND_XML" ]]; then
  echo "Ошибка: Файлы $ORIGINAL_ISO и/или $AUTOUNATTEND_XML не найдены."
  exit 1
fi

TEMP_AUTOUNATTEND=$(mktemp)
trap 'rm -f "$TEMP_AUTOUNATTEND"' EXIT

USERNAME_ESCAPED=$(escape_sed "$LSW_USERNAME")
PASSWORD_ESCAPED=$(escape_sed "$LSW_PASSWORD")
PASSWORD_BASE64_ESCAPED=$(escape_sed "$PASSWORD_BASE64")

sed -e "s/__LSW_USERNAME__/$USERNAME_ESCAPED/g" \
    -e "s/__LSW_PASSWORD_CLEAR__/$PASSWORD_ESCAPED/g" \
    -e "s/__LSW_PASSWORD_BASE64__/$PASSWORD_BASE64_ESCAPED/g" \
  "$AUTOUNATTEND_XML" > "$TEMP_AUTOUNATTEND"

# Создание модифицированного ISO-образа с autounattend.xml
WORK_DIR=$(mktemp -d)
ISO_ORIGINAL=$(realpath "$ORIGINAL_ISO")
AUTOUNATTEND_XML=$(realpath "$TEMP_AUTOUNATTEND")

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
