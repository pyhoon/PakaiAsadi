# Pakai Asadi

Pakai Asadi is an embedded SQLite administration component for B4J. It registers handlers on the host's existing EndsMeet server; it never starts a separate server.

New to the library? Start with [QUICKSTART.md](QUICKSTART.md) for installation and host integration in the Pakai Server template or a plain B4J + EndsMeet application.

## Status (M1-M5)

This checkout contains the B4J source project, two demo hosts (`source/` compiles the library from source; `demo/` consumes the packaged `.b4xlib`), and the packaging tooling for the library:

- `PakaiAsadi.bas` - public configuration, explicit database allowlist and route registration.
- `AsadiState.bas` - request-shared module state, including the per-process CSRF secret and the host module name.
- `AsadiHandler.bas` - fail-closed host gate, MiniORMUtils-managed SQLite connections, MiniHTML-rendered pages, schema-object detail pages, the table/view browser, the read-only SQL workspace, CSRF-protected row editing, and CSV/JSON exports.
- `Pakai-Asadi.b4j` - demo host, configured to listen on port 8080 and serve both `/` and `/asadi` from one EndsMeet instance; its project attributes also describe the packaged library.
- `manifest.txt` - author, version, dependencies, and supported platform for the `.b4xlib`.
- `tools/package-b4xlib.ps1` - runs the library build and assembles `release/PakaiAsadi.b4xlib`.
- `libs.json` - EndsMeet 4.03 and Xerial SQLite JDBC 3.53.2.1, matching the driver installed in the current B4J environment.

Both `source/Pakai-Asadi.b4j` and `demo/demo.b4j` compile with B4JBuilder 10.70 using `-Task=Build -NoClean=True -ShowWarnings=True`. The demo ticks `pakaiasadi` instead of embedding the library modules, so build and install `release/PakaiAsadi.b4xlib` first. The standalone `source` host was launched on 2026-10-28 and its M1-M4 pages and write paths were exercised against a disposable SQLite file; the Lanyard demo host was exercised separately on a disposable copy of `pakai.db`. See [tests/M2-checklist.md](tests/M2-checklist.md), [tests/M3-checklist.md](tests/M3-checklist.md), and [tests/M4-checklist.md](tests/M4-checklist.md). The Lanyard host flow remains application-specific and is covered by [tests/M1-checklist.md](tests/M1-checklist.md). M5 covers the packaged `.b4xlib`, including the demo's consumer build, in [tests/M5-checklist.md](tests/M5-checklist.md).

## Public API

Configure the component from trusted host code after initializing EndsMeet and before `App.Start`:

```vb
Dim Asadi As PakaiAsadi
Asadi.Initialize(App, File.Combine(File.DirApp, "data"), "AuthorizeAsadi")
Asadi.BasePath = "/asadi" ' default
If Asadi.AddDatabase("main", File.Combine(File.Combine(File.DirApp, "data"), "main.db")) = False Then
    Log("Database registration failed")
    Return
End If
If Asadi.Start = False Then Return
App.Start
```

`Initialize` requires an existing allowed directory and the name of a host-module Boolean function with signature `AuthorizeAsadi(req As ServletRequest) As Boolean`. Missing or failing authorization denies requests. `AddDatabase` accepts only an already existing readable file inside that directory; names are restricted to ASCII letters/digits/underscore/hyphen (starting with a letter). The database path is never accepted from an HTTP request. `Start` registers the workspace routes on the host's EndsMeet instance; it does not start a listener. It rejects a prefix that overlaps a route already present in `App.routes`.

The Pakai demo uses Lanyard's global `AuthFilter` for session authentication and an additional `Main.AuthorizeAsadi` check requiring the session's `role` to equal `admin`. Newly registered Lanyard accounts default to role `user`; promote a trusted account to `admin` through the host's authorized provisioning process before testing the workspace. Do not make self-registration confer admin access. The Asadi handler repeats the role gate on every request; the global login filter alone is not the admin authorization policy.

## Install the library

Build the package and copy it into the B4J additional libraries folder:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\package-b4xlib.ps1
Copy-Item -LiteralPath release\PakaiAsadi.b4xlib -Destination C:\B4X\Additional\B4J\
```

Restart B4J, then add `PakaiAsadi` to the host project's libraries. The archive contains `AsadiHandler`, `AsadiState`, and `PakaiAsadi` plus `manifest.txt`; it does not include the demo `main` or `DemoHomeHandler`. Its `B4J.DependsOn` entry names EndsMeet, MiniHTML, MiniORMUtils, and `sqlite-jdbc`, so B4J resolves those libraries and the JDBC driver; a project that manages libraries manually should add them explicitly and keep `#AdditionalJar: sqlite-jdbc`.

The host supplies the authorization sub in its main code module. B4J always names that module `Main`, and the library resolves it by name so the callback is reachable from an `.b4xlib`. Call the public API from `AppStart` before `App.Start`. The library never starts a listener, never creates a database, and refuses to register routes when the callback is missing. Only one Asadi instance can be configured per host process.

