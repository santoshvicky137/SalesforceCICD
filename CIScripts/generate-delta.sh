#!/bin/bash
set -e
set -o pipefail

# === CONFIGURATION ===
API_VERSION="${API_VERSION:-60.0}"
DELTA_DIR="delta"
PACKAGE_DIR="$DELTA_DIR/package"
PACKAGE_XML="$PACKAGE_DIR/package.xml"
INPUT_FILE="changed-files.txt"

# === SAFETY CHECK ===
echo "📂 Current directory: $(pwd)"
ls -la

export GIT_DIR="$(pwd)/.git"
export GIT_WORK_TREE="$(pwd)"

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "❌ Not inside a Git repository. Delta generation aborted."
  exit 1
fi

echo "🔍 Detecting changes in 'force-app/'..."
if ! git rev-parse HEAD~1 > /dev/null 2>&1; then
  echo "⚠️ No previous commit found. Cannot compare changes. Executing dry steps."
  echo "" > "$INPUT_FILE"
else
  git diff --name-status HEAD~1 HEAD -- 'force-app/**' > "$INPUT_FILE"
fi

# === EXIT EARLY IF NO CHANGES DETECTED ===
if [[ ! -s "$INPUT_FILE" ]]; then
  echo "🚫 No changes are detected in 'force-app/' folder. Delta is empty ⚠️ running dry steps to complete pipeline flow. 🚫 No deployment will occur."
  exit 1
fi

# === STEP 1: Clean and prepare delta folder ===
echo "🧹 Cleaning delta folder..."
rm -rf "$DELTA_DIR"
mkdir -p "$PACKAGE_DIR"

# === STEP 2: Metadata folder to type mapping ===
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

  # Copy -meta.xml if it exists
  [[ -f "$file-meta.xml" ]] && cp "$file-meta.xml" "$PACKAGE_DIR/$file-meta.xml"

  # Copy entire bundle for aura/lwc
  if [[ "$file" == *"/aura/"* || "$file" == *"/lwc/"* ]]; then
    bundle_dir=$(dirname "$file")
    cp -r "$bundle_dir" "$PACKAGE_DIR/$(dirname "$file")/../"
  fi
}

# === STEP 3: Create base package.xml ===
echo "📦 Creating package.xml..."
cat <<EOF > "$PACKAGE_XML"
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
  <version>$API_VERSION</version>
</Package>
EOF

# === STEP 4: Process changed files ===
echo "📁 Processing changed metadata files..."
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

echo "✅ Delta package and package.xml generated successfully."
