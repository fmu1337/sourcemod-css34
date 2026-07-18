# BufferFix / srcds_patch (CS:S v34 on modern glibc)

Context: [hlmod thread](https://hlmod.net/threads/cs-s-v34-bufferfix-fiks-krivogo-bufera-valve-rc-unknown-command.63301/),
[post with srcds_patch](https://hlmod.net/threads/cs-s-v34-bufferfix-fiks-krivogo-bufera-valve-rc-unknown-command.63301/page-2#post-656715),
[WeSTManCoder/BufferFix](https://github.com/WeSTManCoder/BufferFix).

## Problem

CS:S v34 dedicated server on modern Linux (Debian 9+, newer glibc) often:

- hangs or floods the console with `Unknown command ":"` / similar garbage
- fails to load configs / SourceMod unreliably
- prints `Incorrect price blob version!` and `Assertion Failed: !"Implement me!"`

Root cause: engine / `server_i486.so` use `memcpy` on **overlapping** buffers.
Older glibc was permissive; modern `memcpy` is undefined for overlaps.
`memmove` is the correct call.

## Approaches

| Approach | What it does | Pros | Cons |
|---|---|---|---|
| Edit `cstrike/cfg/valve.rc` | Minimal cfg (less parse work) | Tiny workaround | Does **not** fix memcpy |
| BufferFix VSP | Runtime hook `memcpy` → `memmove` | Clean, reversible | Needs `_i486` suffix; loads after some early parse |
| **ELF rewrite (this repo)** | Same binary edits as bruno_args `srcds_patch`, done by script | No VSP; no patched blobs in git; works before early cfg | Touches proprietary `.so` files in the **server tree** (not in this repo) |

## What the script changes

`testing/scripts/patch-srcds-bufferfix.py` (via `apply-srcds-patch.sh`) edits a
stock server tree in place. Validated against the historical hlmod rar
(`srcds_patch (1).rar`): same sizes, `memcpy` relocation count → **0**.

### 1. `bin/engine_{amd,i486,i686}.so` and `cstrike/bin/server_i486.so`

1. Find ELF32 `.dynsym` indices for `memcpy` and `memmove`.
2. For every relocation in `.rel.dyn` / `.rel.plt` whose symbol is `memcpy`,
   rewrite `r_info` so the symbol is `memmove` (relocation type unchanged).
3. Zero the primary `memcpy` `.dynsym` entry (16 bytes) and its `.gnu.version`
   slot so the loader no longer binds `memcpy` for those sites.

Example (`engine_i486.so` from `srcds_css34_l_a.zip`): stock `memcpy` relocs
**126** → **0**; `memmove` **186** → **312**.

### 2. `bin/steamclient_i486.so` (noise only)

Three call sites that push/`call` the `"Assertion Failed: !"Implement me!"`
string are replaced with `jmp +0x0a` + NOPs (string left in the binary).
Optional: `SRCDS_PATCH_STEAMCLIENT=0`.

### Not shipped in git

We do **not** keep pre-patched Valve binaries or the rar in this repository.
CI downloads stock zips via `fetch-server.sh`, then runs the script.

## Apply locally

```bash
SERVER_DIR=/path/to/css34 \
  APPLY_SRCDS_PATCH=1 testing/scripts/apply-srcds-patch.sh
# or directly:
python3 testing/scripts/patch-srcds-bufferfix.py /path/to/css34
```

Keep the minimal `valve.rc` rewrite as a cheap extra (`APPLY_VALVE_RC=1`).

## Recommendation for CI

- Default: run the ELF rewrite on Debian 9+ / modern RHEL-family images.
- BufferFix VSP remains valid when you cannot rewrite engine binaries.
- Do not treat these edits as SourceMod source: they patch proprietary server libs.
