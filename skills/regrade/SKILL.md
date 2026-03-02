---
name: regrade
description: Analyze replay deltas to find bugs in API implementations. Use when developer asks to analyze a replay, investigate deltas, find bugs in API responses, check for regressions, or mentions ReGrade analysis. Also use when developer mentions recording, replaying, or differential testing.
version: 1.0.0
---

# ReGrade Bug Investigation Methodology

You are analyzing replay deltas to identify bugs in API implementations. ReGrade performs differential testing by replaying recorded API traffic against a new software version and comparing responses.

## CLI vs MCP

**CLI (Bash, only two commands):**
- `regrade proxy --target <url> --port <port>` — Record traffic
- `regrade replay --rec-id <id> --target <url>` — Replay against new version

**MCP tools (function calls, everything else):**
- `list_recordings`, `list_replays`, `list_profiles` — Discovery
- `summarize_deltas`, `query_deltas`, `get_delta_request_context` — Investigation
- `analyze_replay_performance`, `analyze_semantic_patterns` — Analysis
- `create_profile`, `create_filter_rule`, `create_id_mapping` — Profile rules
- `create_transformation_rule` — URL/body/header transformations
- `apply_profile_to_replay` — Apply rules retroactively
- `batch_update_deltas`, `list_delta_labels` — One-off labeling

## CRITICAL PRINCIPLE: Never Assume "Data Changed"

**ReGrade compares IDENTICAL DATA across DIFFERENT SOFTWARE VERSIONS.**

When you see different content in responses:
- **WRONG:** "The data must have changed between recording and replay"
- **RIGHT:** "The API is returning wrong data due to a code bug"

**ONLY exception:** ID fields (UUIDs, auto-increment IDs) that refer to the same logical entity but have different values. These need ID mapping.

---

## Root Cause Analysis Philosophy

**Goal: Find the FEWEST root causes that explain the MOST deltas.**

- 100+ deltas usually = 1-3 bugs, NOT 100 bugs
- One ignored parameter can cause 500+ content differences
- Always ask: "What single bug would explain all these deltas?"

---

## Iterative Profile Refinement Workflow

**CRITICAL: Always use profile rules (create_filter_rule + apply_profile_to_replay) instead of batch_update_deltas for routine labeling. Profile rules are reusable across replays. batch_update_deltas is only for one-off investigative notes.**

### The Goal: Complete Delta Coverage

**Success criteria:**
- `query_deltas(replay_id, unlabeled_only=true)` returns **0 deltas**
- Every delta is either DROPPED or LABELED via profile rules

### Minimal Labels with Root Cause Grouping

**Use as FEW labels as possible:**
- All deltas from the SAME root cause get the SAME label
- One pagination bug affecting 300 deltas = ONE label: `pagination-bug-page-ignored`

### Iteration Loop

1. Run replay WITHOUT profile first time
2. Analyze all deltas, identify root causes
3. Create profile with DROP/LABEL/MAP rules
4. Apply profile: `apply_profile_to_replay(replay_id, profile_id)`
5. Verify: `query_deltas(replay_id, unlabeled_only=true)` → should return 0
6. If mappings were created: re-run replay WITH profile (mappings may reveal new deltas)
7. Repeat until `unlabeled_only=true` returns 0

### Why Mappings Create New Deltas

**Before URL transformation:** `200→404` (asset not found)
**After URL transformation:** Content-length differs (minor size change)
The new delta needs labeling too — iterate until all are handled.

---

## Investigation Workflow

### Step 1: Start with Summary

**ALWAYS begin with `summarize_deltas`** to get the big picture. Look for:
- Endpoints with high delta counts (systematic bug)
- High-severity deltas (status mismatches)
- Patterns suggesting parameterized request bugs

### Step 2: Investigate High-Severity Deltas

**Status mismatch patterns:**

