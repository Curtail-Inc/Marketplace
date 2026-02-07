# ID Mapping and Request Transformation Guide

## What Are ID Mappings?

ID mappings allow the ReGrade sensor to handle dynamic identifiers that change between software versions but refer to the same logical entities.

### The Problem

When replaying recorded traffic against a new version:
- Database IDs may be different (UUIDs, auto-increment IDs)
- Asset filenames may have version hashes (`app-ABC123.js` vs `app-XYZ789.js`)
- Content-addressed identifiers change with content

Without mappings, ReGrade would report these as bugs even though they're expected differences.

### The Solution

ID mappings teach the sensor to:
1. **Learn** the OLD_ID → NEW_ID mapping during replay
2. **Transform** future requests that reference OLD_ID to use NEW_ID
3. **Compare** responses correctly by understanding equivalence

---

## How ID Mapping Works

### Phase 1: Learning (Initial Replay)

During the first replay:

1. **Sensor compares responses** between recording and replay
2. **Identifies value differences** at configured JSONPath locations
3. **Learns mappings**: `OLD_VALUE` → `NEW_VALUE`
4. **Stores mappings** in the profile namespace

**Example:**
```json
// Recording response
{
  "posts": [
    {"id": "5d39f047", "title": "Hello"},
    {"id": "5d39f048", "title": "World"}
  ]
}

// Replay response
{
  "posts": [
    {"id": "8f2a1039", "title": "Hello"},
    {"id": "8f2a103a", "title": "World"}
  ]
}

// Learned mapping
Namespace "post-ids":
  "5d39f047" → "8f2a1039"
  "5d39f048" → "8f2a103a"
```

### Phase 2: Transformation (Subsequent Requests)

For later requests in the replay that reference these IDs, the sensor transforms BOTH requests and responses:

**Request transformation (URLs and bodies):**
```http
# Original recorded request
GET /posts/5d39f047/comments

# Transformed request (sent to replay target)
GET /posts/8f2a1039/comments
```

**Request URL example (asset hashes):**
```http
# Original recorded request
GET /assets/app.min-bed13fa971b2b2c352507b7d16048f97.js

# Sensor looks up learned mapping: OLD_HASH → NEW_HASH
# Transformed request (sent to replay target)
GET /assets/app.min-NEWHASH.js
```

**Response transformation (for comparison):**
```json
// Actual replay response
{"post_id": "8f2a1039", "comments": [...]}

// Transformed for comparison (mapped back to recording values)
{"post_id": "5d39f047", "comments": [...]}
```

This allows correct comparison with the original recording and prevents 404s on changed IDs.

---

## When to Use ID Mappings

### Use ID Mapping For:

#### 1. Entity IDs
- UUIDs: `"user_id": "550e8400-e29b-41d4-a716-446655440000"`
- ObjectIDs: `"_id": "507f1f77bcf86cd799439011"`
- Auto-increment IDs: `"id": 12345`
- Any identifier for database entities

**JSONPath Example:** `$.users[*].id`, `$.posts[*].user_id`

#### 2. Asset Hashes in Filenames
- JavaScript bundles: `app.min-ABC123XYZ.js`
- CSS files: `styles-DEF456UVW.css`
- Images: `logo-GHI789RST.png`
- Source maps: `bundle-JKL012MNO.js.map`

**JSONPath Example:** `/html/body[*]/script[*]/@src`, `/html/head[*]/link[*]/@href`

#### 3. Content-Addressed Values
- Content hashes: `"hash": "sha256:abc123..."`
- ETags: `"etag": "W/\"5d8c72a5e0\""`
- Version tokens: `"version_token": "v2_abc123"`

**JSONPath Example:** `$.content[*].hash`, `$.etag`

#### 4. Request/Session IDs (when referenced later)
- If a response returns a request ID that's used in subsequent requests
- Example: `create_session` returns `session_id`, later requests use it

**JSONPath Example:** `$.session.id`, `$.transaction_id`

### Do NOT Use ID Mapping For:

