#!/bin/bash

WATCH_DIR="$HOME/Downloads"
SHARE_FOLDER="$HOME/shared"

inotifywait -m "$WATCH_DIR" -e create -e moved_to |
while read path action file; do
  if [[ "$file" == *.exe ]]; then
    echo "Новый файл $file был найден в $WATCH_DIR, перемещаем и запускаем на виртуальной машине..."
    
    cp "$WATCH_DIR/$file" "$SHARE_FOLDER/$file"
    
    sshpass -p "Password123!" ssh -o StrictHostKeyChecking=no localuser@192.168.122.2 "C:\\path\\to\\shared\\folder\\$file"
    
    # Создание ярлыка на хостовой системе
    cat > "$HOME/Desktop/${file%.*}.desktop" <<EOL
[Desktop Entry]
Version=1.0
Name=${file%.*}
Exec=xfreerdp /u:localuser /p:Password123! /v:192.168.122.2 /app:"C:\\path\\to\\shared\\folder\\$file"
Icon=application-x-executable
Terminal=false
Type=Application
EOL

  fi
done