| Pattern | Likely Cause | Action |
|---------|-------------|--------|
| 200→404 on /assets/*.js | Asset hash changed | URL transformation needed |
| 200→404 on /api/{uuid} | Entity ID changed | URL transformation needed |
| 200→500 | Critical bug | Investigate immediately |
| 200→403 | Auth/permission change | Check breaking changes |

**For 200→404 with asset hashes:**
1. Use `get_delta_request_context` to see the failed URL
2. Search for new hash: `query_deltas(location_path_pattern="@src|@href|script.*src")`
3. Find OLD→NEW hash mapping in `response_body_difference` deltas
4. Create URL transformation rule via `create_transformation_rule` with `target: "url"`

### Step 3: Investigate Parameterized Requests (CRITICAL)

**For ANY endpoint with query parameters (?sort=, ?page=, ?limit=):**

1. **Check metadata FIRST:** `query_deltas(location_path_pattern="meta|pagination|total|count|limit|offset|sort|order|page")`
2. **Compare metadata to request params** — if they don't match, the parameter is being IGNORED (root cause bug)
3. **Label ALL content deltas as side effects** via a profile filter rule

### Step 4: Identify Data Evolution (Rare)

Only after ruling out code bugs. Verify:
- Checked request parameters vs response metadata
- Investigated high-severity deltas
- Looked for single bugs explaining multiple deltas

### Step 5: Performance Analysis

**ALWAYS run `analyze_replay_performance`** to detect regressions. Report any:
- Critical regressions (>2x slower)
- Significant improvements (>50% faster)
- High-variance endpoints (reliability concerns)

---

## Labeling Strategy

### DROP (Pure Noise)
Timestamps (`*_at`, `*_date`), session IDs, CSRF tokens, request/trace IDs.
**Action:** `create_filter_rule` with `action: drop`

### LABEL (Significant But Expected)
Environment URL differences, version headers, schema evolution (new fields).
**Action:** `create_filter_rule` with `action: label`

### MAP (Dynamic Identifiers)
UUIDs, ObjectIDs, asset hashes — same entity, different values.
**Action:** `create_id_mapping` (source=body for JSON IDs, source=header for response headers), `create_transformation_rule` (target=url for URLs, target=body for request bodies, target=header for request headers)

**Namespace pairing rule:** When creating extraction + transformation pairs (e.g., `create_id_mapping` + `create_transformation_rule`), always specify the **same explicit `namespace`** on both tools. Do NOT rely on auto-generated namespace defaults — they produce names like `auto_posts_id` or `header_x_auth_token` that won't match an explicitly-named transform namespace, causing silent mapping failures.

---

## Troubleshooting Filter Rules

**Path patterns must include the `$` prefix** — JSON paths start with `$` (e.g., `$.posts[8]`):
```
WRONG: "^\.posts\[\d+\]$"
RIGHT: "^\\$\\.posts\\[\\d+\\]$"
```

**Debug workflow:**
1. Check actual paths: `query_deltas(unlabeled_only=true, group_by="path")`
2. Create rule → `apply_profile_to_replay` → check if deltas got labeled
3. If not matching: compare actual path against your pattern regex

---

## Final Analysis Output

After investigation, provide:

1. **Bugs Identified** — Description, root cause, affected endpoints, delta count, severity, evidence
2. **Intentional Changes** — New fields, deprecated fields, schema migrations
3. **Performance Analysis** — Regressions, improvements, reliability concerns
4. **Profile Status** — Total/labeled/unlabeled counts, rules created, whether next iteration needed
5. **Recommendations** — Priority fixes, re-test suggestions

### Checklist
- [ ] Used `summarize_deltas` for overview
- [ ] Investigated all high-severity deltas
- [ ] Checked metadata vs request params for parameterized endpoints
- [ ] Ran `analyze_replay_performance`
- [ ] Created profile rules (not manual batch updates) for all patterns
- [ ] `query_deltas(unlabeled_only=true)` returns 0 or documented why
- [ ] If mappings created: flagged need for re-replay

---

## Common Mistakes

1. Assuming data changed → Investigate for bugs instead
2. Labeling deltas individually → Find root cause explaining many
3. Using `batch_update_deltas` for routine labeling → Use profile rules + `apply_profile_to_replay`
4. Stopping before profile complete → Iterate until unlabeled = 0
5. Not testing mappings → Re-run replay after creating mapping rules
6. Skipping metadata checks for parameterized requests
7. Not running performance analysis
8. Wrong path patterns (missing `$` prefix, unescaped regex chars)

**You are not done until every delta is labeled.**
