#!/bin/bash
set -e
set -o pipefail

# === CONFIGURATION ===
API_VERSION="${API_VERSION:-63.0}"
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

# === STEP 1: Detect changed files ===
echo "🔍 Detecting changes in 'force-app/'..."
if ! git rev-parse HEAD~1 > /dev/null 2>&1; then
  echo "⚠️ No previous commit found. Cannot compare changes."
  echo "" > "$INPUT_FILE"
else
  git diff --name-status HEAD~1 HEAD -- 'force-app/**' > "$INPUT_FILE"
fi

# === STEP 2: Exit early if no changes ===
if [[ ! -s "$INPUT_FILE" ]]; then
  echo "🚫 No changes are detected in 'force-app/' folder. Delta is empty ⚠️ running dry steps to complete pipeline flow. 🚫 No deployment will occur."
  exit 1
fi

# === STEP 3: Prepare delta folder ===
echo "🧹 Cleaning delta folder..."
rm -rf "$DELTA_DIR"
mkdir -p "$PACKAGE_DIR"

# === STEP 4: Copy changed metadata files ===
echo "📁 Copying changed metadata files..."
while read -r status file; do
  [[ "$status" == "D" ]] && continue
  [[ ! -f "$file" ]] && continue
  dest="$PACKAGE_DIR/$file"
  mkdir -p "$(dirname "$dest")"
  cp "$file" "$dest"
done < "$INPUT_FILE"

# === STEP 5: Generate package.xml using sf CLI ===
echo "📦 Generating package.xml using Salesforce CLI...and current path is : $(pwd)"
sf project manifest generate \
  --source-dir "$PACKAGE_DIR" \
  --api-version "$API_VERSION"
  
# === STEP 6: Log included files ===
echo "📜 Files included in delta package:"
find "$PACKAGE_DIR" -type f ! -name "package.xml" | sed "s|^$PACKAGE_DIR/|- |"

# === STEP 7: Final success message (only if delta was created) ===
if [[ -s "$INPUT_FILE" ]] && find "$PACKAGE_DIR" -type f ! -name "package.xml" | grep -q .; then
  echo "✅ Delta package and package.xml generated successfully."
fi
