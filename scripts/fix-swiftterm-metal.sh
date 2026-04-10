#!/bin/bash
# Workaround for tuist/tuist#9111: Tuist adds .metal files as both Sources and Resources,
# causing "Unexpected duplicate tasks" build errors.
# This removes the duplicate "Shaders.metal in Sources" entry, keeping only Resources.

# Find all SwiftTerm pbxproj files (Tuist can place them in different locations)
PBXPROJS=$(find . -path "*/SwiftTerm/*.xcodeproj/project.pbxproj" 2>/dev/null)

if [ -z "$PBXPROJS" ]; then
  echo "SwiftTerm project not found, skipping"
  exit 0
fi

FIXED=0
while IFS= read -r PBXPROJ; do
  if grep -q "Shaders.metal in Sources" "$PBXPROJ"; then
    sed -i.bak '/Shaders\.metal in Sources/d' "$PBXPROJ"
    rm -f "${PBXPROJ}.bak"
    echo "Fixed: removed duplicate Shaders.metal from Sources in $PBXPROJ"
    FIXED=$((FIXED + 1))
  fi
done <<< "$PBXPROJS"

if [ $FIXED -eq 0 ]; then
  echo "No duplicate Metal entry found, skipping"
fi
