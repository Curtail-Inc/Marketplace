# Example ReGrade Analysis Report

This document shows the expected output format when analyzing a replay using the ReGrade skill.

**Replay ID:** `623593e7-a78d-4680-a609-e58b2dec5aff`
**Recording ID:** `b070ffb0-3788-49c3-ba33-6f0d29f48ec7`
**Total Deltas:** 617
**Analysis Date:** 2026-01-29

---

## Executive Summary

**Critical Bug Found:** Query parameter ignored in list endpoint

- **606 deltas** explained by a single pagination bug
- **11 deltas** are environment differences or version changes
- **0 performance regressions** detected
- **Profile created** with noise reduction rules

---

## 1. Bugs Identified

### Bug #1: Query parameter `page` ignored in list endpoint

**Severity:** Critical
**Affected Endpoint:** `GET /api/v2/admin/posts/`
**Delta Count:** 606 (98% of total deltas)

#### Description
The `page` query parameter is being completely ignored. The API always returns page 1 regardless of the requested page number.

#### Root Cause
Pagination logic is not reading the `page` parameter from the query string. The endpoint defaults to page 1 in all cases.

#### Evidence

**Request:**
```http
GET /api/v2/admin/posts/?page=2&limit=30&filter=...
```

**Expected Response (from recording):**
```json
{
  "meta": {
    "pagination": {
      "page": 2,
      "limit": 30,
      "pages": 2,
      "total": 38,
      "prev": 1,
      "next": null  // Last page
    }
  },
  "posts": [
    // Posts 31-38 (page 2)
  ]
}
```

**Actual Response (from replay):**
```json
{
  "meta": {
    "pagination": {
      "page": 1,      // ❌ Should be 2
      "limit": 30,
      "pages": 2,
      "total": 38,
      "prev": null,   // ❌ Should be 1
      "next": 2       // ❌ Should be null
    }
  },
  "posts": [
    // Posts 1-30 (page 1) ❌ Wrong page returned
  ]
}
```

#### Impact

- **Breaks pagination completely** - Users cannot access pages beyond the first
- **All content deltas are side effects** - The 606 deltas showing different post IDs, titles, content, etc. are all consequences of returning the wrong page
- **Client-side pagination broken** - UIs relying on pagination will malfunction

#### Side Effects Explained

All of these are consequences of returning page 1 instead of page 2:

- **Post ID mismatches** (8 deltas) - Different posts have different IDs
- **Post titles differ** (8 deltas) - Different posts have different titles
- **Post content differs** (500+ deltas) - All post fields differ because they're different posts
- **22 extra posts** - Page 1 returns posts 1-30, page 2 only had posts 31-38 (8 posts)
- **Pagination metadata wrong** - `prev`/`next` values reflect page 1 instead of page 2

This is NOT "data evolution" - this is a single bug with cascading effects.

#### Recommendation

**Priority: P0 - Critical**

1. **Fix pagination logic** to read `page` parameter from query string
2. **Add parameter validation** to ensure `page` is within valid range
3. **Add integration test** for multi-page list endpoints
4. **Re-run replay** after fix to verify resolution

**Suggested Fix Location:**
Check the request handler for `GET /api/v2/admin/posts/` - likely the parameter parsing or pagination logic initialization.

---

## 2. Intentional Changes Detected

### Change #1: URL Format - Relative to Absolute

**Delta Count:** 118
**Severity:** Low
**Category:** Environment difference

#### Description
URL fields changed from relative paths to absolute URLs with hostname.

#### Examples

| Field | Recording | Replay |
|-------|-----------|--------|
| `posts[*].url` | `/thirty-one/` | `http://localhost:8000/thirty-one/` |
| `users[*].url` | _(not present)_ | `http://localhost:8000/author/thomas/` |
| `tags[*].url` | _(not present)_ | `http://localhost:8000/tag/getting-started/` |

#### Analysis
This appears to be an intentional environment difference or configuration change:
- Recording environment returned relative URLs
- Replay environment returns absolute URLs with hostname
- Functionally equivalent for clients

#### Recommendation
**Action:** None required - labeled as `environment-url-format` in profile

If this is unintentional:
- Check if there's a configuration flag for URL format
- Verify recording and replay environments have same config

### Change #2: Asset Hash in Script Tag

**Delta Count:** 1
**Severity:** Low
**Category:** Version change

#### Description
JavaScript bundle filename has different version hash.

#### Evidence

**Status mismatch delta:**
```
GET /assets/ghost.min-bed13fa971b2b2c352507b7d16048f97.js
Status: 200 → 404
```

**Corresponding HTML change:**
```html
<!-- Recording -->
<script src="assets/ghost.min-bed13fa971b2b2c352507b7d16048f97.js"></script>

<!-- Replay -->
<script src="assets/ghost.min-NEWHASH.js"></script>
```

#### Analysis
This is a normal version change - asset filenames include content hashes for cache busting. When the JS bundle changes, the hash changes.

#### Recommendation
**Action:** ID mapping created for asset hashes

**How it works:**
1. **Learning:** Sensor compares HTML responses, learns `OLD_HASH` → `NEW_HASH` mapping from `<script src=...>` attributes
2. **Transformation:** In future requests, sensor rewrites URLs: `GET /assets/app-OLD.js` → `GET /assets/app-NEW.js`
3. **Result:** 404s eliminated - requests automatically use new hash

