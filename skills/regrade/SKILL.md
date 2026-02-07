---
name: regrade
description: Analyze replay deltas to find bugs in API implementations. Use when developer asks to analyze a replay, investigate deltas, find bugs in API responses, check for regressions, or mentions ReGrade analysis. Also use when developer mentions recording, replaying, or differential testing.
version: 1.0.0
---

# ReGrade Bug Investigation Methodology

You are analyzing replay deltas to identify bugs in API implementations. ReGrade performs differential testing by replaying recorded API traffic against a new software version and comparing responses.

## ReGrade CLI + MCP Workflow

ReGrade has two separate interfaces - CLI for recording/replaying, MCP for everything else.

### 1. ReGrade CLI - ONLY for Recording and Replaying

**The CLI has ONLY two commands:**

**Recording traffic** (capture production or test traffic):
```bash
regrade proxy --target http://api-server:8080 --port 8888
# Point client at localhost:8888 to record traffic
```

**Replaying traffic** (test against new version):
```bash
regrade replay --rec-id <recording-id> --target http://new-version:8080
```

**That's it!** Everything else is done via MCP tools.

### 2. MCP Tools - Everything Else

**All listing, analysis, and profile management is done via MCP tools**, NOT CLI commands.

**Available MCP tools:**
- `list_recordings` - List available recordings
- `list_replays` - List replays (use this to find latest replay)
- `list_profiles` - List app profiles
- `summarize_deltas` - Get overview of deltas in a replay
- `query_deltas` - Search deltas with filters
- `get_delta_request_context` - Get full request/response for a delta
- `analyze_replay_performance` - Detect performance regressions
- `create_profile_filter_rule` - Create noise reduction rules
- `create_id_mapping` - Set up ID mappings for dynamic identifiers
- `create_profile` - Create a new app profile

**How to use MCP tools:**
When this skill is active, these tools are available in your function list. Use them directly, NOT as bash commands.

❌ **WRONG:**
```bash
regrade list-replays  # NOT a CLI command!
regrade summarize-deltas --replay-id <id>  # NOT a CLI command!
```

✅ **RIGHT:**
```
Use MCP tools directly as function calls:
- list_replays()
- summarize_deltas(replay_id="<id>")
```

**Your role:**
- List and find replays using MCP tools
- Analyze deltas from replays using MCP tools
- Identify bugs vs intentional changes
- Create noise reduction profiles using MCP tools
- Generate structured bug reports
- Recommend fixes and retests

**Typical workflow:**
1. Developer runs CLI: `regrade replay ...` (creates replay with deltas)
2. Developer invokes this skill: `/regrade:regrade` or asks "analyze latest replay"
3. You use MCP tool `list_replays` to find the latest replay
4. You use MCP tool `summarize_deltas` to get overview
5. You use other MCP tools to investigate: `query_deltas`, `get_delta_request_context`, etc.
6. You create filter profiles using MCP tools
7. You provide structured analysis report
8. Developer fixes bugs, runs new CLI replay
9. Repeat until no bugs remain

### Quick Reference: CLI vs MCP

**CLI Commands (use Bash tool, ONLY these two):**
- `regrade proxy` - Start recording traffic
- `regrade replay` - Replay traffic against new version

**MCP Tools (use as function calls, everything else):**
- `list_recordings()` - List recordings
- `list_replays()` - List replays
- `list_profiles()` - List profiles
- `summarize_deltas()` - Analyze deltas
- `query_deltas()` - Search deltas
- `get_delta_request_context()` - Get delta details
- `analyze_replay_performance()` - Performance analysis
- `create_profile_filter_rule()` - Add filter rules
- `create_id_mapping()` - Configure ID mappings
- `create_profile()` - Create app profiles

### When to Guide Developers to Use the CLI

If the developer asks:
- "How do I record traffic?" → Explain `regrade proxy` (CLI)
- "How do I replay?" → Explain `regrade replay` (CLI)
- "How do I list recordings?" → Use MCP tool `list_recordings()` for them
- "How do I analyze deltas?" → Use MCP tools to do the analysis

**Only guide them to CLI for recording and replaying. Everything else you do via MCP.**

## CRITICAL PRINCIPLE: Never Assume "Data Changed"

**ReGrade compares IDENTICAL DATA across DIFFERENT SOFTWARE VERSIONS.**

When you see different content in responses:
- ❌ **WRONG:** "The data must have changed between recording and replay"
- ✅ **RIGHT:** "The API is returning wrong data due to a code bug"

The recording and replay use the SAME database state. Differences indicate bugs in the code, not differences in data.

