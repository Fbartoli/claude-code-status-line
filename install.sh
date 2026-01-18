#!/bin/bash
# Claude Code Status Line Installer

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.claude/scripts"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "🚀 Installing Claude Code Status Line..."

# Create scripts directory
mkdir -p "$DEST_DIR"

# Copy script
cp "$SCRIPT_DIR/status-indicator.sh" "$DEST_DIR/"
chmod +x "$DEST_DIR/status-indicator.sh"
echo "✓ Copied status-indicator.sh to $DEST_DIR/"

# Update settings.json
if [[ -f "$SETTINGS_FILE" ]]; then
    # Check if statusLine already configured
    if grep -q '"statusLine"' "$SETTINGS_FILE"; then
        echo "⚠ statusLine already configured in settings.json"
        echo "  Please verify it points to: ~/.claude/scripts/status-indicator.sh"
    else
        # Add statusLine to existing settings
        # Remove trailing } and add statusLine config
        tmp=$(mktemp)
        sed '$ s/}$/,\n  "statusLine": {\n    "type": "command",\n    "command": "~\/.claude\/scripts\/status-indicator.sh"\n  }\n}/' "$SETTINGS_FILE" > "$tmp"
        mv "$tmp" "$SETTINGS_FILE"
        echo "✓ Added statusLine to settings.json"
    fi
else
    # Create new settings.json
    cat > "$SETTINGS_FILE" << 'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/scripts/status-indicator.sh"
  }
}
EOF
    echo "✓ Created settings.json with statusLine config"
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Restart Claude Code to see the status line."
echo ""
echo "Example output:"
echo "  [Opus 4.5] 🟢 Ctx: 33% | 1K↓ 2K↑ 45K⚡ | 🧠 | \$5.57 | main"
