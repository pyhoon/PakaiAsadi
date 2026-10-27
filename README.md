# Pakai Asadi

Pakai Asadi is an embedded SQLite administration component for B4J. It registers handlers on the host's existing EndsMeet server; it never starts a separate server.

## Status (M1 + M2 + M3)

This checkout contains the B4J source project and local demo hosts under `source/` and `demo/`:

- `PakaiAsadi.bas` — public configuration, explicit database allowlist and route registration.
- `AsadiState.bas` — request-shared module state.
- `AsadiHandler.bas` — fail-closed host gate, MiniORMUtils-managed SQLite connections, MiniHTML-rendered pages, schema-object detail pages, the read-only table/view browser, and the read-only SQL workspace.
- `Pakai-Asadi.b4j` — demo host, configured to listen on port 8080 and serve both `/` and `/asadi` from one EndsMeet instance.
- `libs.json` — EndsMeet 4.03 and Xerial SQLite JDBC 3.53.2.1, matching the driver installed in the current B4J environment.

Both `source/Pakai-Asadi.b4j` and `demo/demo.b4j` compile with B4JBuilder 10.70 using `-Task=Build -NoClean=True -ShowWarnings=True`. The standalone `source` host was launched on 2026-10-28 and its M1–M3 pages were exercised against a disposable SQLite file; see [tests/M2-checklist.md](tests/M2-checklist.md) and [tests/M3-checklist.md](tests/M3-checklist.md). The Lanyard host flow remains application-specific and is covered by [tests/M1-checklist.md](tests/M1-checklist.md). A compiled Asadi `.b4xlib` has not been generated.

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

## Current UI and safeguards

- Responsive light/dark workspace with registered database navigation.
- Database overview shows table/view/index/trigger counts and current main-file-plus-WAL byte size; no full-table scans.
- Schema-object listing is bounded to 500 objects. Indexes and triggers have detail pages showing their retained SQL definition.
- Table and view pages show the column structure (type, nullability, primary-key position, default, foreign-key target), indexes, and SQL definition.
- Read-only table browser: 25 rows per page, whitelisted column sorting, literal `LIKE` search across up to 50 non-BLOB columns, explicit `NULL` and BLOB-size rendering, and a bounded 160-character preview for long values.
- Read-only SQL workspace at `/asadi/db/<name>/sql`: one statement per run, limited to `SELECT`, `WITH`, `VALUES`, `EXPLAIN`, and `PRAGMA`. It uses a fresh JDBC connection opened with `open_mode=1`, rejects extra statements, and renders typed grids with `NULL` and BLOB-size cells. Results are capped at 200 rows and 50 columns, values at 160 displayed characters (2,000 stored for the `title` preview), and SQL input at 20,000 characters.
- Browser pages are GET-only. `POST` is accepted only on the SQL workspace route and only when the browser marks the request `Sec-Fetch-Site: same-origin`/`none` or, without that header, the `Origin` host matches `Host`. Other methods return `405` with an `Allow` header; unknown databases, tables, views, indexes, and triggers return `404`; invalid paging, sorting, search, or SQL input returns `400`.
- Logical database names, object names, row values, search text, SQL definitions, and SQL errors are HTML-escaped; JDBC error text is stripped of class prefixes and absolute paths.
- Responses set `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, and a restrictive content security policy.
- MiniORMUtils opens the registered file with `createIfNecessary=False`, so an absent file is not created. Each request enables SQLite `PRAGMA query_only=ON` on its private connection. SQL identifiers come only from verified schema metadata and are quoted; search values are bound parameters.
- The SQL workspace opens its own JDBC connection with SQLite `open_mode=1` (read-only) because MiniORMUtils cannot distinguish BLOBs reliably. The read-only handle plus statement validation enforce the no-write policy; user statements run on that handle, while metadata pages keep using MiniORMUtils with `PRAGMA query_only=ON`.
- MiniHTML builds the page tree. Database-controlled text is escaped with EndsMeet before `.text` because MiniHTML does not escape text automatically.
- Absolute paths and raw database errors are not shown in HTML.

### Browser limits

The table browser intentionally does not attempt to be a general SQL console. It displays at most the first 50 columns of a table or view, searches at most the first 50 non-BLOB columns, rejects page numbers above 100,000, and caps search text at 200 characters. Sorting uses the requested column plus remaining primary-key columns for stable paging. Tables without a primary key are browse-only and sorted by the selected column without a uniqueness guarantee.

The SQL workspace runs one validated statement at a time and caps output at 200 rows and 50 columns. It has no execution-time limit: the installed Xerial driver accepts `setQueryTimeout` but does not enforce it, so a long query holds its request thread until SQLite finishes. The driver also materializes each returned value before the 2,000-character/BLOB-size preview is applied, so a query returning very large values can still use substantial memory even though the grid retains only capped previews. Use host/proxy request timeouts, keep the workspace on trusted databases, and restrict it to trusted administrators. `ATTACH`/`DETACH` are rejected explicitly, and `TABLE` is not accepted because the installed driver reports it as a syntax error.

## Dependencies and build

- B4J 10.7+ (matches current Pakai Server 6.99 project metadata).
- EndsMeet 4.03.
- Xerial `org.xerial:sqlite-jdbc:3.53.2.1` (installed as `sqlite-jdbc.jar`).
- MiniHTML 4.02 and MiniORMUtils 6.04, plus B4J `JavaObject` and `jSQL` libraries.

Open `demo/demo.b4j` in B4J, use the IDE library installer with `demo/libs.json`, then run its Default (SQLite) build. Asadi registers only the host-configured SQLite database and does not create database files. Open `http://127.0.0.1:8080/` and navigate to `/asadi` after logging in as a user with the `admin` role. The starter template's `Objects` database/config are treated as host data and are not modified by Asadi.

For the standalone source host, build `source/Pakai-Asadi.b4j` and run it from the `source` directory. In this environment the `java` on `PATH` is Java 8, so use the Java 19 runtime explicitly:

```powershell
cd source
& 'C:\Java\jdk-19.0.2\bin\java.exe' -jar Objects\result.jar
```

`source/data/demo.db` is created by the demo host on first run and is excluded from version control. Apply [tests/M2-fixture.sql](tests/M2-fixture.sql) with the `sqlite3` CLI to add representative tables, a view, an index, a trigger, NULLs, BLOBs, and enough rows to exercise paging and search. Do not run fixtures against the user-created `demo/Objects/pakai.db`.

The source reconnaissance and plug-in library evaluation (Lanyard, Vest, Watch) are in [RECONNAISSANCE.md](RECONNAISSANCE.md).

## Known limitations

M3 does not yet implement editing, exports, CSRF-protected write routes, or the packaged `.b4xlib` artifact. Table browsing and the SQL workspace are read-only and bounded as described above. The SQL workspace has no enforced query timeout. Only one Asadi instance can be configured per host process because handler state is module-level. Host authentication and authorization remain the integrating application's responsibility; the included Lanyard demo uses plaintext password comparison and must not be deployed as-is. See the reconnaissance report for integration and dependency caveats.

## License

License selection is pending repository-owner confirmation. No license is asserted by this scaffold.