**Note:** The 404 in this replay is expected (first time seeing this version). After re-running with the learned mapping, the 404 will not occur.

---

## 3. Environment Artifacts

**Count:** 0

No unexplained differences that appear to be environment-specific.

**Note:** All differences were either bugs or intentional changes.

---

## 4. Performance Analysis

**Summary:** No significant performance regressions detected

### Performance Metrics

| Endpoint | Recording Mean | Replay Mean | Change | Significant? |
|----------|---------------|-------------|---------|--------------|
| POST /api/v2/admin/session | 957ms | 901ms | -56ms (-5.9%) | No (n=1) |
| GET / | 165ms | 156ms | -9ms (-5.6%) | No (n=1) |
| GET /api/v2/admin/posts/ | _(see note)_ | _(see note)_ | - | N/A |

**Note on pagination endpoint:** Due to the pagination bug, we cannot accurately compare performance - the endpoints are returning different data (page 1 vs page 2).

### Analysis

- **No critical regressions:** No endpoints became significantly slower
- **Minor improvements:** Most endpoints show slight improvements (5-10ms faster)
- **Low confidence:** Single samples per endpoint - need more data for statistical significance
- **Pagination endpoint:** Cannot assess until bug is fixed

### Recommendations

1. **Re-run performance analysis** after fixing pagination bug
2. **Collect more samples** (10+ per endpoint) for statistical significance
3. **Monitor** POST /api/v2/admin/session endpoint (slowest at ~900ms)

---

## 5. Profile Updates

**Profile:** `example-api-analysis` (v8)
**Profile ID:** `prof_71354e7e-6afe-4d9b-b8e0-72ad6c626470`

### Filter Rules Created

#### 1. Drop Timestamp Fields (Pure Noise)
- **Pattern:** `(updated_at|last_seen|created_at|published_at)$`
- **Action:** DROP
- **Rationale:** Timestamps always differ between recording and replay

#### 2. Label URL Format Differences (Environment)
- **Pattern:** `\.url$`
- **Delta Types:** response_body_difference, extra_field
- **Action:** LABEL as `environment-url-format`
- **Rationale:** Relative vs absolute URLs - environment difference

#### 3. Label Pagination Bug Side Effects
- **Pattern:** URL contains `page=`, any delta type on `/posts/` endpoint
- **Action:** LABEL as `side-effect-of-page-param-ignored`, `bug`
- **Rationale:** All content deltas on paginated endpoint are consequences of ignored parameter

#### 4. Label Asset Version Changes
- **Pattern:** URL ends with `.js`, `.css`, or `.map`, status_code_mismatch
- **Action:** LABEL as `asset-version-change`
- **Rationale:** Asset hashes change between versions - expected

### ID Mappings Created

#### 1. Asset Hashes in HTML
- **JSONPath:** `/html/body[*]/script[*]/@src`, `/html/head[*]/link[*]/@href`
- **Namespace:** `asset-hashes`
- **Rationale:** Handle version hashes in asset filenames

### Effect of Profile

- **Before:** 617 unlabeled deltas
- **After:** 606 labeled as bug side-effects, 11 as environment/version
- **Noise reduction:** ~2% pure noise (timestamps), 98% bug, 2% environment

---

## 6. Recommendations

### Immediate Actions

1. **Fix pagination bug** (P0 - Critical)
   - Location: `GET /api/v2/admin/posts/` handler
   - Issue: Not reading `page` query parameter
   - Test: Verify `?page=2` returns page 2, not page 1

2. **Re-run replay with ID mappings** (P1 - High)
   - The asset hash mappings were just created
   - Re-running will apply learned mappings
   - Should reduce asset-related deltas to zero

3. **Add pagination integration tests** (P1 - High)
   - Test multi-page list endpoints
   - Verify `page`, `limit`, `prev`, `next` all work correctly
   - Prevent regression

### Follow-up Actions

4. **Verify URL format is intentional** (P2 - Medium)
   - Check if relative vs absolute URLs are expected
   - Document the intended behavior

5. **Performance testing with more samples** (P2 - Medium)
   - Current analysis based on single samples
   - Collect 10+ samples per endpoint for statistical significance

6. **Apply profile to CI/CD** (P2 - Medium)
   - Use `example-api-analysis` profile for future replays
   - Automate noise filtering

---

## 7. Next Steps

### After Fixing the Bug

1. **Create new replay:**
   ```bash
   regrade replay --rec-id b070ffb0-3788-49c3-ba33-6f0d29f48ec7 \
     --target http://fixed-version:8080 \
     --profile example-api-analysis
   ```

2. **Expected result:** ~606 deltas should disappear (only environment differences remain)

3. **If new deltas appear:** Investigate as potential new bugs

### Continuous Testing

- **Integrate into CI/CD:** Run replay on every deployment
- **Monitor delta trends:** Increasing deltas = potential regressions
- **Update profile:** Add new noise patterns as discovered

---

## Summary

**One critical bug found,** explaining 98% of deltas:
- Query parameter `page` is ignored in list endpoint
- Breaks pagination completely
- All content differences are side effects of this single bug

**Not data evolution, not environment issues - this is a code bug.**

Fix the pagination logic and re-test.