**ONLY exception:** ID fields (UUIDs, auto-increment IDs) that refer to the same logical entity but have different values. These need ID mapping, not "data changed" assumptions.

---

## Root Cause Analysis Philosophy

**Goal: Find the FEWEST root causes that explain the MOST deltas.**

- 100+ deltas usually = 1-3 bugs, NOT 100 bugs
- One ignored parameter can cause 500+ content differences
- Look for systematic patterns, not individual anomalies
- Always ask: "What single bug would explain all these deltas?"

---

## Iterative Profile Refinement Workflow

**CRITICAL: You are not done until EVERY delta is labeled.**

### The Goal: Complete Delta Coverage

**Success criteria for a profile:**
- Query `query_deltas(replay_id, unlabeled_only=true)` returns **0 deltas**
- Every delta has been classified as either:
  - **DROPPED** (pure noise like timestamps)
  - **LABELED** (expected differences, side effects, or bugs)

**If unlabeled deltas remain, the profile is incomplete.**

### Minimal Labels with Root Cause Grouping

**Use as FEW labels as possible:**
- All deltas from the SAME root cause get the SAME label
- One pagination bug affecting 300 deltas = ONE label: `pagination-bug-page-ignored`
- One asset hash change affecting 5 files = ONE label: `side-effect-of-version-change`

**Bad labeling (too many labels):**
```
- post-1-title-changed
- post-2-title-changed
- post-3-title-changed
...
- post-100-title-changed
```

**Good labeling (root cause grouping):**
```
- side-effect-of-pagination-bug  (all 100+ content deltas share this label)
```

### Iteration Loop

**Phase 1: Initial Analysis**
1. Run replay WITHOUT profile first time
2. Analyze all deltas, identify root causes
3. Create profile with DROP/LABEL/MAP rules
4. Verify: `query_deltas(replay_id, unlabeled_only=true)` → should return 0 or close to 0

**Phase 2: Mapping Refinement**
5. Run NEW replay WITH the profile
6. Mappings/transformations apply → **new deltas may appear!**
7. Example: Asset 404 (high severity) becomes content-length diff (low severity)
8. These new deltas need labeling too!
9. Update profile to label the new delta types

**Phase 3: Iteration Until Complete**
10. Repeat Phase 2 until `unlabeled_only=true` returns 0 deltas
11. Every iteration may reveal new patterns as mappings work correctly
12. Final state: Profile automatically handles ALL noise and expected differences

### Why Mappings Create New Deltas

**Before URL transformation:**
- Delta: `200→404` (high severity) - Asset not found
- Label: Not yet labeled

**After URL transformation:**
- Old delta eliminated (transformation fixed the 404)
- NEW delta appears: Content length differs (low severity)
- Why: Transformation worked! Now comparing correct files, but they have minor size difference
- **This new delta needs labeling:** `expected-difference-minor-asset-size-change`

### Iteration Example

**Iteration 1:**
```
Total deltas: 620
Unlabeled: 620
Action: Create initial profile with DROP/LABEL rules
```

**Iteration 2 (replay with profile):**
```
Total deltas: 426 (194 dropped)
Labeled: 123
Unlabeled: 303
Action: Investigate unlabeled deltas, add more rules
```

**Iteration 3 (replay with updated profile):**
```
Total deltas: 450 (some mappings revealed new deltas)
Labeled: 425
Unlabeled: 25
Action: Label the 25 remaining deltas (side effects, minor differences)
```

**Iteration 4 (final):**
```
Total deltas: 455
Labeled: 455
Unlabeled: 0  ✅ DONE!
```

### When to Stop Iterating

**You can stop when:**
- ✅ `query_deltas(replay_id, unlabeled_only=true)` returns 0 results
- ✅ All remaining deltas are actual bugs that need fixing (not noise or expected differences)
- ✅ Profile rules are stable (no new patterns appearing)

**Don't stop if:**
- ❌ Unlabeled deltas remain
- ❌ You just added mapping rules (need to test them)
- ❌ Patterns exist that could be automated with rules

### Communicating Progress

When reporting to the user, always include:
```
**Profile Completeness:**
- Total deltas: 455
- Labeled automatically: 420 (92%)
- Unlabeled: 35 (8%)

**Next iteration needed:** Yes
- 35 unlabeled deltas need classification
- Recommend adding rules for [pattern description]
```

**When complete:**
```
**Profile Completeness:**
- Total deltas: 455
- Labeled automatically: 455 (100%)
- Unlabeled: 0 ✅

**Profile is complete!** All noise and expected differences are automated.
Remaining labeled deltas are actual bugs or intentional changes.
```