#### Pure Noise (use DROP instead)
- Timestamps: `updated_at`, `created_at`
- Request trace IDs never referenced again
- Random nonces, CSRF tokens (unless reused)

#### Environment Differences (use LABEL instead)
- URL format changes: `/path` vs `http://host/path`
- Hostname differences
- Port numbers

#### Content Differences (investigate as bugs first!)
- If items at same array position have completely different IDs AND different content
- This usually means pagination bug, not ID mismatch

---

## How Mappings Work: Learning + Transformation

ID mappings are a single mechanism that handles BOTH learning and transformation:

### Learning Phase (Response Comparison)

The sensor compares responses at the configured JSONPath:

**What it does:**
- Extracts values from recording response at JSONPath
- Extracts values from replay response at same JSONPath
- Learns mappings: `RECORDING_VALUE` → `REPLAY_VALUE`
- Stores mappings in namespace

**Example:**
```python
create_id_mapping(
  json_path="$.posts[*].id",
  namespace="post-ids"
)
```

Sensor learns:
- `"abc-123"` (recording) → `"xyz-789"` (replay)
- `"def-456"` (recording) → `"uvw-012"` (replay)

### Transformation Phase (Request + Response)

The sensor applies learned mappings to transform:

**1. Request URLs:**
```http
# Recorded request referenced old ID
GET /posts/abc-123/comments

# Sensor transforms URL using learned mapping
GET /posts/xyz-789/comments
```

**2. Request bodies:**
```json
// Recorded request body
{"post_id": "abc-123"}

// Transformed before sending
{"post_id": "xyz-789"}
```

**3. Responses (for comparison):**
```json
// Actual replay response
{"id": "xyz-789", "title": "Hello"}

// Inverse transform for comparison
{"id": "abc-123", "title": "Hello"}
```

### Key Points

- **One mechanism, multiple uses:** Same JSONPath mapping handles all transformations
- **Bidirectional:** Recording→Replay for requests, Replay→Recording for comparisons
- **URL transformation included:** Learned mappings automatically apply to request URLs
- **Prevents 404s:** Asset hash changes don't cause 404s after mapping is learned

---

## Creating ID Mappings

### Syntax

```python
create_id_mapping(
  profile_id="prof_abc123...",  # Profile to add mapping to
  json_path="$.items[*].id",     # JSONPath where IDs appear
  namespace="item-ids"            # Optional: groups related IDs
)
```

### JSONPath Support

**Arrays:**
- `$.posts[*].id` - IDs in all posts
- `$.users[0].id` - ID in first user only
- `$.data[*].comments[*].author_id` - Nested arrays

**Nested Objects:**
- `$.post.author.id` - Nested object path
- `$.metadata.user_ref` - Deep nesting

**XPath (for HTML/XML):**
- `/html/body[*]/script[*]/@src` - Script src attributes
- `/html/head[*]/link[@rel='stylesheet']/@href` - CSS hrefs
- `//img/@src` - All image sources

### Namespaces

Namespaces group related IDs:

```python
# All author IDs in same namespace
create_id_mapping(json_path="$.posts[*].author_id", namespace="author-ids")
create_id_mapping(json_path="$.comments[*].author_id", namespace="author-ids")

# Asset hashes in same namespace
create_id_mapping(json_path="/html/body[*]/script[*]/@src", namespace="asset-hashes")
create_id_mapping(json_path="/html/head[*]/link[*]/@href", namespace="asset-hashes")
```

**Benefits:**
- Mapping learned at one path applies to all paths in namespace
- Consistent handling of related identifiers
- Easier to reason about mappings

---

## Best Practices

### 1. Map Early in the Response

If an ID appears in multiple places, map it at the first occurrence:
- Response header → Map there
- Top-level response → Map at top level
- First array element → Map at array level

### 2. Use Specific Paths When Possible

**Prefer:**
- `$.users[*].id` (specific to user IDs)
- `$.posts[*].author_id` (specific to author references)

**Avoid:**
- `$..id` (matches ALL id fields - too broad)
- `$.*.id` (ambiguous)

### 3. Group Related IDs in Namespaces