## Current UI and safeguards

- Responsive light/dark workspace with registered database navigation.
- Database overview shows table/view/index/trigger counts and current main-file-plus-WAL byte size; no full-table scans.
- Schema-object listing is bounded to 500 objects. Indexes and triggers have detail pages showing their retained SQL definition.
- Table and view pages show the column structure (type, nullability, primary-key position, default, foreign-key target), indexes, and SQL definition.
- Table browser: 25 rows per page, whitelisted column sorting, literal `LIKE` search across up to 50 non-BLOB columns, explicit `NULL` and BLOB-size rendering, and a bounded 160-character preview for long values.
- Row editing on tables: per-row `Edit` links, a `+ New row` insert form, and a delete action guarded by a confirmation modal. Primary-key columns are read-only in the form, BLOB columns are shown by size, and each column has a "Set to NULL" checkbox. Updates and deletes carry hidden original values and use `col IS ?` predicates, so a stale form returns `409` instead of overwriting newer data.
- CSV and JSON exports of a whole table or view, GET only, capped at 10,000 rows and 200 columns. CSV is always quoted with a UTF-8 BOM and neutralizes spreadsheet formula prefixes; BLOBs are `base64:<data>`. JSON keeps `null`, numeric, and string values distinct.
- Read-only SQL workspace at `/asadi/db/<name>/sql`: one statement per run, limited to `SELECT`, `WITH`, `VALUES`, `EXPLAIN`, and `PRAGMA`.
- CSRF protection on every write route: a signed `nonce.signature` token (HMAC-SHA256 with a per-process secret) is stored in an `HttpOnly; SameSite=Strict` cookie and echoed in a hidden `csrf` field. Cookie and field must match and the signature must verify.
- Browser pages keep GET for reads. `POST` is accepted only on the SQL workspace and edit routes and only when the browser marks the request `Sec-Fetch-Site: same-origin`/`none` or, without that header, the `Origin` host matches `Host`. Other methods and paths return `405` with an `Allow` header; unknown databases, tables, views, indexes, and triggers return `404`; invalid paging, sorting, search, edit, or SQL input returns `400`.
- Logical database names, object names, row values, search text, SQL definitions, and SQL errors are HTML-escaped; JDBC error text is stripped of class prefixes and absolute paths.
- Responses set `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, and a restrictive content security policy.
- MiniORMUtils opens the registered file with `createIfNecessary=False`, so an absent file is not created. Each metadata request enables SQLite `PRAGMA query_only=ON` on its private connection. SQL identifiers come only from verified schema metadata and are quoted; search values are bound parameters.
- The SQL workspace opens its own JDBC connection with SQLite `open_mode=1` (read-only) because MiniORMUtils cannot distinguish BLOBs reliably. The read-only handle plus statement validation enforce the no-write policy; user statements run on that handle, while metadata pages keep using MiniORMUtils with `PRAGMA query_only=ON`.
- Row edits and exports open short-lived JDBC handles: `open_mode=2` (read-write, no create) for `POST` edit actions and `open_mode=1` for exports. Write connections are used only after the host gate, origin check, and CSRF check pass, and every value is bound as a parameter.
- MiniHTML builds the page tree. Database-controlled text is escaped with EndsMeet before `.text` because MiniHTML does not escape text automatically.
- Absolute paths and raw database errors are not shown in HTML.

### Browser limits

The table browser intentionally does not attempt to be a general SQL console. It displays at most the first 50 columns of a table or view, searches at most the first 50 non-BLOB columns, rejects page numbers above 100,000, and caps search text at 200 characters. Sorting uses the requested column plus remaining primary-key columns for stable paging. Tables without a primary key are sorted by the selected column without a uniqueness guarantee; editing addresses their rows through an unshadowed `rowid` alias.

### Editing and export limits

Editing is limited to tables, one row per request. Views are browse/export only. Primary-key columns are read-only (an update never rewrites them), BLOB columns are read-only, and a table whose key contains a BLOB cannot be edited at all. A table with no primary key is edited through an unshadowed `rowid` alias; a table that shadows `_rowid_`, `rowid`, and `oid` cannot be edited. Form values are capped at 100,000 characters.

Insert skips a blank integer primary key so SQLite assigns one, skips blank columns that declare a default, and omits blank numeric columns so they store `NULL` instead of text. A blank `NOT NULL` numeric column without a default is rejected with `400`.

Update and delete compare every submitted original non-key, non-BLOB value with `col IS ?` before changing anything. A row changed elsewhere returns `409`; a deleted row returns `400`. This is an optimistic compare, not a version counter: a concurrent change that restores identical values is undetectable. There is no bulk edit, no multi-row transaction, and no schema editor.

Exports read a whole table or view over a read-only JDBC handle and stop at 10,000 rows (`X-Asadi-Row-Limit`) and 200 columns. CSV is UTF-8 with a BOM, always quoted, CRLF-terminated, and prefixes `=`, `@`, tab, CR, and LF with an apostrophe to neutralize spreadsheet formulas. `NULL` becomes an empty CSV field and a BLOB becomes `base64:<data>`. JSON is an array of row objects: `null` for `NULL`, unquoted numbers for numeric JDBC types whose stored text is numeric, strings otherwise, and `base64:<data>` for BLOBs. CSV cannot distinguish `NULL` from an empty string.

The SQL workspace runs one validated statement at a time and caps output at 200 rows and 50 columns. It has no execution-time limit: the installed Xerial driver accepts `setQueryTimeout` but does not enforce it, so a long query holds its request thread until SQLite finishes. The driver also materializes each returned value before the 2,000-character/BLOB-size preview is applied, so a query returning very large values can still use substantial memory even though the grid retains only capped previews. Use host/proxy request timeouts, keep the workspace on trusted databases, and restrict it to trusted administrators. `ATTACH`/`DETACH` are rejected explicitly, and `TABLE` is not accepted because the installed driver reports it as a syntax error.

## Dependencies and build

- B4J 10.7+ (matches current Pakai Server 6.99 project metadata).
- EndsMeet 4.03.
- Xerial `org.xerial:sqlite-jdbc:3.53.2.1` (installed as `sqlite-jdbc.jar`).
- MiniHTML 4.02 and MiniORMUtils 6.04, plus B4J `JavaObject` and `jSQL` libraries.

Open `demo/demo.b4j` in B4J, use the IDE library installer with `demo/libs.json`, and install `release/PakaiAsadi.b4xlib` into `C:\B4X\Additional\B4J` (the demo ticks `pakaiasadi` and contains no Asadi modules), then run its Default (SQLite) build. Asadi registers only the host-configured SQLite database and does not create database files. Open `http://127.0.0.1:8080/` and navigate to `/asadi` after logging in as a user with the `admin` role. The starter template's `Objects` database/config are treated as host data and are not modified by Asadi.

