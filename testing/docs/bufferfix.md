# BufferFix / srcds_patch analysis

Context: [hlmod thread](https://hlmod.net/threads/cs-s-v34-bufferfix-fiks-krivogo-bufera-valve-rc-unknown-command.63301/), [post with srcds_patch](https://hlmod.net/threads/cs-s-v34-bufferfix-fiks-krivogo-bufera-valve-rc-unknown-command.63301/page-2#post-656715), [WeSTManCoder/BufferFix](https://github.com/WeSTManCoder/BufferFix), archive on branch `bufferfix` (`srcds_patch (1).rar`).

## Problem

CS:S v34 dedicated server on modern Linux (Debian 9+, newer glibc) often:

- hangs or floods the console with `Unknown command ":"` / similar garbage
- fails to load configs / SourceMod unreliably
- prints `Incorrect price blob version!` and `Assertion Failed: !"Implement me!"`

Root cause: engine code uses `memcpy` on overlapping buffers. Older glibc was more permissive; modern `memcpy` is undefined for overlaps. `memmove` is the correct call.

## Approaches

| Approach | What it does | Pros | Cons |
|---|---|---|---|
| Edit `cstrike/cfg/valve.rc` | Minimal cfg (no comments / less parse work) | Tiny workaround | Does **not** fix the underlying memcpy bug; may still fail |
| BufferFix VSP | Runtime hook: `memcpy` → `memmove` via subhook | Clean, reversible | Needs `_i486` suffix on v34; loads after some early parsing |
| **srcds_patch (bruno_args)** | Binary rewrite of engine/server/steamclient | No VSP; works before early cfg parse; silences two spam messages | Opaque binary patch of Valve `.so` files |

## What srcds_patch actually changes (validated)

Compared stock binaries from `srcds_css34_l_a.zip` / `srcds_css34_l_eSTEAMATiON.zip` to the rar contents (same file sizes, in-place edits):

1. **`bin/engine_{amd,i486,i686}.so`**
   - All `R_386_PC32` relocations that pointed at `memcpy` were retargeted to `memmove`.
   - Example (`engine_i486.so`): stock `memcpy` relocs **126** → patched **0**; `memmove` **186** → **312**.
   - The `memcpy` `.dynsym` entry is zeroed so the dynamic linker no longer binds `memcpy` for those sites.

2. **`cstrike/bin/server_i486.so`**
   - Same memcpy→memmove relocation rewrite (stock memcpy relocs **193** → **0**).

3. **`bin/steamclient_i486.so`**
   - Three call sites that push/`call` the `"Assertion Failed: !"Implement me!"` path are replaced with `jmp +0x0a` + NOPs (message suppressed only; string left in binary).

This matches the author’s claim: BufferFix is unnecessary after the patch, and the two noisy messages are muted. The patch is **technically valid** and safe to use for smoke tests on modern distros.

## Recommendation for CI

- Prefer **srcds_patch** for Debian 9+ / modern CentOS-family images.
- Keep the **valve.rc** minimal rewrite as a cheap extra (harmless with the patch).
- BufferFix VSP remains a valid alternative when you cannot replace engine binaries.

Do not treat srcds_patch as open-source SourceMod code: it is a binary patch of proprietary server libraries. CI downloads it from the `bufferfix` branch and applies it onto a freshly fetched stock server.
