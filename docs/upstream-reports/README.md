# Upstream report drafts

These reports are prepared for issue #101. **The owner submits them**; no upstream
issue has been opened by this change. Each file provides a proposed report,
minimal reproduction procedure, expected result and downstream evidence.

Evidence links are pinned to commit `7c27aca` so archiving KHook code does not
break the references. Existing downstream findings are distinguished from fresh
verification: this documentation change did not rebuild packages or run srcds.
Before submission, check whether upstream has already fixed the issue, reproduce
with the stated dependency revisions, and attach actual logs or a reduced harness.
Do not describe a downstream compatibility build as an unmodified upstream build.

## Reports

- [GameConfigs must inspect the loaded engine without loading a second variant](01-gameconfigs-noload.md)
- [cstrike should use FindDataMapInfo actual_offset for player datamaps](02-cstrike-datamap.md)
- [Linux modules must declare their pthread/rt dependencies on pre-2.34 glibc](03-pthread-rt-needed.md)
- [episode1 provider needs an explicit tier0/mem.h include](04-metamod-mem-header.md)
- [episode1 link ordering can bind ConVar to vstdlib instead of the SDK archive](05-episode1-tier1-link-order.md)
- [`dhooks.ext` no longer registers the `dhooks` library](06-khook-library-registration.md)
- [`DHookSetFromConf` returns 0 on success](07-khook-setfromconf-result.md)
- [Legacy natives removed](08-khook-legacy-natives.md)
- [Unloading `dhooks.ext` on a running server crashes it, and a reload is broken](09-khook-unload-reload.md)
- [Only linux x86_64 is supported](10-khook-x86-backend.md)
- [ConsoleDetours detours the KHook stub instead of `ConCommand::Dispatch`](11-khook-console-detour-target.md)
- [Build breaks against current KHook / MSVC](12-khook-build-api-mismatch.md)
- [x86: a recall restores the callee-saved registers it was re-entered with](13-khook-recall-saved-registers.md)
- [A recall corrupts the recall site's stack and registers on MSVC x86](14-khook-msvc-recall-stack.md)
- [DHooks does not build / run on Windows x86](15-khook-windows-build-and-sdkhooks.md)

The original KHook findings remain in [UPSTREAM_REPORTS.md](../UPSTREAM_REPORTS.md).