---

## Investigation Workflow

### Step 1: Start with Summary

**ALWAYS begin with the MCP tool `summarize_deltas`** to get the big picture:
- Total delta count and severity distribution
- Hot endpoints (disproportionate delta counts)
- Root-level deltas (most likely root causes)

Look for:
- Endpoints with unexpectedly high delta counts (indicates systematic bug)
- High-severity deltas (status mismatches, critical issues)
- Patterns suggesting parameterized request bugs

### Step 2: Investigate High-Severity Deltas

**CRITICAL:** Status mismatches are often the first indicator of URL transformation needs.

#### Identifying URL Mapping Requirements

**Status Code Pattern Recognition:**

| Pattern | Likely Cause | Investigation Action |
|---------|--------------|---------------------|
| 200→404 on /assets/*.js or *.css | Asset hash changed | URL transformation needed |
| 200→404 on /api/resource/{uuid} | Entity ID changed | URL transformation needed |
| 200→404 on multiple similar URLs | Routing change or bug | Check if pattern-based |
| 404→301 or 404→302 | Redirect added | Label as routing change |
| 200→500 | Critical bug | Investigate immediately |
| 200→403 | Auth/permission change | Check for breaking changes |

#### Investigation Workflow for 200→404 (URL Mapping Candidates)

**Step 2a: Get the full context**
```
Use get_delta_request_context(replay_id, delta_id)
```
This shows:
- The exact URL that returned 404
- Request method and headers
- Original response (200) vs replay response (404)

**Step 2b: Classify the 404 type**

**Type 1: Asset Hash Change (Most Common)**
- **URL pattern:** `/assets/file-HASH.ext` or `/path/file.min-HASH.js`
- **Indicators:**
  - Filename contains hex hash (32-64 characters)
  - File extension is .js, .css, .png, .jpg, .woff, etc.
  - Hash appears to be content-based (SHA256, MD5, etc.)
- **Example:** `/assets/app.min-bed13fa971b2b2c352507b7d16048f97.js` → 404

**Type 2: Entity ID in URL Path**
- **URL pattern:** `/api/users/{uuid}` or `/api/posts/{id}/comments`
- **Indicators:**
  - URL contains UUID format (8-4-4-4-12 hex)
  - URL contains ObjectId format (24 hex chars)
  - URL contains numeric ID in path segment
- **Example:** `/api/users/5d39f34ce059b700013c896b` → 404

**Type 3: Query Parameter ID**
- **URL pattern:** `/api/search?user_id={id}` or `/api/data?item={uuid}`
- **Indicators:**
  - Query parameter contains ID-like value
  - Similar requests with different IDs work
- **Example:** `/api/comments?post_id=abc-123` → 404

**Type 4: True Missing Endpoint (NOT URL Mapping)**
- **URL pattern:** Structural endpoint path changed
- **Indicators:**
  - No hash or ID in URL
  - Endpoint removed in new version
  - Multiple different endpoints return 404
- **Example:** `/api/v1/legacy` → 404 (removed endpoint)

**Step 2c: Find the new hash/ID (Types 1-3 only)**

For **Asset Hashes:**
```
query_deltas(
  replay_id=replay_id,
  location_path_pattern="@src|@href|script.*src|link.*href|url",
  delta_type=["value_mismatch"],
  group_by="none",
  limit=10
)
```
**Look for:**
- HTML attributes: `<script src="assets/app-OLD.js">` changed to `<script src="assets/app-NEW.js">`
- CSS urls: `background: url('assets/img-OLD.png')` → `url('assets/img-NEW.png')`
- JSON asset references: `{"js": "app-OLD.js"}` → `{"js": "app-NEW.js"}`

**Extract the mapping:**
- Old hash: `bed13fa971b2b2c352507b7d16048f97`
- New hash: `a552bfc8a6b91e1baf0e5d7761fbf11e`
- Context: `app.min.js` (the filename without hash)

For **Entity IDs:**
```
query_deltas(
  replay_id=replay_id,
  location_path_pattern="^\\..*\\.id$|^\\..*_id$",
  delta_type=["value_mismatch"],
  group_by="path",
  limit=20
)
```
**Look for:**
- `$.posts[*].id` changed from `5d39f34c...` to `7a82b91e...`
- `$.user.author_id` changed from `uuid-old` to `uuid-new`
- Same logical entity, different ID value

**Verification checklist:**
- [ ] Found the value_mismatch delta showing OLD→NEW
- [ ] Confirmed same entity (same position in array, same semantic meaning)
- [ ] Confirmed it's an ID, not different data
- [ ] Extracted both old and new values

**Step 2d: Determine if URL transformation is needed**

**Need URL transformation if:**
- ✅ The 404 URL contains the OLD value (hash or ID)
- ✅ You found the NEW value in response deltas
- ✅ The URL is being requested from a recording (can't change the recording)
- ✅ The sensor should automatically transform the URL before sending

**Don't need URL transformation if:**
- ❌ Endpoint was genuinely removed (Type 4)
- ❌ It's a one-time migration (old system vs new system, not version change)
- ❌ The ID appears in request BODY, not URL (needs body transformation instead)

**Step 2e: Document the URL transformation requirement**

When you find a URL transformation case, document:

```
**URL Transformation Required: Asset Hash Change**

**Failed Request:** GET /assets/app.min-bed13fa971b2b2c352507b7d16048f97.js → 404
**Root Cause:** Asset hash changed between recording and replay versions

**Mapping Discovered:**
- Old hash: bed13fa971b2b2c352507b7d16048f97
- New hash: a552bfc8a6b91e1baf0e5d7761fbf11e
- Context: app.min.js
- Found in: HTML response, /html/body[2]/script[4]/@src

**Current Status:**
- ❌ URL transformation rule NOT created (MCP tool limitation)
- ⚠️  Manual configuration required

**Required Configuration:**
[Show complete YAML configuration here]

**Impact:** Asset 404 will persist until URL transformation rule is added to profile.

**Workaround:** Label as 'side-effect-of-version-change' and 'asset-not-found'
```

#### Special Case: Multiple Assets with Pattern

If you see **multiple 404s following the same pattern** (e.g., 5 different JS files, all with hash changes):

1. **Group them together** - they're all the same root cause
2. **Find the pattern** - e.g., all `/assets/*.min-{hash}.js` files
3. **Create ONE transformation rule** that handles all of them with a regex pattern
4. **Document once** - note that it covers N asset files

**Example:**
```
**URL Transformation Required: Multiple Asset Hashes**

Pattern: /assets/{filename}.min-{hash}.js

Affected assets (5 files):
- app.min-{old_hash}.js → 404
- vendor.min-{old_hash}.js → 404
- bundle.min-{old_hash}.js → 404
[etc.]

**Solution:** Single URL transformation rule with pattern matching will handle all cases.
```

#### Non-URL Mapping Status Mismatches

**If 200→404 on API endpoints (Type 4):**
- Investigate if endpoint was removed (breaking change)
- Check if URL structure changed (routing bug)
- Use `get_delta_request_context` to understand the failure
- **This is usually a BUG or BREAKING CHANGE, not a mapping issue**

**If 200→500 or other errors:**
- Critical bug: API is crashing or failing
- Get full context and investigate immediately
- Check error response body for stack traces or error messages

**If 404→301 or 404→302:**
- Routing configuration changed (redirect added)
- Label as `routing-change`
- Not a mapping issue - this is intentional infrastructure change

### Step 3: Investigate Parameterized Requests (CRITICAL)

**For ANY endpoint with query parameters (`?sort=`, `?page=`, `?limit=`, `?filter=`, etc.):**

This is the MOST COMMON bug pattern. Follow this MANDATORY workflow:

#### 3a. Check Response Metadata FIRST

Use `query_deltas` with `location_path_pattern` to find response metadata fields:
```
location_path_pattern="meta|pagination|total|count|limit|offset|sort|order|query|cursor|page"
```

These fields tell you what the API **claims** it's returning.

#### 3b. Compare Metadata to Request Parameters

Example request: `GET /items?page=2&limit=30&sort=name`

Check if response metadata matches:
- Does `meta.page` or `pagination.page` = `2`?
- Does `meta.limit` or `pagination.limit` = `30`?
- Does `meta.sort` or `sort_order` = `name`?

**If metadata DOESN'T match request parameters:**
🚨 **BUG FOUND:** API is ignoring the parameter!

#### 3c. Label ALL Content Deltas as Side Effects

If you find an ignored parameter:
1. All content differences are side effects of this ONE bug
2. Label them as `side-effect-of-[parameter-name]-ignored`
3. Create a profile rule to automatically label these in future
4. Note the bug in your final analysis

**Example:**
- Request: `?page=2&limit=30`
- Response shows: `{page: 1, limit: 30}`
- Bug: `page` parameter is being ignored
- Result: All 600+ content deltas are side effects of returning page 1 instead of page 2

### Step 4: Identify Data Evolution (Rare)

Only after ruling out code bugs, consider if differences might be intentional changes:

**Acceptable as data evolution:**
- New fields added to response (feature addition)
- New enum values (feature addition)
- Schema migrations (documented changes)
- Deprecated fields removed (documented breaking changes)

**Before labeling as "data-evolution", verify:**
- [ ] Checked request parameters vs response metadata
- [ ] Investigated high-severity deltas
- [ ] Looked for single bugs explaining multiple deltas
- [ ] Used `get_delta_request_context` for suspicious patterns
- [ ] Confirmed the API is working correctly per its spec

**Still NOT data evolution:**
- Different items in arrays at same positions = pagination bug
- Different ID values = needs ID mapping
- Missing/extra items = likely pagination or filter bug
- Content mismatches = likely query parameter bug

### Step 5: Performance Analysis

**ALWAYS run the MCP tool `analyze_replay_performance`** to detect performance regressions:

Look for:
- Endpoints with statistically significant slowdowns (p-value < 0.05)
- Large effect sizes (Cohen's d > 0.8)
- High variability (CV > 0.5 indicates inconsistent performance)
- Endpoints taking >500ms average (user-visible latency)

Report any:
- Critical regressions (>2x slower)
- Significant improvements (>50% faster)
- High-variance endpoints (reliability concerns)

---

## Labeling Strategy

### DROP (Pure Noise)

Automatically filter out deltas that provide zero value:

**Timestamps:**
- `*updated_at`, `*created_at`, `*last_seen`, `*published_at`
- Any field ending in `_at`, `_date`, `_time` that's an ISO timestamp

**Ephemeral Data:**
- Session IDs, CSRF tokens
- Request IDs, trace IDs
- Timestamps in headers

**Use case:** These will ALWAYS differ between recording and replay.

**Action:** Create filter rule with `action: drop`

### LABEL (Significant But Expected)

Mark deltas that are real differences but may be intentional:

**Environment Differences:**
- URL format changes (relative vs absolute)
- Hostname differences (localhost vs production domain)
- Port numbers in URLs

**Version Changes:**
- Asset hashes changing (use ID mapping too)
- API version headers changing
- Software version fields

**Schema Evolution:**
- New optional fields added
- Deprecated fields removed (with warning)
- Enum values added

**Action:** Create filter rule with `action: label` and descriptive labels

### MAP (Dynamic Identifiers)

Use ID mapping when values refer to the same entity but differ:

**Entity IDs:**
- UUIDs, ObjectIDs, auto-increment IDs
- When same logical entity has different ID values

**Content-Addressed Values:**
- Asset hashes in filenames (`app-ABC.js` vs `app-XYZ.js`)
- Content hashes, ETags
- Version-specific identifiers

**How mapping works:**
1. Sensor learns OLD_ID → NEW_ID mapping by comparing responses
2. Future requests are transformed: OLD_ID in request → NEW_ID before sending
3. Responses are inverse-transformed: NEW_ID in response → OLD_ID for comparison

**Action:** Use `create_id_mapping` with JSONPath to ID field

---

### URL TRANSFORMATION (Asset Hashes and Dynamic URLs)

**CRITICAL: The `create_id_mapping` MCP tool is LIMITED** - it only creates basic JSON extraction rules and CANNOT handle URL transformations for asset files.

#### The Asset Hash Problem

When asset files have version hashes in their filenames:

1. **Recording:** HTML says `<script src="assets/app-ABC123.js">`, browser requests `GET /assets/app-ABC123.js` → 200 OK
2. **Replay:** HTML says `<script src="assets/app-XYZ789.js">` (new version)
3. **Problem:** Sensor replays recorded request `GET /assets/app-ABC123.js` → 404 Not Found (old hash doesn't exist)
4. **Need:** Transform request URL from old hash to new hash

#### What You'll See

When asset hash changes occur, you'll see:
- **status_mismatch (high):** 200→404 on asset files (JS/CSS/images)
- **value_mismatch (low):** HTML/JSON contains new asset hash in `src`/`href` attributes

#### Current MCP Limitation

The `create_id_mapping` MCP tool creates a **learning rule** but NOT a **URL transformation rule**:
- ✅ **What it does:** Learn hash mappings from HTML/JSON responses
- ❌ **What it doesn't do:** Transform request URLs before sending

#### Required Configuration for URL Transformation

For complete asset hash mapping, the profile needs BOTH rules:

**1. EXTRACTION RULE (learns from responses):**
```yaml
namespaces:
  asset-hashes:
    context_key: asset_filename
    rules:
      - name: "learn-asset-hashes-from-html"
        extract:
          from: html_attribute
          selector: "script[src*='.min-']"
          attribute: src
          pattern: "^/?(?:.*/)?assets/([^.]+)\\.min-([a-f0-9]{32})\\.js$"
          captures:
            filename: 1    # "app", "vendor", "bundle", etc.
            hash: 2        # 32-char hex hash
          context_template: "{filename}.min.js"
          value_template: "{hash}"
