#!/bin/bash

WATCH_DIR="$HOME/Downloads"
SHARE_FOLDER="$HOME/shared"
VM_NAME="windows-vm"
RDP_USER="localuser"
RDP_PASS="Password123!"

inotifywait -m "$WATCH_DIR" -e create -e moved_to |
    while read path action file; do
        if [[ "$file" == *.exe ]]; then
            handle_new_program "$WATCH_DIR/$file"
        fi
    done

handle_new_program() {
    local program_path="$1"
    local program_name="${program_path##*/}"
    program_name="${program_name%.*}"
    SHARE_FOLDER="${BASE_SHARE_FOLDER}/${program_name}"
    mkdir -p "${SHARE_FOLDER}"
    cp "${program_path}" "${SHARE_FOLDER}/${program_name}.exe"

    if ! sudo virsh domstate "${VM_NAME}" | grep -q "running"; then
        sudo virsh start "${VM_NAME}"
        sleep 30
    fi

    sshpass -p "${RDP_PASS}" ssh ${RDP_USER}@192.168.122.2 "C:\\path\\to\\shared\\folder\\${program_name}\\${program_name}.exe"

    cat <<EOF > ~/Desktop/${program_name}.desktop
[Desktop Entry]
Version=1.0
Name=${program_name}
Comment=Launch ${program_name} via VM
Exec=xfreerdp /u:${RDP_USER} /p:${RDP_PASS} /v:192.168.122.2 /app:"||C:\\path\\to\\shared\\folder\\${program_name}\\${program_name}.exe"
Icon=application-x-executable
Terminal=false
Type=Application
EOF
}
