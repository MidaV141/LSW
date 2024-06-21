#!/bin/bash

WATCH_DIR="$HOME/Downloads"
VM_NAME="windows-vm"
SHARE_FOLDER="/mnt/hgfs/SharedFolder"
RDP_IP="192.168.122.2"
RDP_USER="Administrator"
RDP_PASS="securepassword"

# Функция для обработки новых файлов
handle_new_program() {
    local program_path="$1"
    local program_name="${program_path##*/}"
    program_name="${program_name%.*}"
    SHARE_FOLDER="${SHARE_FOLDER}/${program_name}"
    mkdir -p "${SHARE_FOLDER}"
    cp "${program_path}" "${SHARE_FOLDER}/${program_name}.exe"

    if ! sudo virsh domstate "${VM_NAME}" | grep -q "running"; then
        sudo virsh start "${VM_NAME}"
        sleep 30
    fi

    sshpass -p "${RDP_PASS}" ssh "${RDP_USER}@${RDP_IP}" "C:\\path\\to\\shared\\folder\\${program_name}\\${program_name}.exe"

    cat <<EOF > ~/Desktop/${program_name}.desktop
[Desktop Entry]
Version=1.0
Name=${program_name}
Comment=Launch ${program_name} via VM
Exec=xfreerdp /u:${RDP_USER} /p:${RDP_PASS} /v:${RDP_IP} /app:"||C:\\path\\to\\shared\\folder\\${program_name}\\${program_name}.exe"
Icon=application-x-executable
Terminal=false
Type=Application
EOF
}

inotifywait -m "$WATCH_DIR" -e create -e moved_to |
    while read -r directory action file; do
        if [[ "$file" == *.exe ]]; then
            handle_new_program "${directory}${file}"
        fi
    done
