# ReGrade Plugin for Claude Code

AI-powered bug detection via replay differential testing.

## Installation

This plugin is part of the ReGrade marketplace. See the marketplace README for installation instructions.

## Using the Plugin

The plugin provides the `/regrade:regrade` skill for automated bug detection and analysis.

**Usage:**
```
# Automatic activation when mentioning replay analysis
"Analyze the latest replay"

# Explicit invocation
"/regrade:regrade"
```

## Configuration

**Default Settings (Cloud):**
- `REGRADE_API_URL` → `https://api.regrade.curtail.com`
- `REGRADE_KEY_FILE` → `$HOME/.regrade/key`

**No configuration needed for cloud use!**

**For local development:**
```bash
export REGRADE_API_URL="http://localhost"
```

## What It Does

- **Identifies bugs** vs intentional changes
- **Checks for query parameter bugs** (ignored parameters)
- **Detects performance regressions**
- **Creates noise reduction profiles** automatically
- **Generates structured reports** with bugs/changes/performance sections

## Documentation

- `skills/regrade/SKILL.md` - Complete investigation methodology
- `resources/mapping-guide.md` - ID mapping and request transformation guide
- `resources/example-analysis-output.md` - Example analysis report

## ReGrade CLI

The plugin analyzes replays created by the ReGrade CLI:

```bash
# Record traffic
regrade proxy --target http://api:8080 --port 8888

# Replay against new version
regrade replay --rec-id <recording-id> --target http://new-version:8080
```

Then use this plugin via Claude Code to analyze the deltas.

## Support

For issues or questions, contact Curtail support at support@curtail.com
