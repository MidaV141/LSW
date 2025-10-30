#!/bin/bash
set -euo pipefail

CHECK_INTERVAL=30
INSTALL_TIMEOUT=3600
CONFIG_FILE="/etc/lsw.conf"
MODIFIED_ISO="windows10_autounattend.iso"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANSIBLE_DIR="$SCRIPT_DIR/.ansible"
ANSIBLE_CFG="$ANSIBLE_DIR/ansible.cfg"
ANSIBLE_INVENTORY="$ANSIBLE_DIR/hosts.ini"
WINDOWS_BOOTSTRAP_PLAYBOOK="$SCRIPT_DIR/ansible/windows-bootstrap.yml"

HOST_USER="${SUDO_USER:-$USER}"
HOST_HOME="$(eval echo "~$HOST_USER")"
if [[ -z "$HOST_HOME" || ! -d "$HOST_HOME" ]]; then
  echo "Не удалось определить домашний каталог пользователя $HOST_USER" >&2
  exit 1
fi

prompt_with_default() {
  local __resultvar=$1
  local __prompt=$2
  local __default=$3
  local __value
  read -r -p "$__prompt [$__default]: " __value
  if [[ -z "$__value" ]]; then
    __value="$__default"
  fi
  printf -v "$__resultvar" '%s' "$__value"
}

prompt_password() {
  local __resultvar=$1
  local __password
  local __confirm
  while true; do
    read -r -s -p "Введите пароль для учетной записи Windows: " __password
    echo
    read -r -s -p "Подтвердите пароль: " __confirm
    echo
    if [[ "$__password" != "$__confirm" ]]; then
      echo "Пароли не совпадают, попробуйте снова." >&2
      continue
    fi
    if [[ -z "$__password" ]]; then
      echo "Пароль не может быть пустым." >&2
      continue
    fi
    printf -v "$__resultvar" '%s' "$__password"
    break
  done
}

if [[ -f "$CONFIG_FILE" ]]; then
  read -r -p "Конфигурационный файл $CONFIG_FILE уже существует. Перезаписать его? [y/N]: " overwrite
  case "$overwrite" in
    [yY][eE][sS]|[yY])
      ;;
    *)
      echo "Используется существующая конфигурация."
      source "$CONFIG_FILE"
      EXISTING_CONFIG=true
      ;;
  esac
fi