```

**2. APPLICATION RULE (transforms request URLs):**
```yaml
      - name: "apply-asset-hashes-to-requests"
        apply:
          to: request_url
          pattern: "^(.*/)assets/([^.]+)\\.min-([a-f0-9]{32})\\.js$"
          captures:
            prefix: 1
            filename: 2
            old_hash: 3
          mappings:
            - namespace: asset-hashes
              context_template: "{filename}.min.js"
              value_template: "{old_hash}"
              output: new_hash
          transform: "{prefix}assets/{filename}.min-{new_hash}.js"
```

#### Workflow for Asset Hash Mappings

When you find asset 404s (200→404 status mismatch):

1. **Use `get_delta_request_context`** to see the failed request URL
2. **Search for the new hash** using `query_deltas` with `location_path_pattern` matching asset references:
   ```
   location_path_pattern="@src|@href|script.*src|link.*href"
   ```
3. **Find OLD_HASH → NEW_HASH pattern** in value_mismatch deltas
4. **Document the hash change** in your analysis
5. **Explain the limitation:** Note that the MCP tool created a learning rule but URL transformation requires manual profile configuration
6. **Provide the complete YAML** (shown above) for the developer to add to the profile
7. **Label the 404s** as `side-effect-of-version-change` and `asset-not-found`

#### Profile Configuration Methods

Since the MCP API doesn't support URL transformation rules:

**Option 1: Manual YAML Configuration**
- Export current profile
- Add the complete namespace configuration with both extraction and application rules
- Re-import the profile

**Option 2: Direct API/Database Update**
- Update the profile document directly if you have access
- Add the URL transformation rules to the existing namespace

**Option 3: Request MCP Enhancement**
- File an issue requesting a new tool: `create_url_transformation_rule`
- Should support HTML extraction + URL application configuration

#### What to Tell Developers

When you find asset hash changes:

```
**Asset Version Change Detected**

