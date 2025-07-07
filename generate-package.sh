#!/bin/bash

# Input and output files
INPUT_FILE="changed-files.txt"
PACKAGE_XML="package.xml"
BASE_XML="base-package.xml"

# Create base package.xml with dynamic API version
cat <<EOF > "$BASE_XML"
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
  <version>$API_VERSION</version>
</Package>
EOF

# Copy base to working package.xml
cp "$BASE_XML" "$PACKAGE_XML"

# Metadata folder to type mapping
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

# Function to get metadata type from file path
get_metadata_type() {
  for key in "${!metadata_map[@]}"; do
    if [[ "$1" == *"/$key/"* ]]; then
      echo "${metadata_map[$key]}"
      return
    fi
  done
  echo ""
}

# Function to extract member name from file path
get_member_name() {
  filename=$(basename "$1")
  echo "${filename%%.*}"
}

# Process each file
while read -r file; do
  type=$(get_metadata_type "$file")
  member=$(get_member_name "$file")

  if [[ -n "$type" && -n "$member" ]]; then
    # Check if type already exists
    exists=$(xmlstarlet sel -N x="http://soap.sforce.com/2006/04/metadata" \
      -t -v "count(/x:Package/x:types[x:name='$type'])" "$PACKAGE_XML")

    if [[ "$exists" -eq 0 ]]; then
      # Add new type node
      xmlstarlet ed --inplace \
        -s "/x:Package" -t elem -n "typesTMP" -v "" \
        -s "/x:Package/typesTMP" -t elem -n "members" -v "$member" \
        -s "/x:Package/typesTMP" -t elem -n "name" -v "$type" \
        -r "/x:Package/typesTMP" -v "types" \
        "$PACKAGE_XML"
    else
      # Add member to existing type
      xmlstarlet ed --inplace \
        -s "/x:Package/x:types[x:name='$type']" -t elem -n "members" -v "$member" \
        "$PACKAGE_XML"
    fi
  fi
done < "$INPUT_FILE"

echo "✅ package.xml generated successfully!"
