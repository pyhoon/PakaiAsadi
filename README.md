# Pakai Asadi

Pakai Asadi is an embedded SQLite administration component for B4J. It registers handlers on the host's existing EndsMeet server; it never starts a separate server.

## M1 status

This checkout now contains a B4J M1 source project and local demo host under `source/`:

- `PakaiAsadi.bas` — public configuration, explicit database allowlist and route registration.
- `AsadiState.bas` — request-shared module state.
- `AsadiHandler.bas` — fail-closed host gate, MiniORMUtils-managed SQLite connections, and a MiniHTML-rendered overview.
- `Pakai-Asadi.b4j` — demo host, configured to listen on port 8080 and serve both `/` and `/asadi` from one EndsMeet instance.
- `libs.json` — EndsMeet 4.03 and Xerial SQLite JDBC 3.53.2.1, matching the driver installed in the current B4J environment.

Both `source/Pakai-Asadi.b4j` and `demo/demo.b4j` compiled successfully with B4JBuilder 10.70 using `-Task=Build -NoClean=True -ShowWarnings=True`. The applications have not been launched, so runtime behavior remains unverified. A compiled Asadi `.b4xlib` has not been generated.

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
- Schema-object listing is bounded to 500 objects.
- Logical database names and metadata are HTML-escaped.
- No write operations or SQL endpoint exist in M1.
- MiniORMUtils opens the registered file with `createIfNecessary=False`, so an absent file is not created. Each request enables SQLite `PRAGMA query_only=ON` on its private connection; the only SQL statements in M1 are static metadata reads.
- MiniHTML builds the page tree. Database-controlled text is escaped with EndsMeet before `.text` because MiniHTML does not escape text automatically.
- Absolute paths and raw database errors are not shown in HTML.

## Dependencies and build

- B4J 10.7+ (matches current Pakai Server 6.99 project metadata).
- EndsMeet 4.03.
- Xerial `org.xerial:sqlite-jdbc:3.53.2.1` (installed as `sqlite-jdbc.jar`).
- MiniHTML 4.02 and MiniORMUtils 6.04, plus B4J `JavaObject` and `jSQL` libraries.

Open `demo/demo.b4j` in B4J, use the IDE library installer with `demo/libs.json`, then run its Default (SQLite) build. Asadi registers only the host-configured SQLite database and does not create database files. Open `http://127.0.0.1:8080/` and navigate to `/asadi` after logging in as a user with the `admin` role. The starter template's `Objects` database/config are treated as host data and are not modified by Asadi.

The source reconnaissance and plug-in library evaluation (Lanyard, Vest, Watch) are in [RECONNAISSANCE.md](RECONNAISSANCE.md).

## Known limitations

M1 does not yet implement table browsing, editing, exports, the SQL workspace, CSRF-protected writes, or the packaged `.b4xlib` artifact. The current source changes have not yet been compiled in B4J. See the reconnaissance report for integration and dependency caveats.

## License

License selection is pending repository-owner confirmation. No license is asserted by this scaffold.