Old hash: `bed13fa971b2b2c352507b7d16048f97`
New hash: `a552bfc8a6b91e1baf0e5d7761fbf11e`

**Current Status:**
- ✅ Learning rule created (sensor will learn the mapping)
- ❌ URL transformation rule NOT created (MCP tool limitation)
- ⚠️  Asset 404s will persist until URL transformation is configured

**To Fix:**
The profile needs a URL transformation rule added manually. I've documented the complete configuration in the analysis report. After adding it, re-run the replay and the 404s should disappear.

**Alternative:**
If this is a one-time version change and you don't need automated transformation, you can simply label these deltas as `side-effect-of-version-change` and ignore them in future replays of the same versions.
```

#### Common URL Transformation Patterns

**Pattern 1: Asset hashes in filenames**
- Example: `/assets/app.min-ABC123.js` → `/assets/app.min-XYZ789.js`
- Use HTML attribute extraction + URL pattern transformation

**Pattern 2: UUID path segments**
- Example: `/api/user/uuid-old/resource` → `/api/user/uuid-new/resource`
- Use JSON extraction from responses + URL segment transformation

**Pattern 3: Composite IDs**
- Example: `/api/org/id1/user/id2` → `/api/org/id1-new/user/id2-new`
- Use multiple namespace lookups in single transformation

**Pattern 4: Query parameter IDs**
- Example: `/api/search?user_id=old` → `/api/search?user_id=new`
- Use query string extraction + parameter transformation

---

## Troubleshooting Filter Rules

When filter rules don't match deltas as expected, use this debugging checklist:

### Common Path Pattern Issues

**Problem: Rules don't match JSON paths**

JSON paths in deltas **always start with `$`** (e.g., `$.posts[8].title`), but regex patterns must escape this:

```yaml
# ❌ WRONG - Missing $ prefix
path_pattern: "^\.posts\[\d+\]$"
# This pattern looks for: .posts[8]
# But actual path is:     $.posts[8]

