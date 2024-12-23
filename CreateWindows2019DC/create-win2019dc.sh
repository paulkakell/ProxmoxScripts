#!/usr/bin/env bash
#
# create-win2019dc.sh
#
# This script references config.sh for variables.
#

# 1) Source the config file (make sure config.sh is in the same directory, or specify the path).
if [ -f ./config.sh ]; then
    source ./config.sh
else
    echo "config.sh not found! Please create one (see example config.sh)."
    exit 1
fi

# 2) Basic argument checks or direct usage from config.sh
if [ -z "$VMID" ] || [ -z "$DOMAIN_FQDN" ] || [ -z "$DOMAIN_NETBIOS" ] || [ -z "$ADMIN_PASSWORD" ] || [ -z "$STORAGE" ] || [ -z "$WIN_ISO" ]; then
  echo "Some required variables are missing. Please check config.sh!"
  exit 1
fi

# 3) Create a temporary directory for unattend files
TMP_DIR="/tmp/win2019-autounattend-$VMID"
mkdir -p "$TMP_DIR"

# 4) Generate unattend.xml
cat > "$TMP_DIR/unattend.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <!-- (rest of unattend.xml content) -->
  <!-- 
  Use your variables like ${DOMAIN_FQDN}, ${ADMIN_PASSWORD}, etc.
  Example: 
  <JoinDomain>${DOMAIN_FQDN}</JoinDomain>
  <Password>${ADMIN_PASSWORD}</Password>
  -->
</unattend>
EOF

# 5) Create your finalize script
cat > "$TMP_DIR/Finalize-DC-Promotion.ps1" <<'EOS'
# ...
EOS

# 6) Create the autounattend ISO
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

# 7) Create the VM
qm create "$VMID" \
  --name "win2019dc" \
  --memory 4096 \
  --cores 2 \
  --sockets 1 \
  --net0 virtio,bridge=vmbr0 \
  --ostype win10 \
  --scsihw virtio-scsi-pci \
  --agent 1

# 8) Add disk, attach ISOs, boot, etc.
qm set "$VMID" --scsi0 "$STORAGE:50"
qm set "$VMID" --cdrom "$WIN_ISO"

if [ -n "$VIRTIO_ISO" ]; then
  qm set "$VMID" --ide2 "$VIRTIO_ISO"
fi

qm set "$VMID" --sata0 "$AUTOUNATTEND_ISO",media=cdrom
qm set "$VMID" --boot c --bootdisk scsi0

# 9) Start the VM
qm start "$VMID"

echo "VM $VMID created and started. Windows installation + DC promotion will proceed unattended."
