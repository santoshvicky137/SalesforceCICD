#!/bin/bash
set -e
set -o pipefail

# === CONFIGURATION ===
API_VERSION="${API_VERSION:-63.0}"
DELTA_DIR="delta"
PACKAGE_DIR="$DELTA_DIR/package"
PACKAGE_XML="$PACKAGE_DIR/package.xml"
INPUT_FILE="changed-files.txt"
ENVIRONMENT="${ENVIRONMENT:-QA}"  # Default to QA if not passed

# === DETERMINE BASE BRANCH ===
case "$ENVIRONMENT" in
  QA) BASE_BRANCH="origin/QA_Branch" ; ENV_ICON="🔬" ;;
  UAT_Branch) BASE_BRANCH="origin/UAT_Branch" ; ENV_ICON="🧪" ;;
  PreProd_Branch) BASE_BRANCH="origin/PreProd_Branch" ; ENV_ICON="🚦" ;;
  *)
    echo "❌ Unknown environment: $ENVIRONMENT. Aborting."
    exit 1
    ;;
esac

echo "🌍 Environment set to: $ENVIRONMENT"
echo "🔗 Using base branch: $BASE_BRANCH"

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
echo "🔍 Detecting changes from base branch '$BASE_BRANCH'..."
BASE_COMMIT=$(git merge-base "$BASE_BRANCH" HEAD)

if [[ -z "$BASE_COMMIT" ]]; then
  echo "⚠️ Could not determine merge-base. Using HEAD~1 as fallback."
  BASE_COMMIT="HEAD~1"
fi

git diff --name-status "$BASE_COMMIT" HEAD -- 'force-app/**' > "$INPUT_FILE"

# === STEP 2: Exit early if no changes ===
if [[ ! -s "$INPUT_FILE" ]]; then
  echo "🚫 No changes detected in 'force-app/'. Delta is empty ⚠️"
  exit 0
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

# === STEP 5: Generate package.xml using Salesforce CLI ===
echo "📦 Generating package.xml using Salesforce CLI..."
sf project manifest generate \
  --source-dir "$PACKAGE_DIR" \
  --api-version "$API_VERSION"

mv ./package.xml "$PACKAGE_XML"

# === STEP 6: Log included files ===
echo "📜 Files included in delta package:"
find "$PACKAGE_DIR" -type f ! -name "package.xml" | sed "s|^$PACKAGE_DIR/|- |"

# === STEP 7: Final success message ===
echo "✅ Delta package and package.xml generated successfully."

# === STEP 8: Summarize deployment (if supported by runner) ===
if [[ -n "$GITHUB_STEP_SUMMARY" ]]; then
  echo "📝 Writing summary to GitHub step summary..."
  {
    echo "### ${ENV_ICON} Delta Deployment Summary"
    echo "- **Target Environment**: ${ENVIRONMENT}"
    echo "- **Base Branch Used**: ${BASE_BRANCH}"
    echo "- **Merge Base Commit**: ${BASE_COMMIT}"
    echo "- **Run ID**: ${GITHUB_RUN_ID:-N/A}"
    echo "- **Timestamp**: $(date +'%Y-%m-%d %H:%M:%S')"
    echo "- **Metadata Components Deployed:**"
    grep "<name>" "$PACKAGE_XML" | sed 's/ *<[^>]*>//g' | sort | uniq | sed 's/^/- /'
  } >> "$GITHUB_STEP_SUMMARY"
else
  echo "⚠️ GITHUB_STEP_SUMMARY not set. Skipping summary output."
fi