# ✅ RIGHT - Escaped $ prefix
path_pattern: "^\\$\\.posts\\[\\d+\\]$"
# This pattern matches:   $.posts[8]
```

**Key escaping rules:**
- `$` → `\\$` (escape dollar sign for start-of-path)
- `.` → `\\.` (escape dot for field separator)
- `[` → `\\[` (escape brackets for array indices)
- `]` → `\\]`

**Common patterns:**
```yaml
# Match array elements: $.posts[N]
path_pattern: "^\\$\\.posts\\[\\d+\\]$"

# Match nested fields: $.posts[N].author
path_pattern: "^\\$\\.posts\\[\\d+\\]\\.author$"

# Match any field ending in .url: $.users[N].url
path_pattern: "\\.url$"

# Match HTML/XML attributes: @src or @href
path_pattern: "@src|@href"
```

### Debugging Workflow

**1. Check actual delta paths:**
```
query_deltas(replay_id, unlabeled_only=true, group_by="path")
```
This shows the exact paths in your deltas.

**2. Test your pattern:**
- Create a rule with your pattern
- Apply retroactively: `apply_profile_to_replay()`
- Check if deltas got labeled

**3. Fix common issues:**
- Missing `$` prefix in pattern
- Forgot to escape special regex characters
- Pattern too specific (won't match variations)
- Pattern too broad (matches unintended deltas)

### URL Pattern Issues

**Problem: Rules don't match request URLs**

URL patterns are regex patterns matched against the full request URL:

```yaml
# ❌ WRONG - Pattern too specific
url_pattern: "/api/posts?page=2"
# Doesn't match: /api/posts?page=3

