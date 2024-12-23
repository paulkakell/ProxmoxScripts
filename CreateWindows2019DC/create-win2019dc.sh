#!/usr/bin/env bash
#
# create-win2019dc-interactive.sh
#
# This script prompts the user for configuration details
# and then creates an unattended Windows 2019 Core VM on Proxmox,
# which will be promoted to a Domain Controller.

set -e  # Exit immediately if any command fails

#################################
# 1) Collect user input interactively
#################################

read -p "Enter VM ID (e.g. 999): " VMID

read -p "Enter FQDN of existing domain (e.g. MYDOMAIN.LOCAL): " DOMAIN_FQDN

read -p "Enter NetBIOS name of the domain (e.g. MYDOMAIN): " DOMAIN_NETBIOS

# Prompt for password without echo:
read -s -p "Enter Domain/Administrator password: " ADMIN_PASSWORD
echo  # just to move to the next line after user input

read -p "Enter Proxmox storage for the main disk (e.g. local-lvm): " STORAGE

read -p "Enter path to Windows Server 2019 ISO in Proxmox (e.g. local:iso/Win2019.iso): " WIN_ISO

read -p "Enter path to VirtIO drivers ISO [optional, press Enter to skip] (e.g. local:iso/virtio-win.iso): " VIRTIO_ISO

echo "==============================================="
echo "       Summary of user-provided values         "
echo "==============================================="
echo "VM ID:                $VMID"
echo "Domain FQDN:          $DOMAIN_FQDN"
echo "Domain NetBIOS:       $DOMAIN_NETBIOS"
echo "Storage:              $STORAGE"
echo "Windows ISO:          $WIN_ISO"
echo "VirtIO ISO:           $VIRTIO_ISO"
echo "==============================================="
echo "Press Enter to continue, or Ctrl+C to cancel..."
read -r  # pause for user confirmation

#################################
# 2) Create temporary directory for unattend
#################################
TMP_DIR="/tmp/win2019-autounattend-$VMID"
mkdir -p "$TMP_DIR"

#################################
# 3) Generate unattend.xml
#################################
cat > "$TMP_DIR/unattend.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <!-- windowsPE, specialize, oobeSystem passes, etc. -->
  <settings pass="windowsPE">
    <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="en-US" versionScope="nonSxS">
      <SetupUILanguage>
        <UILanguage>en-US</UILanguage>
      </SetupUILanguage>
      <InputLocale>en-US</InputLocale>
      <SystemLocale>en-US</SystemLocale>
      <UILanguage>en-US</UILanguage>
      <UserLocale>en-US</UserLocale>
    </component>
    <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <DiskConfiguration>
        <Disk wcm:action="add" wcm:keyValue="1">
          <CreatePartitions>
            <CreatePartition wcm:action="add">
              <Order>1</Order>
              <Type>Primary</Type>
              <Size>500</Size>
            </CreatePartition>
            <CreatePartition wcm:action="add">
              <Order>2</Order>
              <Type>Primary</Type>
              <Extend>true</Extend>
            </CreatePartition>
          </CreatePartitions>
          <ModifyPartitions>
            <ModifyPartition wcm:action="add">
              <Active>true</Active>
              <Format>FAT32</Format>
              <Label>System</Label>
              <Order>1</Order>
              <PartitionID>1</PartitionID>
            </ModifyPartition>
            <ModifyPartition wcm:action="add">
              <Format>NTFS</Format>
              <Label>Windows</Label>
              <Order>2</Order>
              <PartitionID>2</PartitionID>
            </ModifyPartition>
          </ModifyPartitions>
          <WillWipeDisk>true</WillWipeDisk>
        </Disk>
      </DiskConfiguration>
      <ImageInstall>
        <OSImage>
          <InstallFrom>
            <!-- Index for "Windows Server 2019 SERVERCORE" image -->
            <MetaData wcm:action="add">
              <Key>/IMAGE/NAME</Key>
              <Value>Windows Server 2019 SERVERCORE</Value>
            </MetaData>
          </InstallFrom>
          <InstallTo>
            <DiskID>1</DiskID>
            <PartitionID>2</PartitionID>
          </InstallTo>
          <InstallToAvailablePartition>false</InstallToAvailablePartition>
        </OSImage>
      </ImageInstall>
      <UserData>
        <AcceptEula>true</AcceptEula>
        <FullName>Administrator</FullName>
        <Organization>MyOrg</Organization>
      </UserData>
    </component>
  </settings>

  <settings pass="specialize">
    <component name="Microsoft-Windows-ServerCore" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <DisplayShell>false</DisplayShell>
    </component>
    <component name="Microsoft-Windows-UnattendedJoin" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
      <Identification>
        <Credentials>
          <Domain>${DOMAIN_FQDN}</Domain>
          <Password>${ADMIN_PASSWORD}</Password>
          <Username>Administrator</Username>
        </Credentials>
        <JoinDomain>${DOMAIN_FQDN}</JoinDomain>
        <MachineName>WIN2019DC</MachineName>
      </Identification>
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
      <AutoLogon>
        <Password>
          <Value>${ADMIN_PASSWORD}</Value>
          <PlainText>true</PlainText>
        </Password>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
        <Username>Administrator</Username>
      </AutoLogon>
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <NetworkLocation>Work</NetworkLocation>
        <ProtectYourPC>1</ProtectYourPC>
      </OOBE>
      <RegisteredOwner>MyOrg</RegisteredOwner>
      <TimeZone>UTC</TimeZone>
      <EnableOEMRegistration>false</EnableOEMRegistration>
      <EnableOEMUpgrade>false</EnableOEMUpgrade>
      <UserAccounts>
        <AdministratorPassword>
          <Value>${ADMIN_PASSWORD}</Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
    </component>
  </settings>

  <cpi:offlineImage
    xmlns:cpi="urn:schemas-microsoft-com:cpi"
    xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    wcm:path="windowsPE" wcm:scope="IMAGE">
  </cpi:offlineImage>
