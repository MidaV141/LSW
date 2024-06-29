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
FIXED_IP="192.168.123.10"

# Установка необходимых пакетов
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager sshpass inotify-tools freerdp2-x11 ansible genisoimage

# Добавление пользователя в группу libvirt
sudo usermod -aG libvirt $(whoami)

# Создание сети с фиксированным IP для виртуальной машины
sudo tee /etc/libvirt/qemu/networks/fixed_network.xml > /dev/null <<EOL
<network>
  <name>fixed_network</name>
  <forward mode='nat'/>
  <bridge name='virbr1' stp='on' delay='0'/>
  <ip address='192.168.123.1' netmask='255.255.255.0'>
    <dhcp>
      <host mac='52:54:00:bd:86:21' name='${VM_NAME}' ip='${FIXED_IP}'/>
      <range start='192.168.123.2' end='192.168.123.254'/>
    </dhcp>
  </ip>
</network>
EOL

sudo virsh net-define /etc/libvirt/qemu/networks/fixed_network.xml
sudo virsh net-start fixed_network
sudo virsh net-autostart fixed_network

# Создание образа диска для виртуальной машины
qemu-img create -f qcow2 "$VM_DISK" 50G

# Создание и запуск виртуальной машины с Windows
virt-install \
  --name "$VM_NAME" \
  --ram 4096 \
  --vcpus 2 \
  --os-type windows \
  --os-variant win10 \
  --network network=fixed_network,mac=52:54:00:bd:86:21 \
  --graphics vnc \
  --disk path="$VM_DISK",format=qcow2 \
  --cdrom "$MODIFIED_ISO" \
  --noautoconsole

# Функция для проверки состояния виртуальной машины и её запуска
check_and_start_vm() {
  while true; do
    VM_STATE=$(virsh domstate "$VM_NAME")
    if [ "$VM_STATE" == "shut off" ]; then
      echo "Виртуальная машина выключена. Перезапуск..."
      virsh start "$VM_NAME"
    elif [ "$VM_STATE" == "running" ]; then
      echo "Виртуальная машина работает."
      break
    fi
    sleep "$CHECK_INTERVAL"
  done
}

# Ожидание завершения установки Windows (максимум 1 час)
echo "Ожидание завершения установки Windows (до 1 часа)..."
START_TIME=$(date +%s)
INSTALL_COMPLETE=false

while true; do
  check_and_start_vm

  # Удаление старого ключа хоста
  ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$FIXED_IP"

  # Проверка доступности машины по SSH
  sshpass -p "$RDP_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$RDP_USER@$FIXED_IP" exit
  if [ $? -eq 0 ]; then
    INSTALL_COMPLETE=true
    echo "Машина доступна по SSH."
    break
  fi

  # Проверка таймаута
  CURRENT_TIME=$(date +%s)
  ELAPSED_TIME=$((CURRENT_TIME - START_TIME))

  if [ "$ELAPSED_TIME" -ge "$TIMEOUT" ]; then
    echo "Таймаут ожидания завершения установки Windows."
    exit 1
  fi

  echo "Ожидание завершения установки Windows..."
  sleep "$CHECK_INTERVAL"
done

if [ "$INSTALL_COMPLETE" = true ]; then
  # Генерация SSH ключей
  if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    ssh-keygen -t rsa -b 2048 -N "" -f "$HOME/.ssh/id_rsa"
  fi

  # Копирование SSH ключа на виртуальную машину
  sshpass -p "$RDP_PASS" ssh-copy-id -o StrictHostKeyChecking=no -i "$HOME/.ssh/id_rsa.pub" "$RDP_USER@$FIXED_IP"

  # Настройка RDP на виртуальной машине с помощью Ansible
  tee ansible-rdp.yml > /dev/null <<EOF
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

  # Использование пароля при подключении Ansible
  ANSIBLE_PASSWORD_FILE=$(mktemp)
  echo -n "$RDP_PASS" > "$ANSIBLE_PASSWORD_FILE"

  ANSIBLE_CONFIG_FILE=$(mktemp)
  tee "$ANSIBLE_CONFIG_FILE" > /dev/null <<EOF
[defaults]
host_key_checking = False
ansible_user = $RDP_USER
ansible_ssh_pass = $RDP_PASS
ansible_ssh_private_key_file = $HOME/.ssh/id_rsa
EOF

  ANSIBLE_HOSTS_FILE=$(mktemp)
  echo "$FIXED_IP ansible_password=$RDP_PASS" > "$ANSIBLE_HOSTS_FILE"

  ANSIBLE_CONFIG="$ANSIBLE_CONFIG_FILE" ansible-playbook -i "$ANSIBLE_HOSTS_FILE" ansible-rdp.yml

  # Настройка общей папки
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
fi
