# Jules: daily SourceMod / Metamod version bump

Use this as the **daily scheduled task** prompt for Jules. Goal: when AlliedMods publishes newer git builds, bump `sm12-latest` and `sm13-latest`, open **one** PR, and let CI prove smoke + botplay (SDKHooks / SDKTools).

## Task prompt (copy into Jules)

```
Repository: fmu1337/sourcemod-css34

1. Run: builder/scripts/resolve-upstream-tips.sh
   - Exit 0 → no upstream changes; stop (no PR).
   - Exit 2 → new SM 1.12, SM 1.13, or MM 1.12 tip; continue.

2. Resolve full SHAs (never guess):
   - SM 1.12: git fetch origin 1.12-dev on alliedmodders/sourcemod; tip rev-list count = build number.
   - SM 1.13: git fetch origin master on alliedmodders/sourcemod.
   - MM 1.12: git fetch origin 1.12-dev on alliedmodders/metamod-source.

3. Update ALL of these (source of truth is builder/lines.json):
   - builder/lines.json               ← edit pins here, then run python3 builder/lines.py gen
   - builder/versions.env             ← generated; do not edit by hand
   - builder/checkout-deps.sh          ← MM fallback commit (easy to forget)
   - builder/write-build-stamps.sh     ← MM fallback commit (easy to forget)
   - testing/versions/matrix.json      ← lines AND releases AND metamod_pins
   - .github/workflows/test-server.yml ← sm_expect / mm_expect / sm_commit / mm_commit in build-linux,
                                         test-built-debian (debian:11 AND debian:latest rows),
                                         test-built-botplay-matrix, test-built-rhel, test-built-smoke,
                                         test-built-botplay-extra; tag + asset names in test-release-botplay
   - .github/workflows/build.yml       ← windows job SM_VERSION_EXPECT and wine-smoke matrix sm_expect
                                         (NOT checked by check-version-pins.sh — Windows smoke goes red)
   - .github/workflows/release.yml     ← tag → CSS34_LINE mappings (new base tag per new SM rev)
   - README.md                         ← "What to install" + version matrix + releases tables
   - testing/README.md                 ← test-release-botplay table
   - docs/SM13_LATEST.md               ← if sm13-latest SM pin changed
   - pins.SM_KHOOK.merge_master in lines.json equals the sm13-latest commit today; do NOT bump it
     with sm13-latest (moving it means redoing the KHook merge, see docs/MM20_KHOOK.md)

4. matrix.json rules:
   - Rename release key when SM rev changes (e.g. 1.12.0.7245-mm1.12.0 → 1.12.0.7253-mm1.12.0).
   - Add/update 1.13.0.<rev>-mm1.12.0 for sm13-latest.
   - Update metamod_pins "1.12-<rev>" when MM 1.12 moves.
   - sm13-mm20 still uses SM 7404 (SM_DEV_*) with MM 2.0; do not reintroduce sm13-dev.

5. Before opening PR, MUST pass locally:
   python3 builder/lines.py check

6. Open ONE draft PR. Do NOT duplicate if cursor/* PR already exists for the same pins.
   Title: "Bump sm12-latest (SM <rev>) and sm13-latest (SM <rev>) + MM <rev>"

7. Wait for CI Test Server workflow:
   - build-linux (all lines)
   - test-built-debian (smoke, sdkhooks gamedata)
   - test-built-botplay-matrix (sdkhooks OnTakeDamage + sdktools probe)

8. If CI fails on sm12-latest or sm13-latest only, fix patches in builder/patches/ — do not weaken CI checks.

9. Do NOT merge. Leave PR for human review.

10. After a human merges it, the release is a new base tag pushed by a human, e.g.
    git tag 1.13.0.<rev>-mm1.12.0 && git push origin 1.13.0.<rev>-mm1.12.0
    release.yml builds it, smokes the public URLs and switches line-sm13-latest.
```

## Why Jules PR #57 was incomplete

PR #57 updated `versions.env` and CI build matrix but **missed**:

| Missed file | Symptom |
|-------------|---------|
| `builder/checkout-deps.sh` | Local builds without env could still fetch MM git1224 |
| `builder/write-build-stamps.sh` | Same stale MM fallback |
| `matrix.json` `releases` | Key still `1.12.0.7245` with old 7245/1224 inside |
| `matrix.json` | No `1.13.0.7472-mm1.12.0` release entry |
| `README.md` | No sm13-latest release row |
| `test-server.yml` `test-release-botplay` | Tag still `1.12.0.7245-mm1.12.0` |

`testing/scripts/check-version-pins.sh` now fails CI if any of these drift. It covers only
`sm12-latest`, `sm13-latest` and MM 1.12 in `versions.env`, `matrix.json`, `test-server.yml`,
`release.yml` and the two fallbacks — not `build.yml`, the README / docs tables, or the other three lines.

## Lines to bump daily

| Line | SourceMod branch | Metamod |
|------|------------------|---------|
| `sm12-latest` | `1.12-dev` on alliedmodders/sourcemod | `1.12-dev` on alliedmodders/metamod-source |
| `sm13-latest` | `master` on alliedmodders/sourcemod | same MM 1.12 pin as sm12-latest |

Do **not** bump `sm13-mm20` (7404 + MM 2.0) unless explicitly asked. `sm13-dev` is retired.

## Verification commands

```bash
# Upstream vs pinned
builder/scripts/resolve-upstream-tips.sh

# Regenerate after editing builder/lines.json
python3 builder/lines.py gen

# All pins consistent (runs in CI on version-related PRs)
python3 builder/lines.py check
```

`check-version-pins.sh` remains a compatibility entry point for `lines.py check`.
The generated-file check covers all pins. Existing cross-file checks remain in
`check-version-copies.sh` until T4.1 generates CI matrices and removes fallbacks.
