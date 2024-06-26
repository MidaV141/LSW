# LSW

## Описание проекта

Этот проект предназначен для запуска программ Windows внутри виртуальной машины на операционной системе Linux, с возможностью автоматического переноса и запуска программ Windows, а также отображения их окон на хостовой Linux системе. Основная цель проекта - обеспечить бесшовную интеграцию между программами, предназначенными для разных операционных систем, облегчая их совместное использование.

## Функции и возможности

* Автоматическая установка Windows 10 в виртуальной машине с использованием QEMU/KVM.
* Автоматический запуск виртуальной машины с Windows при старте системы.
* Мониторинг загрузок новых файлов .exe на хостовой машине и автоматический перенос их на виртуальную машину.
* Автоматическое создание ярлыков на хостовой машине для запуска Windows программ.
* Отображение окон Windows программ на хостовой Linux системе через RDP.
* Использование общей папки для обмена файлами между хостовой и виртуальной машинами.

## Установка и настройка

### Требования

Операционная система Linux (Ubuntu/Debian)
Установленные пакеты: `qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager sshpass inotify-tools xfreerdp`

### Шаги установки

Клонирование репозитория

```bash
git clone https://github.com/username/project-name.git
cd project-name
```

Запуск скрипта установки

```bash
chmod +x setup.sh
./setup.sh
```

Скрипт установки выполнит следующие действия:

1. Установит необходимые пакеты.
2. Настроит сеть NAT для виртуальной машины.
3. Создаст файл ответов для автоматической установки Windows.
4. Создаст и запустит виртуальную машину с Windows.
5. Настроит SSH доступ к виртуальной машине.
6. Создаст и активирует службы systemd для автоматического запуска виртуальной машины и мониторинга новых файлов.
7. Запуск основного скрипта

```bash
chmod +x main.sh
./main.sh
```

Этот скрипт будет следить за новыми .exe файлами в каталоге загрузок и автоматически переносить их на виртуальную машину, создавая соответствующие ярлыки на рабочем столе.

### Конфигурационные файлы

windows-vm.service  
Этот файл systemd службы отвечает за автоматический запуск и остановку виртуальной машины.

```ini
[Unit]
Description=Windows VM autostart
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/virsh start windows-vm
ExecStop=/usr/bin/virsh shutdown windows-vm
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```
exe-monitor.service
Этот файл systemd службы отвечает за мониторинг новых exe файлов и их обработку.

```ini
[Unit]
Description=Monitor new exe files and handle them
After=network.target windows-vm.service

[Service]
Type=simple
ExecStart=/path/to/your/main.sh
Restart=always

[Install]
WantedBy=multi-user.target
```

## Использование

### Мониторинг новых программ

После установки и запуска службы мониторинга, любой новый .exe файл, загруженный в каталог Downloads на хостовой машине, будет автоматически перенесен на виртуальную машину и установлен.

### Запуск программ

Ярлыки для новых программ будут автоматически созданы на рабочем столе хостовой машины. Для запуска программы, просто дважды щелкните на ярлык, и программа откроется в окне на вашей Linux системе.

## Технические детали

### Структура проекта

`setup.sh`: Скрипт для установки и настройки всех необходимых компонентов.  
`main.sh`: Скрипт для основной работы программы, включая мониторинг и обработку новых   exe файлов.
`autounattend.xml`: Файл ответов для автоматической установки Windows 10.  
`windows-vm.service`: Файл конфигурации systemd для автоматического запуска виртуальной машины.  
`exe-monitor.service`: Файл конфигурации systemd для мониторинга и обработки exe файлов.  

### Переменные и пути  

`VM_NAME`: Имя виртуальной машины.  
`RDP_USER`: Имя пользователя для RDP.  
`RDP_PASS`: Пароль для RDP.  
`WATCH_DIR`: Каталог для мониторинга новых exe файлов.  
`SHARE_FOLDER`: Общая папка для обмена файлами между хостовой и виртуальной машинами.  
`ISO_PATH`: Путь к образу ISO Windows 10.  
`AUTOUNATTEND_XML`: Путь к файлу ответов для автоматической установки Windows.  
