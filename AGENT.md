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

The `java` on `PATH` in this environment is Java 8, which cannot load the Java 19 class files produced by the builder. Launch compiled jars with the installed Java 19 runtime, for example `C:\Java\jdk-19.0.2\bin\java.exe -jar Objects\result.jar`, or use the B4J IDE's Run command.

`-Task=BuildLibrary` currently fails for Asadi with `Cannot access excluded module: main` because the handler and public class resolve the host's `Main` module. Normal application builds are unaffected; resolve the main-module coupling before claiming a `.b4xlib` build.

Builder/API reference: [B4ABuilder / B4JBuilder command-line compilation](https://www.b4x.com/android/forum/threads/b4abuilder-b4jbuilder-command-line-compilation.50154/).

## Dependencies

The builder resolves `#AdditionalJar` names from `C:\Program Files\B4X\B4J\libraries`. Ensure project `libs.json` dependencies are installed there before treating a missing-JAR build failure as a source error. Keep dependency versions consistent between `libs.json` and `#AdditionalJar` declarations.

## Pakai Asadi integration

- Integrate with the host's existing EndsMeet instance; never start an additional server.
- Register the host root route as `App.Get("", HandlerClass)`, matching Pakai's current convention. Avoid mapping a handler to literal `/`, which can collide with Jetty's default servlet mapping.
- Register only explicitly allowlisted SQLite paths and keep HTTP routes path-free.
- Keep the host-provided authorization callback fail-closed; in the Pakai/Lanyard demo require the `admin` session role in addition to the global authentication filter.
- For metadata and read-only table views, use MiniORMUtils for SQLite connection lifecycle and MiniHTML for response construction. Escape user/database-controlled text and attribute values before passing them to MiniHTML `.text`/`.attr`; MiniHTML does not escape either.
- Never interpolate HTTP input into SQL. Resolve database/table/view names against the allowlist and `sqlite_master`, take sort/search columns only from `PRAGMA` metadata, quote identifiers, and bind search values. Keep `PRAGMA query_only=ON` on every request connection.
- Keep the M2 browser bounded: 25 rows per page, at most 50 displayed/searchable columns, 160-character value previews, one-line grid cells with ellipsis, and escaped `title` previews. Do not turn a page render into an unbounded table scan or dump BLOBs.
- Keep the M3 SQL workspace read-only: one validated statement, only `SELECT`/`WITH`/`VALUES`/`EXPLAIN`/`PRAGMA`, 200 rows, 50 columns, 160-character display previews, 2,000-character stored values, and 20,000-character input. Use `open_mode=1` for the JDBC connection and do not add endpoints that accept writes without a CSRF-protected design.
- `POST` is registered only for the SQL route. Preserve the `Sec-Fetch-Site`/`Origin` check and the explicit `405` + `Allow` responses for other routes. Remember that `Origin: null` is emitted by the preview proxy; the host authorization gate is the primary control.
- `jSQL`'s `ResultSet` wrapper cannot expose metadata or distinguish BLOBs. Use `JavaObject`/JDBC for arbitrary SQL, `RunMethodJO` for object-returning Java calls, and `getBytes` for BLOB columns. Apply sanitized error text (`[SQLITE…` onward) and never show registered paths.
- There is no enforced SQL query timeout in Xerial 3.53.2.1 (`setQueryTimeout` is a no-op), and returned values are materialized before preview caps. Do not claim otherwise; rely on host/proxy timeouts and trusted-admin access.
- Keep source modules under `source/` synchronized with the corresponding demo host modules under `demo/` until the `.b4xlib` packaging workflow is established. Copy `source/AsadiHandler.bas`, `AsadiState.bas`, and `PakaiAsadi.bas` over the demo copies from the repository root after editing either side, then build both. Run verification steps in `tests/M1-checklist.md`, `tests/M2-checklist.md`, and `tests/M3-checklist.md` as applicable.
- Never run destructive verification against `demo/Objects/pakai.db`; use an isolated database copy. `tests/M2-fixture.sql` is for a disposable demo database and replaces its `people`/`teams` fixture objects.