if [[ -z "${EXISTING_CONFIG:-}" ]]; then
  VM_NAME_DEFAULT="windows-vm"
  prompt_with_default VM_NAME "Имя виртуальной машины" "$VM_NAME_DEFAULT"

  VM_MEMORY_DEFAULT=4096
  prompt_with_default VM_MEMORY "Объем RAM (МиБ)" "$VM_MEMORY_DEFAULT"

  VM_VCPUS_DEFAULT=2
  prompt_with_default VM_VCPUS "Количество vCPU" "$VM_VCPUS_DEFAULT"

  VM_MAC_DEFAULT="52:54:00:bd:86:21"
  prompt_with_default VM_MAC "MAC-адрес" "$VM_MAC_DEFAULT"

  VM_NETWORK_NAME_DEFAULT="lsw-fixed"
  prompt_with_default VM_NETWORK_NAME "Имя виртуальной сети" "$VM_NETWORK_NAME_DEFAULT"

  VM_BRIDGE_DEFAULT="virbr1"
  prompt_with_default VM_BRIDGE "Имя моста" "$VM_BRIDGE_DEFAULT"

  VM_IP_DEFAULT="192.168.123.10"
  prompt_with_default VM_IP "Фиксированный IP виртуальной машины" "$VM_IP_DEFAULT"

  VM_NETMASK_DEFAULT="255.255.255.0"
  prompt_with_default VM_NETMASK "Маска подсети" "$VM_NETMASK_DEFAULT"

  VM_GATEWAY_DEFAULT="192.168.123.1"
  prompt_with_default VM_GATEWAY "Шлюз" "$VM_GATEWAY_DEFAULT"

  VM_DHCP_START_DEFAULT="192.168.123.2"
  prompt_with_default VM_DHCP_START "Диапазон DHCP (начало)" "$VM_DHCP_START_DEFAULT"

  VM_DHCP_END_DEFAULT="192.168.123.254"
  prompt_with_default VM_DHCP_END "Диапазон DHCP (конец)" "$VM_DHCP_END_DEFAULT"

  VM_DISK_DEFAULT="$HOST_HOME/${VM_NAME}.qcow2"
  prompt_with_default VM_DISK "Путь к диску виртуальной машины" "$VM_DISK_DEFAULT"

  WATCH_DIR_DEFAULT="$HOST_HOME/Downloads"
  prompt_with_default WATCH_DIR "Каталог для мониторинга новых .exe" "$WATCH_DIR_DEFAULT"

  DESKTOP_DIR_DEFAULT="$HOST_HOME/Desktop"
  prompt_with_default DESKTOP_DIR "Каталог для размещения ярлыков" "$DESKTOP_DIR_DEFAULT"

  REMOTE_APPS_DIR_DEFAULT="C:\\LSW\\Apps"
  prompt_with_default REMOTE_APPS_DIR "Путь для хранения приложений в Windows" "$REMOTE_APPS_DIR_DEFAULT"

  RDP_USER_DEFAULT="lswuser"
  prompt_with_default RDP_USER "Имя пользователя Windows" "$RDP_USER_DEFAULT"
  prompt_password RDP_PASS

  sudo truncate -s0 "$CONFIG_FILE"

  write_config_value() {
    local key="$1"
    local value="$2"
    local escaped
    escaped=$(printf '%s' "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '%s="%s"\n' "$key" "$escaped" | sudo tee -a "$CONFIG_FILE" >/dev/null
  }

  write_config_value VM_NAME "$VM_NAME"
  write_config_value VM_MEMORY "$VM_MEMORY"
  write_config_value VM_VCPUS "$VM_VCPUS"
  write_config_value VM_MAC "$VM_MAC"
  write_config_value VM_NETWORK_NAME "$VM_NETWORK_NAME"
  write_config_value VM_BRIDGE "$VM_BRIDGE"
  write_config_value VM_IP "$VM_IP"
  write_config_value VM_NETMASK "$VM_NETMASK"
  write_config_value VM_GATEWAY "$VM_GATEWAY"
  write_config_value VM_DHCP_START "$VM_DHCP_START"
  write_config_value VM_DHCP_END "$VM_DHCP_END"
  write_config_value VM_DISK "$VM_DISK"
  write_config_value WATCH_DIR "$WATCH_DIR"
  write_config_value DESKTOP_DIR "$DESKTOP_DIR"
  write_config_value REMOTE_APPS_DIR "$REMOTE_APPS_DIR"
  write_config_value RDP_USER "$RDP_USER"
  write_config_value RDP_PASS "$RDP_PASS"
  write_config_value PROJECT_DIR "$SCRIPT_DIR"
  unset -f write_config_value
  sudo chmod 600 "$CONFIG_FILE"
  sudo chown "$HOST_USER":"$HOST_USER" "$CONFIG_FILE"
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

mkdir -p "$WATCH_DIR" "$DESKTOP_DIR" "$ANSIBLE_DIR"

export PATH="$HOST_HOME/.local/bin:$PATH"

echo "Установка необходимых пакетов..."
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst virt-manager ansible python3-pip inotify-tools freerdp2-x11
python3 -m pip install --user --upgrade pip >/dev/null 2>&1 || true
python3 -m pip install --user --upgrade pywinrm >/dev/null 2>&1 || true
ansible-galaxy collection install ansible.windows >/dev/null 2>&1 || true

sudo usermod -aG libvirt "$HOST_USER"

if [[ ! -f "$SCRIPT_DIR/$MODIFIED_ISO" ]]; then
  echo "Модифицированный ISO не найден. Запуск create_iso.sh..."
  (cd "$SCRIPT_DIR" && LSW_USERNAME="$RDP_USER" LSW_PASSWORD="$RDP_PASS" ./create_iso.sh)
fi

if [[ ! -f "$SCRIPT_DIR/$MODIFIED_ISO" ]]; then
  echo "Не удалось создать $MODIFIED_ISO" >&2
  exit 1
fi

NETWORK_XML=$(mktemp)
trap 'rm -f "$NETWORK_XML"' EXIT

if ! sudo virsh net-info "$VM_NETWORK_NAME" >/dev/null 2>&1; then
  cat > "$NETWORK_XML" <<EOF_NET
<network>
  <name>$VM_NETWORK_NAME</name>
  <forward mode='nat'/>
  <bridge name='$VM_BRIDGE' stp='on' delay='0'/>
  <ip address='$VM_GATEWAY' netmask='$VM_NETMASK'>
    <dhcp>
      <host mac='$VM_MAC' name='$VM_NAME' ip='$VM_IP'/>
      <range start='$VM_DHCP_START' end='$VM_DHCP_END'/>
    </dhcp>
  </ip>
</network>
EOF_NET
  sudo virsh net-define "$NETWORK_XML"
  sudo virsh net-start "$VM_NETWORK_NAME"
  sudo virsh net-autostart "$VM_NETWORK_NAME"
else
  echo "Сеть $VM_NETWORK_NAME уже существует."
  sudo virsh net-start "$VM_NETWORK_NAME" >/dev/null 2>&1 || true
  sudo virsh net-autostart "$VM_NETWORK_NAME" >/dev/null 2>&1 || true
fi

if [[ ! -f "$VM_DISK" ]]; then
  echo "Создание диска виртуальной машины..."
  qemu-img create -f qcow2 "$VM_DISK" 50G
fi

if ! sudo virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
  echo "Создание виртуальной машины $VM_NAME..."
  sudo virt-install \
    --name "$VM_NAME" \
    --memory "$VM_MEMORY" \
    --vcpus "$VM_VCPUS" \
    --os-type windows \
    --os-variant win10 \
    --network network="$VM_NETWORK_NAME",mac="$VM_MAC" \
    --graphics spice \
    --disk path="$VM_DISK",format=qcow2,bus=virtio \
    --cdrom "$SCRIPT_DIR/$MODIFIED_ISO" \
    --noautoconsole \
    --check path_in_use=off \
    --wait 0
else
  echo "Виртуальная машина $VM_NAME уже существует."
fi

cat > "$ANSIBLE_CFG" <<EOF_CFG
[defaults]
inventory = $ANSIBLE_INVENTORY
host_key_checking = False
retry_files_enabled = False
timeout = 30

[connection]
pipelining = True
EOF_CFG

cat > "$ANSIBLE_INVENTORY" <<EOF_INV
[windows]
$VM_IP

[windows:vars]
ansible_user=$RDP_USER
ansible_password=$RDP_PASS
ansible_connection=winrm
ansible_port=5985
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
EOF_INV

chmod 600 "$ANSIBLE_CFG" "$ANSIBLE_INVENTORY"

export ANSIBLE_CONFIG="$ANSIBLE_CFG"

check_and_start_vm() {
  local state
  state=$(sudo virsh domstate "$VM_NAME" 2>/dev/null || true)
  if [[ "$state" == "shut off" ]]; then
    echo "Виртуальная машина выключена. Запуск..."
    sudo virsh start "$VM_NAME"
  fi
}

wait_for_winrm() {
  echo "Ожидание доступности WinRM (до $(($INSTALL_TIMEOUT / 60)) минут)..."
  local start_time
  start_time=$(date +%s)
  while true; do
    check_and_start_vm
    if ansible windows -i "$ANSIBLE_INVENTORY" -m ansible.windows.win_ping >/dev/null 2>&1; then
      echo "WinRM доступен."
      break
    fi
    local now
    now=$(date +%s)
    if (( now - start_time > INSTALL_TIMEOUT )); then
      echo "Таймаут ожидания WinRM." >&2
      exit 1
    fi
    echo "WinRM пока недоступен, повтор через $CHECK_INTERVAL секунд..."
    sleep "$CHECK_INTERVAL"
  done
}

wait_for_winrm

REMOTE_APPS_DIR="$REMOTE_APPS_DIR" ansible-playbook -i "$ANSIBLE_INVENTORY" "$WINDOWS_BOOTSTRAP_PLAYBOOK"

WINDOWS_SERVICE_PATH="/etc/systemd/system/windows-vm.service"
MONITOR_SERVICE_PATH="/etc/systemd/system/exe-monitor.service"

sudo tee "$WINDOWS_SERVICE_PATH" >/dev/null <<EOF_WINSVC
[Unit]
Description=Windows VM Service
After=network.target
Requires=libvirtd.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/virsh start --domain $VM_NAME --quiet
ExecStop=/usr/bin/virsh shutdown --domain $VM_NAME
ExecStopPost=/bin/sh -c '/usr/bin/virsh domstate $VM_NAME 2>/dev/null | grep -q running && /usr/bin/virsh destroy $VM_NAME'
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF_WINSVC

sudo tee "$MONITOR_SERVICE_PATH" >/dev/null <<EOF_MON
[Unit]
Description=Monitor new Windows executables and deploy them
After=network.target windows-vm.service

[Service]
Type=simple
User=$HOST_USER
Group=$HOST_USER
WorkingDirectory="$SCRIPT_DIR"
Environment="ANSIBLE_CONFIG=$ANSIBLE_CFG"
Environment="PATH=$HOST_HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/bin/env bash "$SCRIPT_DIR/main.sh"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF_MON

sudo systemctl daemon-reload
sudo systemctl enable windows-vm.service
sudo systemctl enable exe-monitor.service
sudo systemctl restart windows-vm.service
sudo systemctl restart exe-monitor.service

sudo systemctl start windows-vm.service >/dev/null 2>&1 || true
sudo systemctl start exe-monitor.service >/dev/null 2>&1 || true

echo "Настройка завершена. Виртуальная машина и службы сконфигурированы."
