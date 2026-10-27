# Pakai Asadi

Pakai Asadi is an embedded SQLite administration component for B4J. It registers handlers on the host's existing EndsMeet server; it never starts a separate server.

## Status (M1 + M2)

This checkout contains the B4J source project and local demo hosts under `source/` and `demo/`:

- `PakaiAsadi.bas` — public configuration, explicit database allowlist and route registration.
- `AsadiState.bas` — request-shared module state.
- `AsadiHandler.bas` — fail-closed host gate, MiniORMUtils-managed SQLite connections, MiniHTML-rendered pages, schema-object detail pages, and the read-only table/view browser.
- `Pakai-Asadi.b4j` — demo host, configured to listen on port 8080 and serve both `/` and `/asadi` from one EndsMeet instance.
- `libs.json` — EndsMeet 4.03 and Xerial SQLite JDBC 3.53.2.1, matching the driver installed in the current B4J environment.

Both `source/Pakai-Asadi.b4j` and `demo/demo.b4j` compile with B4JBuilder 10.70 using `-Task=Build -NoClean=True -ShowWarnings=True`. The standalone `source` host was launched on 2026-10-28 and its M1/M2 pages were exercised against a disposable SQLite file; see [tests/M2-checklist.md](tests/M2-checklist.md). The Lanyard host flow remains application-specific and is covered by [tests/M1-checklist.md](tests/M1-checklist.md). A compiled Asadi `.b4xlib` has not been generated.

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

`Initialize` requires an existing allowed directory and the name of a host-module Boolean function with signature `AuthorizeAsadi(req As ServletRequest) As Boolean`. Missing or failing authorization denies requests. `AddDatabase` accepts only an already existing readable file inside that directory; names are restricted to ASCII letters/digits/underscore/hyphen (starting with a letter). The database path is never accepted from an HTTP request. `Start` registers GET routes; it does not start a listener. It rejects a prefix that overlaps a route already present in `App.routes`.

The Pakai demo uses Lanyard's global `AuthFilter` for session authentication and an additional `Main.AuthorizeAsadi` check requiring the session's `role` to equal `admin`. Newly registered Lanyard accounts default to role `user`; promote a trusted account to `admin` through the host's authorized provisioning process before testing the workspace. Do not make self-registration confer admin access. The Asadi handler repeats the role gate on every request; the global login filter alone is not the admin authorization policy.

## Current UI and safeguards

- Responsive light/dark workspace with registered database navigation.
- Database overview shows table/view/index/trigger counts and current main-file-plus-WAL byte size; no full-table scans.
- Schema-object listing is bounded to 500 objects. Indexes and triggers have detail pages showing their retained SQL definition.
- Table and view pages show the column structure (type, nullability, primary-key position, default, foreign-key target), indexes, and SQL definition.
- Read-only table browser: 25 rows per page, whitelisted column sorting, literal `LIKE` search across up to 50 non-BLOB columns, explicit `NULL` and BLOB-size rendering, and a bounded 160-character preview for long values.
- Requests are GET-only. Non-GET methods return `405` with `Allow: GET`; unknown databases, tables, views, indexes, and triggers return `404`; invalid paging, sorting, or search parameters return `400`.
- Logical database names, object names, row values, search text, and SQL definitions are HTML-escaped.
- Responses set `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, and a restrictive content security policy.
- MiniORMUtils opens the registered file with `createIfNecessary=False`, so an absent file is not created. Each request enables SQLite `PRAGMA query_only=ON` on its private connection. SQL identifiers come only from verified schema metadata and are quoted; search values are bound parameters.
- MiniHTML builds the page tree. Database-controlled text is escaped with EndsMeet before `.text` because MiniHTML does not escape text automatically.
- Absolute paths and raw database errors are not shown in HTML.

### Browser limits

The table browser intentionally does not attempt to be a general SQL console. It displays at most the first 50 columns of a table or view, searches at most the first 50 non-BLOB columns, rejects page numbers above 100,000, and caps search text at 200 characters. Sorting uses the requested column plus remaining primary-key columns for stable paging. Tables without a primary key are browse-only and sorted by the selected column without a uniqueness guarantee.

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

M2 does not yet implement editing, exports, the SQL workspace, CSRF-protected write routes, or the packaged `.b4xlib` artifact. Table browsing is read-only and bounded as described above. Only one Asadi instance can be configured per host process because handler state is module-level. Host authentication and authorization remain the integrating application's responsibility; the included Lanyard demo uses plaintext password comparison and must not be deployed as-is. See the reconnaissance report for integration and dependency caveats.

## License

License selection is pending repository-owner confirmation. No license is asserted by this scaffold.