</unattend>
EOF

#################################
# 4) Create PowerShell finalize script
#################################
cat > "$TMP_DIR/Finalize-DC-Promotion.ps1" <<'EOS'
# Finalize-DC-Promotion.ps1
# This script runs after first logon to:
#  1. Install AD-Domain-Services
#  2. Promote to Domain Controller
#  3. Set DSRM password
#  4. Reboot

$ErrorActionPreference = "Stop"

$domain = $env:USERDOMAIN
Write-Host "Detected domain: $domain"

# The Administrator password is stored as an environment variable in unattend.xml
$adminPassword = ConvertTo-SecureString -String "$env:ADMIN_PASSWORD" -AsPlainText -Force

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Import-Module ADDSDeployment

Install-ADDSDomainController `
  -Credential (New-Object System.Management.Automation.PSCredential("Administrator", $adminPassword)) `
  -DomainName $domain `
  -InstallDns `
  -SafeModeAdministratorPassword (ConvertTo-SecureString "$env:ADMIN_PASSWORD" -AsPlainText -Force) `
  -Force:$true

# System reboots automatically after DC promotion
EOS

#################################
# 5) Create an ISO with unattend.xml + finalize script
#################################
AUTOUNATTEND_ISO="/var/lib/vz/template/iso/win2019-unattend-$VMID.iso"

if [ -f "$AUTOUNATTEND_ISO" ]; then
  rm -f "$AUTOUNATTEND_ISO"
fi

genisoimage \
  -o "$AUTOUNATTEND_ISO" \
  -volid "WIN_UNATTEND" \
  -iso-level 2 \
  -J -R -D \
  "$TMP_DIR"

#################################
# 6) Create and configure the VM
#################################
echo "Creating VM (ID: $VMID)..."
qm create "$VMID" \
  --name "win2019dc" \
  --memory 4096 \
  --cores 2 \
  --sockets 1 \
  --net0 virtio,bridge=vmbr0 \
  --ostype win10 \
  --scsihw virtio-scsi-pci \
  --agent 1

# Add a disk (size 50G as an example)
qm set "$VMID" --scsi0 "${STORAGE}:50"

# Attach the main Windows ISO
qm set "$VMID" --cdrom "$WIN_ISO"

# Optionally attach the VirtIO drivers ISO
if [ -n "$VIRTIO_ISO" ]; then
  qm set "$VMID" --ide2 "$VIRTIO_ISO"
fi

# Attach the autounattend ISO
qm set "$VMID" --sata0 "$AUTOUNATTEND_ISO",media=cdrom

# Set boot order (boot from the disk after installation)
qm set "$VMID" --boot c --bootdisk scsi0

#################################
# 7) Start the VM
#################################
qm start "$VMID"

echo "==============================================="
echo "VM $VMID created and started."
echo "Windows will install & configure itself as a DC."
echo "==============================================="
