#!/bin/bash

# Переменные
VM_NAME="windows-vm"
MODIFIED_ISO="windows10_autounattend.iso"
RDP_USER="localuser"
RDP_PASS="Password123!"
WATCH_DIR="$HOME/Downloads"
SHARE_FOLDER="$HOME/shared"
VM_DISK="$HOME/${VM_NAME}.qcow2"
CHECK_INTERVAL=60  # Интервал проверки состояния установки в секундах
TIMEOUT=3600       # Таймаут в секундах (1 час)

# Установка необходимых пакетов
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager sshpass inotify-tools freerdp2-x11 ansible genisoimage

# Добавление пользователя в группу libvirt
sudo usermod -aG libvirt $(whoami)

# Настройка сети NAT для виртуальной машины (если не существует)
if ! virsh net-list --all | grep -q 'default'; then
    tee /etc/libvirt/qemu/networks/default.xml > /dev/null <<EOL
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

    virsh net-define /etc/libvirt/qemu/networks/default.xml
    virsh net-start default
else
    echo "Network default already exists"
fi

virsh net-autostart default

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
  --cdrom "$MODIFIED_ISO" \
  --noautoconsole

# Ожидание завершения установки Windows (максимум 1 час)
echo "Ожидание завершения установки Windows (до 1 часа)..."
START_TIME=$(date +%s)

while true; do
  # Проверка, что виртуальная машина запущена
  VM_STATE=$(virsh domstate "$VM_NAME")
  
  if [ "$VM_STATE" == "running" ]; then
    echo "Виртуальная машина все еще устанавливается..."
  else
    echo "Установка завершена."
    break
  fi

  # Проверка таймаута
  CURRENT_TIME=$(date +%s)
  ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

  if [ "$ELAPSED_TIME" -ge "$TIMEOUT" ]; then
    echo "Таймаут ожидания завершения установки Windows."
    exit 1
  fi

  sleep "$CHECK_INTERVAL"
done

# Настройка SSH доступа к виртуальной машине
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
sshpass -p "$RDP_PASS" ssh-copy-id -o StrictHostKeyChecking=no "$RDP_USER@192.168.122.2"

# Настройка RDP на виртуальной машине с помощью Ansible
tee ansible-playbook.yml > /dev/null <<EOF
---
- hosts: all
  tasks:
    - name: Enable RDP
      win_feature:
        name: RDS-RD-Server
        state: present

    - name: Allow RDP in Firewall
      win_firewall_rule:
        name: 'Remote Desktop'
        enable: yes
        group: 'remote desktop'

    - name: Set UAC to lowest level
      win_regedit:
        path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
        name: EnableLUA
        data: 0
        type: dword
      notify: reboot

    - name: Disable UAC prompt for administrators
      win_regedit:
        path: HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
        name: ConsentPromptBehaviorAdmin
        data: 0
        type: dword
      notify: reboot

    - name: Reboot the machine to apply changes
      win_reboot:
        msg: "Rebooting to apply UAC changes"
        pre_reboot_delay: 0
        post_reboot_delay: 30
        reboot_timeout: 600
      when: reboot_needed
EOF

ansible-playbook -i "192.168.122.2," -u "$RDP_USER" --ssh-extra-args='-o StrictHostKeyChecking=no' ansible-playbook.yml

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

echo "Настройка завершена. Виртуальная машина с Windows готова к использованию."
