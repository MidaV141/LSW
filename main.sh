#!/bin/bash

WATCH_DIR="$HOME/Downloads"
SHARE_FOLDER="$HOME/shared"
VM_NAME="windows-vm"
RDP_USER="localuser"
RDP_PASS="Password123!"
RDP_IP="192.168.122.2"

inotifywait -m "$WATCH_DIR" -e create -e moved_to |
    while read -r directory action file; do
        if [[ "$file" =~ \.exe$ ]]; then
            program_path="$directory/$file"
            program_name="${file%.*}"
            cp "$program_path" "$SHARE_FOLDER/$file"

            if ! sudo virsh domstate "$VM_NAME" | grep -q "running"; then
                sudo virsh start "$VM_NAME"
                sleep 30
            fi

            sshpass -p "$RDP_PASS" ssh "$RDP_USER@$RDP_IP" "C:\\path\\to\\shared\\folder\\$file"

            cat <<EOF > "$HOME/Desktop/$program_name.desktop"
[Desktop Entry]
Version=1.0
Name=$program_name
Comment=Launch $program_name via VM
Exec=xfreerdp /u:$RDP_USER /p:$RDP_PASS /v:$RDP_IP /app:"||C:\\path\\to\\shared\\folder\\$file"
Icon=application-x-ms-dos-executable
Terminal=false
Type=Application
EOF
        fi
    done
