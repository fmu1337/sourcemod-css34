# cstrike should use FindDataMapInfo actual_offset for player datamaps

Status: **draft for owner submission; not filed upstream**.
Evidence is existing downstream code/notes, not a fresh reproduction in this
change. Re-check the upstream tip and attach the requested logs before filing.

Target: alliedmodders/sourcemod.

`GetPlayerVarAddressOrError` reads `typedescription_t::fieldOffset` directly
after `FindInDataMap`. In the episode1 port this relies on an incomplete or
incompatible SDK description of `typedescription_t`. SourceMod already exposes
`FindDataMapInfo` and its resolved `sm_datatable_info_t.actual_offset`.

### Minimal reproduction

1. At SourceMod `2e229b111534b1be007dc3bd9acfcf2fc472e893`, enable the downstream
   episode1 cstrike build. Keep other compatibility changes fixed.
2. Remove only the `GetPlayerVarAddressOrError` replacement from the linked
   script; compile `extensions/cstrike/natives.cpp` against the episode1 SDK.
3. Compare with the same build using `FindDataMapInfo(pMap, pszBaseVar, &info)`
   and `interimOffset = info.actual_offset`.

Expected: the extension uses the core's SDK-independent field-offset API.
The old path depends on direct SDK struct fields; the replacement removes that
dependency. A standalone vanilla upstream episode1 cstrike build is not claimed:
the extension requires the other downstream episode1-enablement changes.

### Proposed fix and regression checks

Replace only the lookup/offset extraction, preserving missing-property error
handling. Compile the extension for episode1 and the supported modern CSS SDK.
For runtime coverage, join one player, exercise the cstrike native calling this
helper, and compare its result with a core datamap lookup for the same property.
Include inherited fields and a missing property. Attach compiler diagnostics
and the chosen property/native when filing; no fresh diagnostic is claimed here.

Downstream implementation: [pinned patch script](https://github.com/fmu1337/sourcemod-css34/blob/7c27aca8105a5a6c5702c0a485212c9d9c977951/builder/patches/apply-sourcemod-v112.sh).
