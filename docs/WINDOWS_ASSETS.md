# Windows Metamod asset rename (T1.7 / #125)

New builds use `mmsource-<ver>-git<mmrev>-css34-windows.zip`.
Existing published tags keep their original filenames; do not rewrite their URLs.

| Consumer | Handling |
| --- | --- |
| README asset names and installer contract | Documents new names, historical names, and Linux-only pointers. |
| `builder/package-metamod-windows.ps1`, `builder/package_windows.py` | Produce revision-bearing names and validate zip layout and manifests. |
| `builder/package-paths.sh` | Resolves exact Windows SM/MM names from the selected line's pins. |
| `release.yml` Windows upload | Uses exact paths from `package-paths.sh`; validates both archives before upload. |
| `release.yml` tag `SHA256SUMS` | Downloads all `*.zip` and `*.tar.gz`; hashes actual filenames, so accepts the rename. |
| `release.yml` line pointers, `builder/scripts/update-line-pointer.sh` | Publish Linux only, using fixed `mmsource-css34-linux.tar.gz`; pointer checksums hash fixed Linux names. No Windows pointer exists. |
| `build.yml` native/Wine smoke and cache collection | `mmsource-*-css34-windows.zip` accepts both names in fresh job directories. |
| `testing/scripts/wine-smoke-test.sh` | Receives `MM_WIN_PACKAGE`; does not construct an asset name. |
| `testing/scripts/check-package-paths.sh` | Checks revision-bearing Windows paths with stale `-dev-` and wrong-revision archives present. |
| `testing/versions/matrix.json` | Historical published-tag URLs retain `-dev-`; changing them would break downloads. |
| `testing/README.md` | Windows example uses a compatible glob. |
| `v34_server_base/manifest/sources.json`, `todo/windows/install.ps1` | Installer constructs exact names from `line.mm` plus `-windows.zip`; migration recorded in #95. |

For the installer, new release entries must use a revision-bearing MM stem
(e.g. `mmsource-1.12.0-git1226-css34` for the current pin). Keep historical entries
and the rom4s fallback unchanged. If Linux and Windows names differ for a selected
historical tag, use per-platform asset fields rather than changing a shared stem.
Coordinate the manifest update with publication and smoke the constructed Windows
URL, checksum, extraction, and installed SM/MM versions. This PR does not edit the
installer repository.