# ✅ RIGHT - Pattern for endpoint
url_pattern: "/api/posts"
# Matches: /api/posts, /api/posts?page=2, etc.

# ✅ BETTER - Exact match
url_pattern: "^/api/posts$"
# Matches: /api/posts (but not /api/posts/)

# ✅ BEST - With query params
url_pattern: "^/api/posts/?\\?"
# Matches: /api/posts?... or /api/posts/?...
```

### Delta Type Matching

**Problem: Wrong delta_type specified**

Delta types must match exactly (case-insensitive):

```yaml
# Valid delta types:
- value_mismatch    # Value changed
- missing           # Field missing in replay
- extra             # Field present in replay but not recording
- type_mismatch     # Field type changed (string → number)
- status_mismatch   # HTTP status code changed
- large_content_diff # Content too large to diff
```

### Verification Steps

After creating or updating rules:

1. **Apply retroactively to test:**
   ```
   apply_profile_to_replay(replay_id, profile_id)
   ```

2. **Check labeling coverage:**
   ```
   query_deltas(replay_id, unlabeled_only=true)
   ```

3. **Verify label counts:**
   ```
   list_delta_labels(replay_id)
   ```

4. **If rules still don't match:**
   - Get full delta details: `get_delta_request_context()`
   - Compare actual path/URL against your pattern
   - Adjust pattern and retest

---

## Final Analysis Output Format

After completing your investigation, provide a structured analysis:

### 1. Bugs Identified

List actual code bugs found, each with:
- **Bug description**: What's broken
- **Root cause**: Ignored parameter, off-by-one error, etc.
- **Affected endpoints**: Which endpoints are impacted
- **Delta count**: How many deltas this bug explains
- **Severity**: Critical/High/Medium/Low
- **Evidence**: Request/response examples showing the bug

Example:
```
**Bug #1: Query parameter ignored in list endpoint**
- **Description**: The `page` query parameter is being ignored, always returning page 1
- **Root cause**: Pagination logic not reading `page` from query string
- **Affected**: GET /api/items (606 deltas)
- **Severity**: High - breaks pagination entirely
- **Evidence**: Request has `?page=2` but response `meta.page: 1`
```

### 2. Intentional Changes Detected

List schema changes or features that appear intentional:
- New fields added
- Deprecated fields removed
- Enum values added/changed
- Breaking changes (if documented)

### 3. Environment Artifacts (Last Resort)

Only use this category if you've exhausted all other explanations:
- URL format differences unexplainable by code
- Unexplained but consistent differences

**Use sparingly** - most things in this category are actually bugs.

### 4. Performance Analysis

Report from `analyze_replay_performance`:
- **Regressions**: Endpoints significantly slower
- **Improvements**: Endpoints significantly faster
- **Reliability concerns**: High-variance endpoints
- **Critical**: Any endpoint >2x slower or >500ms average

Include statistical significance and effect sizes.

### 5. Profile Updates

**Profile Completeness Status:**
```
Total deltas: 455
- Dropped: 194 (32%)
- Labeled automatically: 238 (52%)
- Unlabeled: 23 (16%)

