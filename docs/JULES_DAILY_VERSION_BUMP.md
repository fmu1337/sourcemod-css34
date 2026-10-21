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

3. Edit pins in builder/lines.json, then run: python3 builder/lines.py gen
   Generated (do not edit by hand):
   - builder/versions.env
   - builder/generated/ci-matrix.json
   - builder/generated/tag-map.sh
   - the install and version tables in README.md
   CI loads those matrices at runtime. release.yml sources the tag map.
   When the MM 1.12 commit moves, also update the hand-written fallback SHA in
   builder/checkout-deps.sh and builder/write-build-stamps.sh. Do not edit smoke scripts.
   testing/versions/matrix.json is historical compatibility/reference data, not a pin source.
   docs/SM13_LATEST.md if the sm13-latest SM pin changed.
   pins.SM_KHOOK.merge_master equals the sm13-latest commit today; do NOT bump it
   with sm13-latest (moving it means redoing the KHook merge, see docs/MM20_KHOOK.md).
   sm13-mm20 still uses SM 7404 (SM_DEV_*) with MM 2.0; do not reintroduce sm13-dev.

4. Before opening PR, MUST pass locally:
   python3 builder/lines.py check

5. Open ONE draft PR. Do NOT duplicate if cursor/* PR already exists for the same pins.
   Title: "Bump sm12-latest (SM <rev>) and sm13-latest (SM <rev>) + MM <rev>"

6. Wait for CI Test Server workflow:
   - build-linux (all lines)
   - test-built-debian (smoke, sdkhooks gamedata)
   - test-built-botplay-matrix (sdkhooks OnTakeDamage + sdktools probe)

7. If CI fails on sm12-latest or sm13-latest only, fix patches in builder/patches/ — do not weaken CI checks.

8. Do NOT merge. Leave PR for human review.

9. After a human merges it, the release is a new base tag pushed by a human, e.g.
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

`testing/scripts/check-version-pins.sh` now fails CI when `python3 builder/lines.py gen`
would change a generated file, when a workflow copies a full commit SHA back in, or when
the MM 1.12 fallback in `checkout-deps.sh` / `write-build-stamps.sh` drifts. `matrix.json`
is no longer part of that check.

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
`lines.py gen` refreshes `versions.env`, the CI matrices, the release tag map, and the
README pin tables. `check-version-copies.sh` still requires the MM 1.12 fallback SHA in
`checkout-deps.sh` and `write-build-stamps.sh`.
