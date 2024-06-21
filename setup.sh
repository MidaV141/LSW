#!/bin/bash

# Настройка среды Linux
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager sshpass ansible

# Создание виртуальной машины
VM_NAME="windows-vm"
ISO_PATH="/path/to/windows.iso"
VIRT_DISK="/var/lib/libvirt/images/${VM_NAME}.qcow2"

sudo qemu-img create -f qcow2 "${VIRT_DISK}" 40G

sudo virt-install \
    --name="${VM_NAME}" \
    --os-variant=win10 \
    --vcpu=2 \
    --ram=4096 \
    --cdrom="${ISO_PATH}" \
    --network network=default,model=virtio \
    --disk path="${VIRT_DISK}",format=qcow2 \
    --graphics spice \
    --noautoconsole \
    --autostart

# Настройка SSH для взаимодействия с виртуальной машиной
ssh-keygen -t rsa -b 2048 -f ~/.ssh/id_rsa -N ""
SSH_PUBLIC_KEY=$(cat ~/.ssh/id_rsa.pub)

# Настройка Ansible для настройки виртуальной машины
cat <<EOF > hosts
[windows]
windows-vm ansible_host=192.168.122.2 ansible_user=Administrator ansible_password=securepassword ansible_connection=winrm ansible_winrm_transport=basic ansible_winrm_server_cert_validation=ignore
EOF

cat <<EOF > setup_vm.yml
---
- name: Настройка виртуальной машины Windows
  hosts: windows
  tasks:
    - name: Создание пользователя и настройка ключей SSH
      win_user:
        name: ansible
        password: securepassword
        groups: Administrators

    - name: Настройка SSH
      win_copy:
        content: "${SSH_PUBLIC_KEY}"
        dest: "C:\\Users\\ansible\\.ssh\\authorized_keys"

    - name: Установка и настройка RDP
      win_feature:
        name: RDS-RD-Server
        state: present

    - name: Разрешение RDP через брандмауэр
      win_firewall_rule:
        name: 'RDP'
        enable: yes
        direction: in
        action: allow
        localport: 3389
        protocol: TCP

    - name: Обновление реестра для разрешения RDP
      win_regedit:
        path: HKLM:\\SYSTEM\\CurrentControlSet\\Control\\Terminal Server
        name: fDenyTSConnections
        data: 0
        type: dword

    - name: Перезапуск службы RDP
      win_service:
        name: TermService
        start_mode: auto
        state: started
EOF

ansible-playbook -i hosts setup_vm.yml
