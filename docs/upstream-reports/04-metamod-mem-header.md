# episode1 provider needs an explicit tier0/mem.h include

Status: **draft for owner submission; not filed upstream**.
Evidence is existing downstream code/notes, not a fresh reproduction in this
change. Re-check the upstream tip and attach the requested logs before filing.

Target: alliedmodders/metamod-source.

The Source1 provider uses `MemAllocScratch` without directly including its
own declaration. Newer SDKs supply it transitively; the episode1 SDK does not.
The downstream fix adds `#include <tier0/mem.h>` next to the KeyValues include.

### Minimal reproduction

1. Check out Metamod `9fd977df3b49ec76cdf865a4af13a90c0f5c8814` (1.12-dev,
   git1226), with the episode1 SDK and the downstream episode1 build setup.
2. Omit only the `PYMEM` include insertion from the linked patch script.
3. Build the episode1 target. The affected translation unit is
   `core/provider/provider_ep2.cpp`; in MM 2.0 it moved to
   `core/provider/source/provider_source.cpp`.
4. Add `#include <tier0/mem.h>` and rebuild the same target.

Expected: the provider includes declarations for the functions it uses.
Recorded downstream failure: `MemAllocScratch` is undeclared in this SDK build.
Exact compiler text should be attached from a current reproduction.

### Proposed fix and regression checks

Include the header explicitly, guarding it by SDK only if another supported
SDK lacks the header. Compile episode1 plus a newer Source1 SDK on Linux and
Windows; verify the include does not change allocator-selection macros.

Downstream implementation: [pinned patch script](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/builder/patches/apply-mmsource-v112.sh).
