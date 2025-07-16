#!/bin/bash
set -e
set -o pipefail

# === CONFIGURATION ===
API_VERSION="${API_VERSION:-63.0}"
DELTA_DIR="delta"
PACKAGE_DIR="$DELTA_DIR/package"
PACKAGE_XML="$PACKAGE_DIR/package.xml"
DESTRUCTIVE_XML="$DELTA_DIR/destructiveChanges.xml"
INPUT_FILE="changed-files.txt"
DELETIONS_FILE="deleted-files.txt"
ENVIRONMENT="${ENVIRONMENT:-QA}"  # Default to QA
FALLBACK_DEPTH="${FALLBACK_DEPTH:-3}" # Used if no base found

# === DETERMINE BASE BRANCH ===
case "$ENVIRONMENT" in
  QA) BASE_BRANCH="origin/QA_Branch"; ENV_ICON="🔬" ;;
  UAT_Branch) BASE_BRANCH="origin/UAT_Branch"; ENV_ICON="🧪" ;;
  PreProd_Branch) BASE_BRANCH="origin/PreProd_Branch"; ENV_ICON="🚦" ;;
  *)
    echo "❌ Unknown environment: $ENVIRONMENT. Aborting."
    exit 1
    ;;
esac

echo "🌍 Environment: $ENVIRONMENT"
echo "🔗 Base Branch: $BASE_BRANCH"

export GIT_DIR="$(pwd)/.git"
export GIT_WORK_TREE="$(pwd)"

# === SAFETY CHECK ===
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "❌ Not inside a Git repository. Aborting."
  exit 1
fi

# === STEP 1: Determine delta range ===
USE_LAST_SHA=false
if [[ "$ENVIRONMENT" == "QA" || "$ENVIRONMENT" == "UAT_Branch" || "$ENVIRONMENT" == "PreProd_Branch" ]]; then
  if [[ -f temp-sha/.last-deploy-sha ]]; then
    BASE_COMMIT=$(cat temp-sha/.last-deploy-sha)
    echo "✅ Using previous deploy SHA: $BASE_COMMIT"
    USE_LAST_SHA=true
  else
    echo "⚠️ No previous deploy SHA found. Fallback to HEAD~${FALLBACK_DEPTH}"
    BASE_COMMIT="HEAD~${FALLBACK_DEPTH}"
  fi
else
  BASE_COMMIT=$(git merge-base "$BASE_BRANCH" HEAD)
  if [[ -z "$BASE_COMMIT" ]]; then
    echo "⚠️ Merge-base unavailable. Fallback to HEAD~${FALLBACK_DEPTH}"
    BASE_COMMIT="HEAD~${FALLBACK_DEPTH}"
  fi
fi

RANGE="${BASE_COMMIT}..HEAD"
echo "📊 Diff range: $RANGE"
git diff --name-status $RANGE -- 'force-app/**' > "$INPUT_FILE"

echo "📋 Changed files:"
cat "$INPUT_FILE" || echo "None"

# === STEP 2: Exit early if no changes ===
if [[ ! -s "$INPUT_FILE" ]]; then
  echo "🚫 No changes detected. Exiting cleanly."
  exit 0
fi

# === STEP 3: Prepare delta directory ===
echo "🧹 Preparing delta structure..."
rm -rf "$DELTA_DIR"
mkdir -p "$PACKAGE_DIR"

# === STEP 4: Copy modified files ===
> "$DELETIONS_FILE"
while read -r status file; do
  if [[ "$status" == "D" ]]; then
    echo "$file" >> "$DELETIONS_FILE"
    continue
  fi
  [[ ! -f "$file" ]] && continue
  dest="$PACKAGE_DIR/$file"
  mkdir -p "$(dirname "$dest")"
  cp "$file" "$dest"
done < "$INPUT_FILE"

# === STEP 5: Generate package.xml ===
echo "📦 Generating package.xml..."
sf project manifest generate \
  --source-dir "$PACKAGE_DIR" \
  --api-version "$API_VERSION"

mv ./package.xml "$PACKAGE_XML"

# === STEP 6: Build destructiveChanges.xml (only for deploy jobs) ===
if [[ "$USE_LAST_SHA" == "true" ]]; then
  echo "🗑️ Building destructiveChanges.xml..."
  echo '<?xml version="1.0" encoding="UTF-8"?>' > "$DESTRUCTIVE_XML"
  echo '<Package xmlns="http://soap.sforce.com/2006/04/metadata">' >> "$DESTRUCTIVE_XML"

  cut -d '/' -f2- <<< "$(grep . "$DELETIONS_FILE")" \
    | sed 's/\.[^.]*$//' \
    | awk -F '/' '{print $1, $2}' \
    | sort | uniq \
    | while read type name; do
        echo "  <types>" >> "$DESTRUCTIVE_XML"
        echo "    <members>$name</members>" >> "$DESTRUCTIVE_XML"
        echo "    <name>$type</name>" >> "$DESTRUCTIVE_XML"
        echo "  </types>" >> "$DESTRUCTIVE_XML"
      done

  echo "  <version>$API_VERSION</version>" >> "$DESTRUCTIVE_XML"
  echo '</Package>' >> "$DESTRUCTIVE_XML"
else
  echo "ℹ️ Destructive deploy skipped — this is a feature validation context."
fi

# === STEP 7: List included components ===
echo "📜 Delta package contents:"
find "$PACKAGE_DIR" -type f ! -name "package.xml" | sed "s|^$PACKAGE_DIR/|- |"

# === STEP 8: GitHub summary ===
if [[ -n "$GITHUB_STEP_SUMMARY" ]]; then
  {
    echo "### ${ENV_ICON} Delta Deployment Summary"
    echo "- **Target Environment**: ${ENVIRONMENT}"
    echo "- **Base Branch**: ${BASE_BRANCH}"
    echo "- **Commit Range**: ${RANGE}"
    echo "- **Run ID**: ${GITHUB_RUN_ID:-N/A}"
    echo "- **Timestamp**: $(date +'%Y-%m-%d %H:%M:%S')"
    echo "- **Delta Components:**"
    grep "<name>" "$PACKAGE_XML" | sed 's/ *<[^>]*>//g' | sort | uniq | sed 's/^/- /'
    if [[ -s "$DESTRUCTIVE_XML" && "$USE_LAST_SHA" == "true" ]]; then
      echo "- **Destructive Components Removed:**"
      grep "<name>" "$DESTRUCTIVE_XML" | sed 's/ *<[^>]*>//g' | sort | uniq | sed 's/^/- /'
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

echo "✅ Delta script completed successfully."
