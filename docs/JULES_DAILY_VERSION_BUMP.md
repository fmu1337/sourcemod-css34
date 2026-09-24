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

3. Update ALL of these (source of truth is builder/versions.env):
   - builder/versions.env
   - builder/checkout-deps.sh          ← MM fallback commit (easy to forget)
   - builder/write-build-stamps.sh     ← MM fallback commit (easy to forget)
   - testing/versions/matrix.json      ← lines AND releases AND metamod_pins
   - .github/workflows/test-server.yml ← build-linux, test-built-debian, botplay matrix, release-botplay tag
   - .github/workflows/release.yml     ← tag → CSS34_LINE mappings
   - README.md                         ← version table + releases table + git tag examples
   - docs/SM13_LATEST.md               ← if sm13-latest SM pin changed

4. matrix.json rules:
   - Rename release key when SM rev changes (e.g. 1.12.0.7245-mm1.12.0 → 1.12.0.7253-mm1.12.0).
   - Add/update 1.13.0.<rev>-mm1.12.0 for sm13-latest.
   - Update metamod_pins "1.12-<rev>" when MM 1.12 moves.
   - sm13-dev line keeps SM 7404 but shares MM 1.12 pin → update its metamod_commit too.

5. Before opening PR, MUST pass locally:
   chmod +x testing/scripts/check-version-pins.sh
   testing/scripts/check-version-pins.sh

6. Open ONE draft PR. Do NOT duplicate if cursor/* PR already exists for the same pins.
   Title: "Bump sm12-latest (SM <rev>) and sm13-latest (SM <rev>) + MM <rev>"

7. Wait for CI Test Server workflow:
   - build-linux (all lines)
   - test-built-debian (smoke, sdkhooks gamedata)
   - test-built-botplay-matrix (sdkhooks OnTakeDamage + sdktools probe)

8. If CI fails on sm12-latest or sm13-latest only, fix patches in builder/patches/ — do not weaken CI checks.

9. Do NOT merge. Leave PR for human review.
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

`testing/scripts/check-version-pins.sh` now fails CI if any of these drift.

## Lines to bump daily

| Line | SourceMod branch | Metamod |
|------|------------------|---------|
| `sm12-latest` | `1.12-dev` on alliedmodders/sourcemod | `1.12-dev` on alliedmodders/metamod-source |
| `sm13-latest` | `master` on alliedmodders/sourcemod | same MM 1.12 pin as sm12/sm13-dev |

Do **not** bump `sm13-dev` (7404) or `sm13-mm20` unless explicitly asked.

## Verification commands

```bash
# Upstream vs pinned
builder/scripts/resolve-upstream-tips.sh

# All pins consistent (runs in CI on version-related PRs)
testing/scripts/check-version-pins.sh
```
