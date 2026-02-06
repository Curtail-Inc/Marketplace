# ReGrade Plugin Marketplace

AI-powered bug detection via replay differential testing for Claude Code.

## Quick Installation

Extract this package and run:

```bash
claude plugin marketplace add ./regrade-marketplace
claude plugin install regrade@regrade
```

That's it! The `/regrade:regrade` skill is now available.

## Usage

The plugin provides the `/regrade:regrade` skill for automated bug detection:

```
# Automatic activation
"Analyze the latest replay"

# Explicit invocation
"/regrade:regrade analyze replay-id"
```

## Configuration

**Default (Cloud):**
- API URL: `https://api.regrade.curtail.com`
- Key file: `~/.regrade/key`

**For local development:**
```bash
export REGRADE_API_URL="http://localhost"
```

## What It Does

- Identifies bugs vs intentional changes
- Detects query parameter bugs (ignored parameters)
- Finds performance regressions
- Creates noise reduction profiles automatically
- Generates structured reports

## Support

Contact Curtail support at support@curtail.com
