#!/bin/bash

# === CONFIGURATION ===
PACKAGE_XML="delta/package.xml"
BACKUP_DIR="deltabackup"
ORG_ALIAS="ci-org"  # Change this to your target org alias

# === VALIDATION ===
if [[ ! -f "$PACKAGE_XML" ]]; then
  echo "❌ package.xml not found at $PACKAGE_XML"
  exit 1
fi

# === BACKUP ===
echo "📦 Backing up metadata from org '$ORG_ALIAS' using $PACKAGE_XML..."
mkdir -p "$BACKUP_DIR"

sf project retrieve start \
  --target-org "$ORG_ALIAS" \
  --manifest "$PACKAGE_XML" \
  --output-dir "$BACKUP_DIR"

if [[ $? -eq 0 ]]; then
  echo "✅ Backup completed successfully. Files saved to $BACKUP_DIR"
else
  echo "❌ Backup failed."
  exit 1
fi
