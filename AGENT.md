# Agent guidance for Pakai Asadi

## B4J builds

Build B4J projects with the installed command-line builder:

```powershell
& 'C:\Program Files\B4X\B4J\B4JBuilder.exe' -Task=Build -NoClean=True -ShowWarnings=True
```

Run it with the project folder as the process working directory (the coding harness's `workdir`); omit `-BaseFolder`. The upstream command-line compilation thread documents `-BaseFolder` as having an open issue. If the folder contains exactly one `.b4j` file, omit `-Project` and let the builder select it.

Running `B4JBuilder.exe` with no arguments prints its own supported parameter list. The installed v10.70 builder reports:

- `-Task=Build` (default; similar to Release compilation) or `-Task=BuildLibrary` (library compilation)
- `-BaseFolder`, `-Project`, `-Obfuscate`, `-ShowWarnings`, `-Configuration`, `-NoClean`, and `-Output`

Use `-NoClean=True` when a project has user-managed runtime files under `Objects/` (including SQLite databases and local configuration). Do not delete or overwrite those files as part of a build. Preserve the full builder output and exit status; do not report a build as successful unless the process exits successfully.

Builder/API reference: [B4ABuilder / B4JBuilder command-line compilation](https://www.b4x.com/android/forum/threads/b4abuilder-b4jbuilder-command-line-compilation.50154/).

## Dependencies

The builder resolves `#AdditionalJar` names from `C:\Program Files\B4X\B4J\libraries`. Ensure project `libs.json` dependencies are installed there before treating a missing-JAR build failure as a source error. Keep dependency versions consistent between `libs.json` and `#AdditionalJar` declarations.

## Pakai Asadi integration

- Integrate with the host's existing EndsMeet instance; never start an additional server.
- Register the host root route as `App.Get("", HandlerClass)`, matching Pakai's current convention. Avoid mapping a handler to literal `/`, which can collide with Jetty's default servlet mapping.
- Register only explicitly allowlisted SQLite paths and keep HTTP routes path-free.
- Keep the host-provided authorization callback fail-closed; in the Pakai/Lanyard demo require the `admin` session role in addition to the global authentication filter.
- For the M1 metadata-only views, use MiniORMUtils for SQLite connection lifecycle and MiniHTML for response construction. Escape user/database-controlled text before passing it to MiniHTML `.text`.
- Keep source modules under `source/` synchronized with the corresponding demo host modules under `demo/` until the `.b4xlib` packaging workflow is established.
- Never run destructive verification against `demo/Objects/pakai.db`; use an isolated database copy.