The demo's `main` module sits in `demo.b4j` and its `#If Release` block sets `App.ssl.Enabled = True`. EndsMeet then registers its `HttpsFilter`, and its SSL settings come from a `.env` file in `Files/` (bundled into `DirAssets`), which the demo does not include. Without a configured keystore and `SSL_PORT`, the server logs `Ssl KeystoreFile is not set` and redirects HTTP requests to `https://127.0.0.1:` with an empty port, so the demo is unreachable over HTTP. Either add a `.env` with `SSL_ENABLED`, `SSL_PORT`, `SSL_KEYSTORE_DIR`, `SSL_KEYSTORE_FILE`, and `SSL_KEYSTORE_PASSWORD` plus a matching keystore to `demo/Files/`, or build the demo with `App.ssl.Enabled = False` for local HTTP testing. Do not commit a local SSL-disable patch.

For the standalone source host, build `source/Pakai-Asadi.b4j` and run it from the `source` directory. In this environment the `java` on `PATH` is Java 8, so use the Java 19 runtime explicitly:

```powershell
cd source
& 'C:\Java\jdk-19.0.2\bin\java.exe' -jar Objects\result.jar
```

`source/data/demo.db` is created by the demo host on first run and is excluded from version control. Apply [tests/M2-fixture.sql](tests/M2-fixture.sql) with the `sqlite3` CLI to add representative tables, a view, an index, a trigger, NULLs, BLOBs, and enough rows to exercise paging and search. Do not run fixtures against the user-created `demo/Objects/pakai.db`.

If you build in the B4J IDE, it may add a UTF-8 BOM when saving a `.bas` or `.b4j` file. This repository stores the BOM and CRLF line endings exactly as the IDE writes them, and `.gitattributes` disables line-ending conversion for those extensions. A BOM-only save therefore produces no diff. Do not add a clean/smudge filter or run a per-clone setup; see [AGENT.md](AGENT.md#source-encoding-and-git).

The source reconnaissance and plug-in library evaluation (Lanyard, Vest, Watch) are in [RECONNAISSANCE.md](RECONNAISSANCE.md).

## Known limitations

M1-M5 are implemented: row editing, CSV/JSON exports, CSRF-protected write routes, and the packaged `.b4xlib`. Editing is table-only and one row per request; primary-key and BLOB values are read-only, and views cannot be edited. Exports are capped at 10,000 rows and 200 columns and are not a backup/replication tool. Conflict detection is an optimistic value comparison, not a version counter. The SQL workspace has no enforced query timeout, and both the SQL grid and exports materialize each value before their size caps. Only one Asadi instance can be configured per host process because handler state is module-level. Host authentication and authorization remain the integrating application's responsibility; the included Lanyard demo uses plaintext password comparison and must not be deployed as-is. See the reconnaissance report for integration and dependency caveats.

## License

License selection is pending repository-owner confirmation. No license is asserted by this scaffold.
