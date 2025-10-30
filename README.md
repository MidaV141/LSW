# LSW

## Назначение

Проект автоматизирует установку Windows 10 в виртуальной машине KVM/QEMU и обеспечивает доставку новых `.exe` файлов с хоста Linux на гостевую Windows. Обнаруженные приложения копируются через WinRM, запускаются средствами PowerShell и получают ярлыки для быстрого подключения по RDP.

Основные возможности:

* автоматическое создание модифицированного установочного ISO с `autounattend.xml`;
* развёртывание изолированной NAT-сети libvirt с фиксированным IP для виртуальной машины;
* ожидание готовности WinRM и начальная настройка Windows через Ansible (включение RDP, открытие брандмауэра и подготовка каталога приложений);
* мониторинг каталога загрузок на хосте и доставка новых `.exe` в Windows с последующим запуском и созданием ярлыка на рабочем столе Linux;
* юниты systemd для автоматического старта виртуальной машины и фонового мониторинга.

## Требования

* Linux (Ubuntu/Debian) с поддержкой виртуализации KVM;
* пользователь, имеющий права на запуск `sudo`;
* установочный образ Windows 10 (`windows10.iso`) в корне репозитория.

Скрипт установки самостоятельно установит следующие пакеты: `qemu-kvm`, `libvirt-daemon-system`, `libvirt-clients`, `bridge-utils`, `virtinst`, `virt-manager`, `ansible`, `python3-pip`, `inotify-tools`, `freerdp2-x11`. Дополнительно через `pip` устанавливается библиотека `pywinrm`.

## Установка

1. Склонируйте репозиторий и поместите оригинальный ISO Windows 10 в файл `windows10.iso` рядом с `setup.sh`:

   ```bash
   git clone https://github.com/username/project-name.git
   cd project-name
   ```

2. Запустите сценарий развёртывания:

   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

   Скрипт:
   * запросит имя/пароль локального пользователя Windows и параметры сети виртуальной машины;
   * сохранит настройки в `/etc/lsw.conf` (файл создаётся с правами `600` и принадлежит текущему пользователю);
   * при отсутствии модифицированного ISO вызовет `create_iso.sh`, подставив указанные учётные данные в шаблон `autounattend.xml`;
   * настроит сеть libvirt, создаст диск и определит виртуальную машину;
   * дождётся доступности WinRM и выполнит плейбук `ansible/windows-bootstrap.yml`, включающий RDP и открывающий брандмауэр;
   * создаст и активирует сервисы systemd `windows-vm.service` и `exe-monitor.service`.

## Конфигурация

* `/etc/lsw.conf` — основные параметры: имя ВМ, сетевые адреса, пути каталогов и учётные данные Windows. Этот файл используется как `source` в других скриптах и должен иметь права `600`.
* `ansible/` — плейбуки Ansible:
  * `windows-bootstrap.yml` включает WinRM/RDP и создаёт каталог `C:\LSW\Apps`.
  * `deploy-app.yml` копирует очередной `.exe` на гостя и запускает его через `Start-Process`.
* `.ansible/hosts.ini` и `.ansible/ansible.cfg` — создаются `setup.sh` для подключения к Windows по WinRM.

## Работа мониторинга

`main.sh` подписывается на события `inotify` в каталоге `WATCH_DIR` (по умолчанию `~/Downloads`). Каждый новый `.exe`:

1. передаётся в Windows плейбуком `ansible/deploy-app.yml`;
2. запускается через WinRM (PowerShell `Start-Process`);
3. получает ярлык `.desktop` в каталоге `DESKTOP_DIR` (по умолчанию `~/Desktop`) с командой `xfreerdp` для быстрого подключения к виртуальной машине.

Скрипт использует параметры из `/etc/lsw.conf`, поэтому при смене пароля или сетевых настроек обновите конфигурацию и перезапустите службы:

```bash
sudo systemctl restart windows-vm.service exe-monitor.service
```

## Обслуживание служб

* `windows-vm.service` — однократный запуск/корректное завершение виртуальной машины через `virsh` с тайм-аутом и жёстким выключением при зависании.
* `exe-monitor.service` — выполняет `main.sh` от имени указанного пользователя. В примере из `systemd/exe-monitor.service` используется шаблон `exe-monitor@username.service`.

Проверка статуса:

```bash
sudo systemctl status windows-vm.service
sudo systemctl status exe-monitor@username.service
```

## Обновление

При изменении скриптов перезапустите службу мониторинга:

```bash
sudo systemctl restart exe-monitor@username.service
```

Перед повторным запуском `setup.sh` при необходимости удалите или обновите `/etc/lsw.conf`.
