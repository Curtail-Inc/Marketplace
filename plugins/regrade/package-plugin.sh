#!/bin/bash
#
# Package ReGrade Plugin for Distribution
#
# Creates a tarball that can be extracted to ~/.claude/plugins/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${OUTPUT_FILE:-regrade-plugin.tar.gz}"

echo "Packaging ReGrade Plugin..."

# Create tarball from plugin directory
cd "$(dirname "$SCRIPT_DIR")"
tar -czf "$OUTPUT_FILE" \
  --exclude='.DS_Store' \
  --exclude='*.tar.gz' \
  regrade-plugin/

echo "✓ Plugin packaged successfully: $OUTPUT_FILE"
echo "  Size: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo ""
echo "Installation:"
echo "  tar -xzf $OUTPUT_FILE -C ~/.claude/plugins/"
echo "  # or"
echo "  mkdir -p ~/.claude/plugins && tar -xzf $OUTPUT_FILE --strip-components=0 -C ~/.claude/plugins/"
