#!/bin/bash
set -euo pipefail

CONFIG_FILE="/etc/lsw.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Конфигурационный файл $CONFIG_FILE не найден. Запустите setup.sh для инициализации." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR/.ansible"
ANSIBLE_CFG="$ANSIBLE_DIR/ansible.cfg"
ANSIBLE_INVENTORY="$ANSIBLE_DIR/hosts.ini"

WATCH_DIR="${WATCH_DIR:-$HOME/Downloads}"
DESKTOP_DIR="${DESKTOP_DIR:-$HOME/Desktop}"
REMOTE_APPS_DIR="${REMOTE_APPS_DIR:-C:\\LSW\\Apps}"
RDP_USER="${RDP_USER:?RDP_USER не задан в $CONFIG_FILE}"
RDP_PASS="${RDP_PASS:?RDP_PASS не задан в $CONFIG_FILE}"
VM_IP="${VM_IP:?VM_IP не задан в $CONFIG_FILE}"

export PATH="$HOME/.local/bin:$PATH"
export ANSIBLE_CONFIG="$ANSIBLE_CFG"

if [[ ! -d "$WATCH_DIR" ]]; then
  mkdir -p "$WATCH_DIR"
fi

if [[ ! -d "$DESKTOP_DIR" ]]; then
  mkdir -p "$DESKTOP_DIR"
fi

sanitize_filename() {
  local name="$1"
  name="${name%.*}"
  name="${name//[^A-Za-z0-9._-]/_}"
  printf '%s' "$name"
}

create_desktop_file() {
  local source_file="$1"
  local desktop_name="$2"
  local desktop_file="$DESKTOP_DIR/${desktop_name}.desktop"
  cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=${source_file%.*}
Exec=xfreerdp /u:"$RDP_USER" /p:"$RDP_PASS" /v:$VM_IP /dynamic-resolution
Icon=application-x-executable
Terminal=false
Categories=Utility;
DESKTOP
  chmod +x "$desktop_file"
}

process_file() {
  local file="$1"
  local full_path="$WATCH_DIR/$file"
  if [[ ! -f "$full_path" ]]; then
    return
  fi

  echo "Обнаружен новый файл $file. Копирование и запуск на виртуальной машине..."

  APP_SOURCE="$full_path" APP_NAME="$file" REMOTE_APPS_DIR="$REMOTE_APPS_DIR" \
    ansible-playbook "$SCRIPT_DIR/ansible/deploy-app.yml"

  local desktop_name
  desktop_name=$(sanitize_filename "$file")
  create_desktop_file "$file" "$desktop_name"
  echo "Файл $file обработан. Ярлык создан: $DESKTOP_DIR/${desktop_name}.desktop"
}

command -v ansible-playbook >/dev/null 2>&1 || {
  echo "ansible-playbook не найден. Установите Ansible." >&2
  exit 1
}

command -v inotifywait >/dev/null 2>&1 || {
  echo "Утилита inotifywait не найдена. Установите пакет inotify-tools." >&2
  exit 1
}

inotifywait -m "$WATCH_DIR" -e create -e moved_to |
while read -r path action file; do
  if [[ "$file" == *.exe ]]; then
    process_file "$file"
  fi
done
