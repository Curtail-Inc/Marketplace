# ReGrade Plugin for Claude Code

AI-powered bug detection via replay differential testing.

## Installation

### Prerequisites
- Claude Code CLI installed and configured
- Linux x86_64 system (for sensor binary)

### Quick Start

1. **Sign Up** - Get your API key at https://app.regrade.curtail.com/free-trial

2. **Install Plugin**
   ```bash
   # Add marketplace and install plugin
   claude plugin marketplace add https://app.regrade.curtail.com/downloads/latest/marketplace.json
   claude plugin install regrade@regrade --scope user
   ```

3. **Install Sensor Binary**
   ```bash
   # Linux x86_64
   curl -LO https://app.regrade.curtail.com/downloads/latest/regrade-linux-x86_64
   chmod +x regrade-linux-x86_64
   mv regrade-linux-x86_64 ~/.local/bin/regrade
   ```

4. **Configure API Key**
   ```bash
   export REGRADE_API_KEY="your-api-key-here"
   echo 'export REGRADE_API_KEY="your-api-key-here"' >> ~/.bashrc
   source ~/.bashrc
   ```

5. **Verify Installation**
   ```bash
   claude plugins list  # Should show: ❯ regrade@regrade
   /mcp                 # Should show "regrade" MCP server
   regrade --version    # Should show: regrade 0.x.x
   ```

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

The plugin connects to the ReGrade cloud API using your API key:
```bash
export REGRADE_API_KEY="sk_live_..."
```

Add to your shell profile for persistence:
```bash
echo 'export REGRADE_API_KEY="sk_live_..."' >> ~/.bashrc
source ~/.bashrc
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
# Record traffic from your application
regrade proxy --target https://api.example.com --port 8888

# Replay against a new version
regrade replay --rec-id <recording-id> --target https://staging.example.com
```

Then use this plugin via Claude Code to analyze the deltas and identify bugs.

## Support

For issues or questions, contact Curtail support at support@curtail.com
