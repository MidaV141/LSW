#!/bin/bash

# Переменные
VM_NAME="windows-vm"
ISO_PATH="/path/to/windows10.iso"
AUTOUNATTEND_XML="/path/to/autounattend.xml"
RDP_USER="localuser"
RDP_PASS="Password123!"
WATCH_DIR="$HOME/Downloads"
SHARE_FOLDER="$HOME/shared"
VM_DISK="$HOME/${VM_NAME}.qcow2"

# Установка необходимых пакетов
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager sshpass inotify-tools xfreerdp

# Настройка сети NAT для виртуальной машины
sudo tee /etc/libvirt/qemu/networks/default.xml > /dev/null <<EOL
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOL

sudo virsh net-define /etc/libvirt/qemu/networks/default.xml
sudo virsh net-start default
sudo virsh net-autostart default

# Создание образа диска для виртуальной машины
qemu-img create -f qcow2 "$VM_DISK" 50G

# Создание и запуск виртуальной машины с Windows
virt-install \
  --name "$VM_NAME" \
  --ram 4096 \
  --vcpus 2 \
  --os-type windows \
  --os-variant win10 \
  --network network=default \
  --graphics vnc \
  --disk path="$VM_DISK",format=qcow2 \
  --cdrom "$ISO_PATH" \
  --disk path="$AUTOUNATTEND_XML",device=cdrom \
  --extra-args "autounattend=$AUTOUNATTEND_XML"

# Ожидание завершения установки Windows (максимум 30 минут)
echo "Ожидание завершения установки Windows (до 30 минут)..."
sleep 1800

# Настройка SSH доступа к виртуальной машине
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
sshpass -p "$RDP_PASS" ssh-copy-id -o StrictHostKeyChecking=no "$RDP_USER@192.168.122.2"

# Настройка RDP на виртуальной машине
ssh "$RDP_USER@192.168.122.2" <<EOF
reg add "HKEY_LOCAL_MACHINE\\System\\CurrentControlSet\\Control\\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f
netsh advfirewall firewall set rule group="remote desktop" new enable=Yes

# Установка запуска команд с правами администратора без запроса UAC
reg add "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System" /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 0 /f
reg add "HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Policies\\System" /v EnableLUA /t REG_DWORD /d 0 /f
EOF

# Настройка общей папки
mkdir -p "$SHARE_FOLDER"
sudo mount -t 9p -o trans=virtio,version=9p2000.L,rw,cache=none hostshare "$SHARE_FOLDER"

# Создание и активация служб systemd
sudo tee /etc/systemd/system/windows-vm.service > /dev/null <<EOL
[Unit]
Description=Windows VM Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/virsh start "$VM_NAME"
ExecStop=/usr/bin/virsh shutdown "$VM_NAME"
Restart=always

[Install]
WantedBy=multi-user.target
EOL

sudo tee /etc/systemd/system/exe-monitor.service > /dev/null <<EOL
[Unit]
Description=Monitor new exe files and handle them

[Service]
Type=simple
ExecStart=/bin/bash "$HOME/project-name/main.sh"
Restart=always

[Install]
WantedBy=multi-user.target
EOL

sudo systemctl enable windows-vm.service
sudo systemctl start windows-vm.service

sudo systemctl enable exe-monitor.service
sudo systemctl start exe-monitor.service
