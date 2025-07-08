#!/bin/bash

API_VERSION="60.0"
DELTA_DIR="delta"
PACKAGE_DIR="$DELTA_DIR/package"
PACKAGE_XML="$PACKAGE_DIR/package.xml"
INPUT_FILE="changed-files.txt"

echo "🔍 Generating Git diff..."
git diff --name-status HEAD~1 HEAD > "$INPUT_FILE"

echo "🧹 Preparing delta folder..."
rm -rf "$DELTA_DIR"
mkdir -p "$PACKAGE_DIR"

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

get_metadata_type() {
  for key in "${!metadata_map[@]}"; do
    [[ "$1" == *"/$key/"* ]] && echo "${metadata_map[$key]}" && return
  done
  echo ""
}

get_member_name() {
  basename "$1" | cut -d. -f1
}

copy_metadata_file() {
  local file="$1"
  local dest="$PACKAGE_DIR/$file"
  mkdir -p "$(dirname "$dest")"
  cp "$file" "$dest"
  [[ -f "$file-meta.xml" ]] && cp "$file-meta.xml" "$PACKAGE_DIR/$file-meta.xml"
  [[ "$file" == *"/aura/"* || "$file" == *"/lwc/"* ]] && cp -r "$(dirname "$file")" "$PACKAGE_DIR/$(dirname "$file")/../"
}

echo "📦 Creating package.xml..."
cat <<EOF > "$PACKAGE_XML"
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
  <version>$API_VERSION</version>
</Package>
EOF

while read -r status file; do
  [[ "$status" == "D" ]] && continue
  [[ ! -f "$file" ]] && continue
  type=$(get_metadata_type "$file")
  member=$(get_member_name "$file")
  [[ -z "$type" || -z "$member" ]] && continue

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
done < "$INPUT_FILE"

echo "✅ Delta and package.xml generated."