Profile completeness: 84% (goal: 100%)
```

**Rules created this iteration:**
- List filter rules created (DROP/LABEL)
- List ID mappings created
- List URL transformation rules created

**Next iteration needed:** [Yes/No]
- If Yes: Specify what patterns remain unlabeled
- If Yes: Recommend specific rules to add
- **If mappings were created**: MUST re-run replay to test transformations and label any new deltas

### 6. Recommendations

**Immediate actions:**
- Priority bugs to fix
- Profile refinement steps (if unlabeled deltas remain)
- Re-run replay with updated profile (if rules were added)

**Long-term actions:**
- Suggested retests after bug fixes
- Additional test scenarios needed
- Profile maintenance guidelines

---

## Checklist Before Finalizing Analysis

Before submitting your analysis, verify:

### Investigation Completeness
- [ ] Used MCP tool `summarize_deltas` to get overview
- [ ] Investigated ALL high-severity deltas with MCP tool `get_delta_request_context`
- [ ] For endpoints with query parameters: checked metadata vs parameters
- [ ] Looked for root causes (single bugs explaining many deltas)
- [ ] Ran MCP tool `analyze_replay_performance` for performance regressions

### Profile Completeness (CRITICAL)
- [ ] Ran `query_deltas(replay_id, unlabeled_only=true)` to check unlabeled count
- [ ] Created profile rules for ALL patterns using MCP tools (DROP/LABEL/MAP)
- [ ] Verified unlabeled delta count is 0 OR documented why remaining deltas can't be automated
- [ ] Used minimal labels (group by root cause, not individual delta)
- [ ] If mappings/transformations were created: flagged need for next iteration

### Quality Checks
- [ ] Did NOT label anything as "data-evolution" without ruling out bugs
- [ ] Provided structured output with bugs/changes/performance sections
- [ ] Included profile completeness percentage and status
- [ ] Recommended re-run if ID mappings were created
- [ ] Specified if another iteration is needed (unlabeled deltas > 0)

---

## Common Mistakes to Avoid

1. ❌ **Assuming data changed** when seeing different content
   - ✅ Investigate for pagination bugs, query parameter bugs

2. ❌ **Labeling each delta individually** instead of finding root causes
   - ✅ Find the single bug explaining 100+ deltas
   - ✅ Use ONE label per root cause, not one label per delta

3. ❌ **Stopping before profile is complete** (unlabeled deltas remain)
   - ✅ Iterate until `query_deltas(unlabeled_only=true)` returns 0 deltas
   - ✅ Every delta must be either DROPPED or LABELED

4. ❌ **Not testing mappings/transformations** (stopping after creating rules)
   - ✅ After creating mapping rules, MUST re-run replay
   - ✅ Mappings may reveal new deltas that need labeling

5. ❌ **Skipping metadata checks** for parameterized requests
   - ✅ Always check response metadata vs request parameters first

6. ❌ **Ignoring high-severity deltas** (status mismatches)
   - ✅ Investigate these immediately with full context

7. ❌ **Not running performance analysis**
   - ✅ Always check for performance regressions

8. ❌ **Creating ID mappings without checking for bugs first**
   - ✅ Different IDs at same position = likely pagination bug, not ID mismatch

9. ❌ **Labeling asset 404s without finding the new hash**
   - ✅ Search for value_mismatch showing OLD→NEW hash, create mapping

10. ❌ **Filter rules with incorrect path patterns**
    - ❌ WRONG: `path_pattern: "^\.posts\[\d+\]$"` (missing `$` prefix)
    - ✅ RIGHT: `path_pattern: "^\\$\\.posts\\[\\d+\\]$"` (includes `$` prefix)
    - **Critical**: JSON paths in deltas start with `$` (e.g., `$.posts[8]`, not `.posts[8]`)
    - **Regex escaping**: In path patterns, escape both the `$` and the `\.` → `^\\$\\.`
    - **Common failure**: Rules with patterns like `\.posts\[` won't match `$.posts[`
    - **Testing**: After creating rules, apply retroactively to verify they match

---

## Remember

- **ReGrade finds bugs by comparing identical data across software versions**
- **Your job is to identify CODE BUGS, not explain away differences**
- **One bug can cause hundreds of deltas - find that one bug**
- **Always check request parameters vs response metadata**
- **Performance matters - always analyze it**
- **Profile completeness is mandatory - iterate until unlabeled deltas = 0**
- **Use minimal labels - group deltas by root cause, not individual delta**
- **Mappings require re-testing - new deltas may appear after transformations work**

When in doubt, investigate deeper. Most differences are bugs.

**You are not done until every delta is labeled.**
