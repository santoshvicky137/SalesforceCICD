

#!/bin/bash

set -e
set -o pipefail

# === CONFIGURATION ===
PACKAGE_XML="delta/package/package.xml"
BACKUP_DIR="${BACKUP_DIR:-deltabackup}"
ORG_ALIAS="${ORG_ALIAS:-target-org}"  # Allow override via environment variable

# === VALIDATION CHECKS ===
if [[ ! -f "sfdx-project.json" ]]; then
  echo "❌ Missing sfdx-project.json. Not a valid Salesforce DX workspace."
  exit 1
fi

echo "📦 Backing up metadata from org '$ORG_ALIAS'..."
mkdir -p "$BACKUP_DIR"

# === RETRIEVE METADATA ===
if sf project retrieve start \
  --ignore-conflicts \
  --target-org "$ORG_ALIAS" \
  --manifest "$PACKAGE_XML" \
  --output-dir "$BACKUP_DIR"; then
  echo "✅ Backup completed successfully to '$BACKUP_DIR'."
else
  echo "❌ Backup failed while retrieving metadata."
  exit 1
fi
