#!/bin/bash

# === CONFIGURATION ===
API_VERSION="60.0"
DELTA_DIR="delta"
PACKAGE_DIR="$DELTA_DIR/package"
PACKAGE_XML="$PACKAGE_DIR/package.xml"
INPUT_FILE="changed-files.txt"
ORG_ALIAS="target-org"

# === STEP 1: Clean and prepare delta folder ===
echo "🧹 Cleaning delta folder..."
rm -rf "$DELTA_DIR"
mkdir -p "$PACKAGE_DIR"

# === STEP 2: Get changed files from Git ===
echo "🔍 Detecting changed files..."
git diff --name-status HEAD~1 HEAD > "$INPUT_FILE"

# === STEP 3: Create base package.xml ===
cat <<EOF > "$PACKAGE_XML"
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
  <version>$API_VERSION</version>
</Package>
EOF

# === STEP 4: Metadata folder to type mapping ===
declare -A metadata_map=(
  ["classes"]="ApexClass"
  ["triggers"]="ApexTrigger"
  ["objects"]="CustomObject"
  ["layouts"]="Layout"
  ["permissionsets"]="PermissionSet"
  ["profiles"]="Profile"
  ["tabs"]="CustomTab"
  ["staticresources"]="StaticResource"
  ["labels"]="CustomLabels"
  ["flows"]="Flow"
  ["aura"]="AuraDefinitionBundle"
  ["lwc"]="LightningComponentBundle"
)

# === STEP 5: Helper functions ===
get_metadata_type() {
  for key in "${!metadata_map[@]}"; do
    if [[ "$1" == *"/$key/"* ]]; then
      echo "${metadata_map[$key]}"
      return
    fi
  done
  echo ""
}

get_member_name() {
  filename=$(basename "$1")
  echo "${filename%%.*}"
}

copy_metadata_file() {
  local file="$1"
  local dest="$PACKAGE_DIR/$file"
  mkdir -p "$(dirname "$dest")"
  cp "$file" "$dest"

  # Copy -meta.xml if it exists
  if [[ -f "$file-meta.xml" ]]; then
    cp "$file-meta.xml" "$PACKAGE_DIR/$file-meta.xml"
  fi

  # For aura/lwc, copy entire bundle folder
  if [[ "$file" == *"/aura/"* || "$file" == *"/lwc/"* ]]; then
    bundle_dir=$(dirname "$file")
    cp -r "$bundle_dir" "$PACKAGE_DIR/$(dirname "$file")/../"
  fi
}

# === STEP 6: Process changed files ===
echo "📦 Copying metadata and building package.xml..."
while read -r status file; do
  [[ "$status" == "D" ]] && continue  # Skip deleted files

  type=$(get_metadata_type "$file")
  member=$(get_member_name "$file")

  if [[ -n "$type" && -n "$member" ]]; then
    copy_metadata_file "$file"

    exists=$(xmlstarlet sel -N x="http://soap.sforce.com/2006/04/metadata" \
      -t -v "count(/x:Package/x:types[x:name='$type'])" "$PACKAGE_XML")

    if [[ "$exists" -eq 0 ]]; then
      xmlstarlet ed --inplace \
        -s "/x:Package" -t elem -n "typesTMP" -v "" \
        -s "/x:Package/typesTMP" -t elem -n "members" -v "$member" \
        -s "/x:Package/typesTMP" -t elem -n "name" -v "$type" \
        -r "/x:Package/typesTMP" -v "types" \
        "$PACKAGE_XML"
    else
      xmlstarlet ed --inplace \
        -s "/x:Package/x:types[x:name='$type']" -t elem -n "members" -v "$member" \
        "$PACKAGE_XML"
    fi
  fi
done < "$INPUT_FILE"

# === STEP 7: Deploy the delta ===
echo "🚀 Deploying delta to org '$ORG_ALIAS'..."
sf project deploy start -x "$PACKAGE_XML" --target-org "$ORG_ALIAS"

# === STEP 8: Clean up ===
if [[ $? -eq 0 ]]; then
  echo "🧹 Cleaning up delta folder after successful deployment..."
  rm -rf "$DELTA_DIR"
  echo "✅ Deployment complete and delta cleaned up."
else
  echo "❌ Deployment failed. Delta folder retained for inspection."
fi
