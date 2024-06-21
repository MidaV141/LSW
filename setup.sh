#!/bin/bash

# Переменные
VM_NAME="windows-vm"
RDP_USER="Administrator"
RDP_PASS="securepassword"
WATCH_DIR="$HOME/Downloads"
SHARE_FOLDER="/mnt/hgfs/SharedFolder"
ISO_PATH="/path/to/windows10.iso"
AUTOUNATTEND_XML="$HOME/autounattend.xml"  # Путь к файлу ответов

# Установка необходимых пакетов
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager sshpass inotify-tools xfreerdp

# Настройка NAT для виртуальной машины
sudo virsh net-define --file - <<EOF
<network>
  <name>default</name>
  <uuid>$(uuidgen)</uuid>
  <forward mode='nat'/>
  <bridge name='virbr0' stp='on' delay='0'/>
  <mac address='52:54:00:xx:xx:xx'/>
  <ip address='192.168.122.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.122.2' end='192.168.122.254'/>
    </dhcp>
  </ip>
</network>
EOF

sudo virsh net-start default
sudo virsh net-autostart default

# Создание файла ответов для автоматической установки Windows 10
cat <<EOF > $AUTOUNATTEND_XML
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SetupUILanguage>
                <UILanguage>en-US</UILanguage>
            </SetupUILanguage>
            <InputLocale>0409:00000409</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <CreatePartition wcm:action="add">
                            <Order>1</Order>
                            <Type>Primary</Type>
                            <Size>100</Size>
                        </CreatePartition>
                        <CreatePartition wcm:action="add">
                            <Order>2</Order>
                            <Type>Primary</Type>
                            <Extend>true</Extend>
                        </CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add">
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Label>System Reserved</Label>
                            <Format>NTFS</Format>
                            <TypeID>0x27</TypeID>
                        </ModifyPartition>
                        <ModifyPartition wcm:action="add">
                            <Order>2</Order>
                            <PartitionID>2</PartitionID>
                            <Label>OS</Label>
                            <Format>NTFS</Format>
                            <Letter>C</Letter>
                        </ModifyPartition>
                    </ModifyPartitions>
                </Disk>
                <WillShowUI>OnError</WillShowUI>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/INDEX</Key>
                            <Value>1</Value>
                        </MetaData>
                    </InstallFrom>
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>2</PartitionID>
                    </InstallTo>
                    <InstallToAvailablePartition>false</InstallToAvailablePartition>
                </OSImage>
            </ImageInstall>
            <UserData>
                <ProductKey>
                    <WillShowUI>Never</WillShowUI>
                </ProductKey>
                <AcceptEula>true</AcceptEula>
                <FullName>User</FullName>
                <Organization>Organization</Organization>
            </UserData>
            <EnableFirewall>false</EnableFirewall>
            <SkipMachineOOBE>true</SkipMachineOOBE>
            <SkipUserOOBE>true</SkipUserOOBE>
        </component>
    </settings>
    <settings pass="specialize">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <ComputerName>WindowsVM</ComputerName>
            <ShowWindowsLive>false</ShowWindowsLive>
            <TimeZone>UTC</TimeZone>
            <RegisteredOwner>User</RegisteredOwner>
            <RegisteredOrganization>Organization</RegisteredOrganization>
            <ProductKey>
                <Key></Key>
            </ProductKey>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <UserAccounts>
                <AdministratorPassword>
                    <Value>$RDP_PASS</Value>
                    <PlainText>true</PlainText>
                </AdministratorPassword>
            </UserAccounts>
            <AutoLogon>
                <Password>
                    <Value>$RDP_PASS</Value>
                    <PlainText>true</Password>
                </Password>
                <Username>$RDP_USER</Username>
                <Enabled>true</Enabled>
            </AutoLogon>
        </component>
    </settings>
</unattend>
EOF

# Создание виртуальной машины
sudo virt-install \
  --name $VM_NAME \
  --os-variant win10 \
  --ram 4096 \
  --vcpus 2 \
  --disk size=40 \
  --cdrom $ISO_PATH \
  --disk path=$AUTOUNATTEND_XML,device=cdrom \
  --network network=default \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole \
  --extra-args 'autoinstall'

# Автоматическое создание ssh ключа
ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa
sudo virsh start $VM_NAME
sleep 30

# Настройка SSH доступа к виртуальной машине
sshpass -p $RDP_PASS ssh-copy-id -o StrictHostKeyChecking=no $RDP_USER@192.168.122.2

# Создание конфигурации systemd для виртуальной машины
sudo bash -c "cat > /etc/systemd/system/windows-vm.service" <<EOF
[Unit]
Description=Windows VM autostart
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/virsh start $VM_NAME
ExecStop=/usr/bin/virsh shutdown $VM_NAME
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Создание конфигурации systemd для мониторинга exe файлов
sudo bash -c "cat > /etc/systemd/system/exe-monitor.service" <<EOF
[Unit]
Description=Monitor new exe files and handle them
After=network.target windows-vm.service

[Service]
Type=simple
ExecStart=/path/to/your/main.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Активировать и запустить службы systemd
sudo systemctl daemon-reload
sudo systemctl enable windows-vm.service
sudo systemctl start windows-vm.service
sudo systemctl enable exe-monitor.service
sudo systemctl start exe-monitor.service

echo "Setup completed successfully!"
