#!/bin/bash

# Переменные
VM_NAME="windows-vm"
RDP_USER="Administrator"
RDP_PASS="securepassword"
RDP_IP="192.168.122.2"
WATCH_DIR="$HOME/Downloads"
SHARE_FOLDER="/mnt/hgfs/SharedFolder"

# Функция для обработки новых файлов
handle_new_program() {
    local program_path="$1"
    local program_name="${program_path##*/}"
    program_name="${program_name%.*}"
    mkdir -p "${SHARE_FOLDER}/${program_name}"
    cp "${program_path}" "${SHARE_FOLDER}/${program_name}/${program_name}.exe"

    if ! sudo virsh domstate "${VM_NAME}" | grep -q "running"; then
        sudo virsh start "${VM_NAME}"
        sleep 30
    fi

    sshpass -p "${RDP_PASS}" ssh ${RDP_USER}@${RDP_IP} "C:\\path\\to\\shared\\folder\\${program_name}\\${program_name}.exe"

    cat <<EOF > ~/Desktop/${program_name}.desktop
[Desktop Entry]
Version=1.0
Name=${program_name}
Comment=Launch ${program_name} via VM
Exec=xfreerdp /u:${RDP_USER} /p:${RDP_PASS} /v:${RDP_IP} /app:"||C:\\path\\to\\shared\\folder\\${program_name}\\${program_name}.exe"
Icon=application-x-ms-dos-executable
Terminal=false
Type=Application
EOF
}

# Мониторинг каталога на новые exe файлы
inotifywait -m "$WATCH_DIR" -e create -e moved_to |
    while read -r directory action file; do
        if [[ "$file" == *.exe ]]; then
            handle_new_program "${directory}${file}"
        fi
    done
