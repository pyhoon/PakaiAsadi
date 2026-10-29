# M5 library packaging checklist

These checks cover the `.b4xlib` build, its manifest, and consumption from the demo host, which ticks `pakaiasadi` and contains no Asadi modules. Run them against disposable copies; do not install a test build permanently into the B4J additional libraries folder.

## Setup

1. Build the library host from its project directory:

   ```powershell
   cd source
   & 'C:\Program Files\B4X\B4J\B4JBuilder.exe' -Task=Build -NoClean=True -ShowWarnings=True
   ```

2. Build and package the library:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File tools\package-b4xlib.ps1
   ```

3. Inspect the archive. It must be a flat zip (no folder prefix) with exactly these entries:

   ```
   AsadiHandler.bas
   AsadiState.bas
   PakaiAsadi.bas
   manifest.txt
   ```

4. Copy `release/PakaiAsadi.b4xlib` to `C:\B4X\Additional\B4J\`, then build the demo. It resolves the three modules from the archive and must build with no Asadi `.bas` file in `demo/`.

   ```powershell
   cd ..\demo
   & 'C:\Program Files\B4X\B4J\B4JBuilder.exe' -Task=Build -NoClean=True -ShowWarnings=True
   ```

## Packaging

| Case | Expected |
|---|---|
| Run the script with a clean `source/` | `BuildLibrary` ends with `Completed successfully`; `release/PakaiAsadi.b4xlib` is created |
| Inspect the archive | Only the three library modules plus `manifest.txt`; `main` and `DemoHomeHandler` are absent |
| Read `manifest.txt` | `Author=Aeric Poon`, `Version=1.00`, `B4J.DependsOn=EndsMeet, MiniHTML, MiniORMUtils, sqlite-jdbc`, `Supported Platforms=B4J` |
| Compare `#LibraryVersion` in `source/Pakai-Asadi.b4j` with the manifest | Equal; the script rejects a mismatch |
| Run a normal `-Task=Build` and then the package script | Packaging succeeds; the script discards the generated `Objects/src` and `Objects/bin` that a library build cannot reuse |
| Keep a direct `SubExists(Main, ...)` reference in a library module | `BuildLibrary` fails with `Cannot access excluded module: main` |
| Package with `-SkipBuild` | Archives the current sources without running the compiler |

The library build compiles every non-main module in `source/Pakai-Asadi.b4j`, including the demo-only `DemoHomeHandler`. A compile error in demo code still blocks the package step even though that module is not shipped.

## Consumer build

`demo/demo.b4j` is the committed consumer: `Library10=pakaiasadi`, no Asadi modules in `demo/`. Build it after installing the archive and confirm the `/asadi` pages still work.

For a stricter dependency check, create a scratch copy of `source/` with `Objects/`, `logs/`, `AutoBackups/`, and `data/` excluded, then:

1. Delete `AsadiHandler.bas`, `AsadiState.bas`, and `PakaiAsadi.bas` from the copy.
2. Remove `#LibraryName`, `#LibraryVersion`, and `#LibraryAuthor` from the copy's `Pakai-Asadi.b4j` (a consuming application does not declare them).
3. Set the project libraries to `Library1=endsmeet`, `Library2=jcore`, `Library3=minihtml`, `Library4=miniormutils`, `Library5=pakaiasadi`, and keep only `Module1=DemoHomeHandler`.
4. Build with `-BaseFolder=<scratch path>`.

| Case | Expected |
|---|---|
| Build the scratch host | `Completed successfully` although the three Asadi source files are absent |
| Start it with a disposable database copy | EndsMeet starts on port 8080 and logs the `/asadi` workspace URL |
| `GET /asadi` | `200`; the overview lists the registered database |
| `GET /asadi/db/demo?table=people` | `200`; fixture rows render |
| `GET /asadi/db/demo/edit?table=people&k0=7` | `200`; the form and delete confirmation modal render |
| `POST /asadi/db/demo/sql` | `200`; a `SELECT` result renders |
| Forged CSRF token or cross-origin `POST` | `403` |
| Run the 31-check smoke suite and 6-check edge suite | All pass |

A stronger dependency check: keep only `Library1=jcore` and `Library2=pakaiasadi`, remove `#AdditionalJar: sqlite-jdbc`, and rebuild. The build must still succeed, the merged `Objects/result.jar` must contain `org/sqlite` entries, and the host must serve the same pages. This confirms the manifest's `B4J.DependsOn` supplies EndsMeet, MiniHTML, MiniORMUtils, and the JDBC driver.

## Runtime wiring

| Case | Expected |
|---|---|
| Host main module exposes the configured authorization sub | Requests are gated; a `True` result allows the request |
| Host omits that sub | `PakaiAsadi.Initialize` logs and leaves the component unconfigured; `Start` returns `False` and registers no routes |
| Host calls `Initialize` without the library installed | Build fails on the missing `PakaiAsadi` type, not at runtime |
| A second `PakaiAsadi.Initialize` in one process | Logs that only one instance is supported and makes no changes |

## Last verified

2026-10-29, B4JBuilder 10.70 / Java 19.0.2.

- `source/Pakai-Asadi.b4j` built successfully after the `AsadiState.HostModule` change.
- `tools/package-b4xlib.ps1` ran `-Task=BuildLibrary` successfully and created `release/PakaiAsadi.b4xlib` with the four expected entries.
- `demo/demo.b4j` now ticks `Library10=pakaiasadi` and `demo/` holds no Asadi modules. After installing the archive, the demo built successfully; its `demo.jar` contained `b4j/pakai/asadihandler.class`, `asadistate.class`, `pakaiasadi.class`, and 146 `org/sqlite/` entries.
- A scratch host containing none of the three Asadi modules, with `Library5=pakaiasadi`, built and ran on port 8080 against a disposable copy of `source/data/demo.db`. The 31-check smoke suite (dashboard, table, edit, insert/update/delete, CSRF negatives, index detail, SQL) and the 6-check edge suite (SQL rejection, SQL error surfacing, `NOT NULL` rejection) passed.
- A second scratch host listing only `jcore` and `pakaiasadi`, without `#AdditionalJar: sqlite-jdbc`, also built and passed both suites. Its `result.jar` contained `org/sqlite/JDBC.class`.
- The test install was removed from `C:\B4X\Additional\B4J` afterwards. `source/data/demo.db` remained at 61 `people` rows with row 7 still `Person 7`.
