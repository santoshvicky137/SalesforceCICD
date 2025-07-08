#!/bin/bash

PACKAGE_XML="delta/package/package.xml"
BACKUP_DIR="deltabackup"
ORG_ALIAS="target-org"

[[ ! -f "$PACKAGE_XML" ]] && echo "❌ package.xml not found." && exit 1

echo "📦 Backing up metadata from org '$ORG_ALIAS'..."
mkdir -p "$BACKUP_DIR"

sf project retrieve start \
  --target-org "$ORG_ALIAS" \
  --manifest "$PACKAGE_XML" \
  --output-dir "$BACKUP_DIR"

[[ $? -eq 0 ]] && echo "✅ Backup complete." || echo "❌ Backup failed."