If `user_id`, `author_id`, `owner_id` all refer to users, use the same namespace:
```python
namespace="user-ids"
```

### 4. Verify Mappings Make Sense

After creating mapping, check a few examples:
- Do the mapped values have the same content/context?
- Are positions in arrays consistent?
- If not → might be a pagination bug, not ID mismatch

### 5. Re-run Replay After Creating Mappings

Mappings are learned during the FIRST replay where they're configured.

**Workflow:**
1. First replay: Sensor learns mappings, many deltas remain
2. Create ID mapping rules in profile
3. **Second replay**: Mappings are applied, deltas reduce significantly
4. Continue analysis with transformed data

Always recommend a second replay after adding mappings.

---

## Examples

### Example 1: User IDs

**Problem:** User IDs differ between recording and replay

```json
// Recording
{"users": [{"id": "abc-123", "name": "Alice"}]}

// Replay
{"users": [{"id": "xyz-789", "name": "Alice"}]}
```

**Solution:**
```python
create_id_mapping(
  profile_id="prof_...",
  json_path="$.users[*].id",
  namespace="user-ids"
)
```

**Result:** `abc-123` → `xyz-789` mapping learned, applied to future requests

### Example 2: Asset Hashes

**Problem:** Script tag has different hash

```html
<!-- Recording -->
<script src="assets/app.min-abc123.js"></script>

<!-- Replay -->
<script src="assets/app.min-xyz789.js"></script>
```

**Solution:**
```python
create_id_mapping(
  profile_id="prof_...",
  json_path="/html/body[*]/script[*]/@src",
  namespace="asset-hashes"
)
```

**Result:** Asset hash differences handled automatically

### Example 3: Referenced IDs

**Problem:** Response returns post IDs, later requests use them

```
1. GET /posts → {"posts": [{"id": "post-123"}]}
2. GET /posts/post-123/comments → ...
```

If replay has different ID (`post-xyz`), request #2 needs transformation.

**Solution:**
```python
create_id_mapping(
  profile_id="prof_...",
  json_path="$.posts[*].id",
  namespace="post-ids"
)
```

**Result:** Request #2 automatically transformed to `GET /posts/post-xyz/comments`

---

## Troubleshooting

### Mapping Not Applied

**Check:**
1. Is JSONPath correct? Test with sample response
2. Is namespace spelled consistently?
3. Did you re-run replay after adding mapping?
4. Is the ID actually at that path in the response?

### Too Many Mappings Learned

**Issue:** Mapping too broad, catching unrelated fields

**Fix:** Make JSONPath more specific
- Change `$..id` → `$.users[*].id`
- Add namespace to separate different ID types

### Mapped Values Still Show as Deltas

**Possible causes:**
1. Mapping hasn't been learned yet (first replay)
2. JSONPath doesn't match where ID appears
3. This isn't an ID mismatch - might be a bug!

**Investigate:** Are the mapped items actually the same entity?
- Check surrounding content
- Verify positions in arrays match
- Could be pagination bug, not ID mismatch

---

## When Mappings Suggest a Bug

If you create an ID mapping and find:
- Mapped items have different content
- Array positions don't align
- Context around the ID doesn't match

**This is likely a BUG, not an ID mismatch!**

Example:
```json
// Recording
{"posts": [
  {"id": "123", "title": "First Post", "views": 100}
]}

// Replay
{"posts": [
  {"id": "456", "title": "Different Post", "views": 500}
]}
```

**This is NOT an ID mapping issue** - the posts are completely different. Likely a pagination or filter bug.

---

## Summary

- **ID mappings** handle dynamic identifiers (UUIDs, hashes, IDs)
- **Learning phase** compares responses to build OLD→NEW mapping
- **Transformation phase** applies mappings to subsequent requests
- **Use for:** Entity IDs, asset hashes, content-addressed values
- **Don't use for:** Timestamps (DROP), environment diffs (LABEL), bugs (investigate!)
- **Always re-run replay** after adding mappings to apply them
- **Verify mappings** make sense - misalignment suggests bug, not ID mismatch
