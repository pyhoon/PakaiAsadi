# Pakai Asadi — M0 reconnaissance and M1 specification

## Repository state

At M0, the provided `C:\Projects\pakai-asadi` checkout had no tracked files and no commits. The source checks below use the current public branches and release/manifests observed on 2026-10-27.

## Verified ecosystem findings

| Component | Verified current source/release | Relevance |
|---|---|---|
| Pakai Server | README identifies template version 6.99; `source/libs.json` pins EndsMeet 4.03, MiniHTML 4.02, MiniJS 0.60, MiniORMUtils 6.04, WebApiUtils 7.00. | B4J v10.7+ project conventions; server-side HTML; Bootstrap 5.3.8 and HTMX 2.0.8 assets/CDN conventions. |
| EndsMeet | `source/EndsMeet.bas`, version 4.03; `release/EndsMeet.b4xlib`. | `App.Get(Path, Class)` / `Post` / `Route(Path, Class, Methods)` register against `App.srvr`; `App.Start` starts the host's server. A request handler is a class with `Handle(req As ServletRequest, resp As ServletResponse)`. `App.routes` tracks method/path/class. `WriteHtml` sets `text/html`. No built-in authentication/session policy was identified in the verified public API. |
| MiniHtml | Pakai manifest selects **MiniHTML 4.02 from MiniHtml4**, despite the related `MiniHtml-B4X` repository existing. | Verified `MiniHtml.Initialize(Name)`, `.attr`, `.cls`, `.text`, `.add`/`.up`, and `.build`. Its `.text` stores text without HTML escaping; Asadi escapes metadata through verified `EndsMeet.EscapeHtml` before adding text nodes. |
| MiniORMUtils | Version 6.04. | `MiniORMSettings` exposes `DBType`, `DBDir`, and `DBFile`. `MiniORM.Open As SQL` opens SQLite with `InitializeSQLite(DBDir, DBFile, False)` and returns the owned connection; `SQL` getter and `Close` are public. Asadi uses a per-request MiniORM instance for connection lifecycle, runs fixed metadata SELECTs on its SQL connection, and closes it. It does not route arbitrary SQL through the ORM query builder. |
| MiniJS | Version 0.60. | B4X JavaScript code generator, not a browser JS runtime/framework; not needed for M1. |
| WebApiUtils | Version 7.00. | Provides request/response helpers, auth extractors, CSRF validation helpers and HTML escaping. Its documented auth/CSRF utilities do not establish the host application's authorization policy automatically. Not required for read-only M1 routes. |
| SQLite JDBC | Pakai Server README says the SQLite JDBC version is not pinned and `source/libs.json` does not declare it. Maven Central metadata lists 3.53.4.0 as latest; the B4J environment's installed `sqlite-jdbc.jar` contains Maven metadata for **3.53.2.1**. | Asadi pins the host's actual `org.xerial:sqlite-jdbc:3.53.2.1` artifact in source and demo manifests and uses `#AdditionalJar: sqlite-jdbc`, matching the installed filename. MiniORM's verified open call disables create-on-open; Asadi then enables SQLite connection-local `PRAGMA query_only=ON` before fixed metadata SELECTs. |

## Pakai plug-in library reconnaissance

| Plug-in | Current repository evidence | Asadi integration implications |
|---|---|---|
| [Pakai Lanyard](https://github.com/pyhoon/pakai-lanyard) | Current `master` source manifest reports **0.30** and Pakai Server dependency manifest version **6.80**; its README/forum attachment describe **0.20**. Current source contains `AuthFilter`, `AuthHandler`, `AuthView`, `UsersModel`, and a demo. `AuthFilter.Filter(req, resp)` allows `/assets/`, `/login`, `/register`, otherwise checks `req.GetSession.GetAttribute("user")` and redirects to `/login`. | Provides a verified session-based authentication integration option, but its demonstrated filter checks only that a user session exists; it does not show a role/permission requirement for database administration. Use a host-owned authorization check for the Asadi prefix, or extend the policy explicitly. Its README says to add the filter at `/*`; confirm order and exclusions for the Asadi base path and deploy behind HTTPS. No CSRF contract is established by the inspected filter. The manifest's old EndsMeet 2.00/MiniHtml 2.10/MiniORM 5.60/WebApiUtils 6.80 dependencies differ from the Pakai Server 6.99 manifest; verify class-template compatibility instead of importing those dependency versions over the host's versions. README/forum/source version disagreement should be resolved before documenting a supported release. |
| [Pakai Vest](https://github.com/pyhoon/pakai-vest) | Current `main` README reports **0.20**, labels itself under development/experimental, and its `source/libs.json` still identifies Pakai Server **6.80** with EndsMeet 2.00 and older library versions. It supplies generic model/view/handler CRUD templates based on MiniORM, with a demo project. Forum author explicitly says much of it was copied from Lanyard as an experiment. | Not a suitable engine for Asadi's arbitrary SQLite schema/SQL tasks; its documented CRUD model targets application-defined tables and MiniORM. It demonstrates B4X library packaging and class templates, but its bundled dependency manifest is not the current Pakai Server 6.99 manifest. Keep Asadi on direct JDBC for schema and arbitrary query handling. |
| [Pakai Watch](https://github.com/pyhoon/pakai-watch) | Current `main` README and root `manifest.txt` report **0.60**; it packages a `RateLimiter` filter, registered with `App.srvr.AddFilter("/*", "RateLimiter", False)`. It derives the client identifier from the raw Authorization header (Bearer token included) or `GUEST-{IP}`, and its source writes that identifier into `security_violations.log` on blocked requests. | Can be an optional host-level rate limit for the admin route, not a replacement for authorization or query limits. Important: bearer tokens can be written to a local violation log; avoid placing reusable secrets in that header when blocked-request logging is enabled, or change/redact the logging before deployment. Its Cloudflare IP header handling should be trusted only behind a controlled proxy. It is a global filter in the example; choose limits carefully so admin routes/login are handled as intended. |

### Plug-in version/documentation caveats

- Lanyard README says Version 0.20, but its current root manifest says 0.30 and forum thread also documents 0.20. Resolve the exact release artifact before relying on the packaged API.
- Vest's current docs call itself under development, while the manifest dependency versions remain aligned to Pakai 6.80 rather than Pakai 6.99. Keep its dependency manifest from selecting older shared libraries for a current host.
- Watch's package is a server filter rather than a full auth system. Its own README documents bearer-token-derived identifiers and blocked-request logging; the inspected source confirms the identifier is logged unredacted.
- The supplied Pakai plug-ins demonstrate that B4J class-template `.b4xlib` distribution is an existing ecosystem convention, but they do not remove the need for Asadi's explicit host authorization, CSRF policy, database allowlist, and its own SQLite driver selection.

## Source/documentation discrepancies and limits

- The Pakai README calls out MiniHtml-B4X, but its authoritative `source/libs.json` resolves MiniHTML 4.02 from the distinct MiniHtml4 repository. This project follows the manifest artifact.
- The Pakai README lists SQLite JDBC with no version, and its dependency manifest does not include the driver. A packaged Asadi build cannot silently assume that an application has a particular SQLite driver.
- EndsMeet starts the server only via `App.Start`; route methods add handlers to `srvr` and do not start it. Routes are keyed by method/path/class and handler classes are supplied by name.
- EndsMeet exposes no verified general purpose session/authentication/CSRF contract. Each host must enforce the admin policy in a verified filter or gate; M1 must fail closed when that gate is not wired.
- MiniORMUtils' documented APIs do not make it a general-purpose SQL execution or arbitrary-schema inspection engine.

## Finalized M1 integration specification

The public B4J component will be configured by trusted host code with an existing `EndsMeet` instance, a normalized base path, explicit named database paths, and a required host authorization gate. `Start` means “register Asadi's workspace routes”; it never means “start the HTTP server”. Database names are opaque logical identifiers, and HTTP paths never contain filesystem paths. Registration canonicalizes an already existing file, rejects duplicate/invalid names, and uses MiniORMUtils' SQLite open API with `createIfNecessary=False`; each request sets SQLite `PRAGMA query_only=ON` before fixed metadata reads. Every request checks the host gate before serving database information. Unknown names map to 404; missing authorization integration denies access.

The first vertical slice is a responsive, server-rendered overview: registered database list, per-database table/view listing, object counts and reliable file size. MiniORMUtils supplies per-request SQLite connection lifecycle while its SQL object performs bounded fixed metadata queries. MiniHTML builds the page; all database-controlled text is escaped because MiniHTML's `.text` method itself does not escape. There are no writes, arbitrary SQL endpoints, browsing-by-path, or invented dashboard metrics in M1. Bootstrap-inspired styling follows Pakai's current convention.

Route registration will use the verified EndsMeet methods (GET only) and non-conflicting `BasePath` routes. The demo will register Asadi routes before the host's single `App.Start`, and keep the normal host route registered alongside it. EndsMeet has no public `RemoveHandler`, so dynamic unregister is unsupported; disable/remove the module by omitting its registration before startup.

## Implementation plan

1. Create a B4J project/source tree and minimal demo host using EndsMeet 4.03 conventions.
2. Implement explicit database registration, canonical path checks, MiniORMUtils no-create connection setup, and a reusable metadata query layer.
3. Add a fail-closed host gate contract and register only GET routes on the supplied server.
4. Render the M1 workspace with escaped names, schema object overview, responsive navigation, and clear empty/error states.
5. Add integration and isolated SQLite tests only after selecting a concrete driver artifact; compile using B4J if installed. Record exact compile/test status rather than assuming it.

## Unresolved risks

1. B4JBuilder 10.70 is installed at `C:\Program Files\B4X\B4J\B4JBuilder.exe`; source and demo projects compile successfully with Java 19 using `-Task=Build -NoClean=True -ShowWarnings=True`.
2. Verify MiniORMUtils 6.04's `Open`/`Close` behavior, SQLite `query_only` enforcement, paths containing spaces/Unicode, and no-create behavior with the installed Xerial 3.53.2.1 in the actual B4J runtime.
3. The host authentication and CSRF integration remains application-specific. Reads use GET; `POST` exists only on the SQL workspace and row-edit routes. Both POST routes require a `Sec-Fetch-Site`/`Origin` check against `Host`, and row edits additionally require the signed CSRF cookie/field pair described in the M4 note. The host admin gate is still required on every request. Configure an explicit host admin gate before exposure.
4. EndsMeet has no public route removal method, so runtime uninstall after registration is unsupported; opt-out is before `App.Start`.

## M1 implementation note (2026-10-27)

Added `source/Pakai-Asadi.b4j`, `PakaiAsadi.bas`, `AsadiState.bas`, and `AsadiHandler.bas`. M1 has an allowlisted existing-file registration API, canonical allowed-directory checks, a host authorization callback checked on every request, pre-registration route-overlap detection against `App.routes`, per-request MiniORM-managed connections with SQLite `query_only`, MiniHTML rendering, a bounded schema listing, and escaped names. Driver and MiniHTML/MiniORM dependencies are pinned in `source/libs.json`. `tests/M1-checklist.md` lists repeatable checks; they have not been executed. No `.b4xlib` has been generated and no compilation success is claimed.

## User-created Pakai/Lanyard host integration (2026-10-27)

The checkout now also contains the user's Pakai Server (6.99) host at `demo/demo.b4j`, with Lanyard auth modules and `App.srvr.AddFilter("/*", "AuthFilter", False)`. The actual source generated by the user's prior B4J build under `demo/Objects/src` reports EndsMeet **4.03**, whereas the template's initial `demo/libs.json` declared 4.02. The project manifest was updated to 4.03 to match that observed compiled source. The installed `sqlite-jdbc.jar` was inspected and is version 3.53.2.1; both manifests now pin this actual host artifact.

Verified Lanyard host behavior from the checked-out files:

- `AuthFilter` allows `/assets/`, `/login`, `/register`; other unauthenticated requests are redirected to `/login`. An authenticated session only proves there is a `user` attribute; it does not authorize admin access.
- `AuthHandler` stores both `user` and `role` in the session. New registrations use role `user`; `AuthModel` uses direct stored-password comparison (plain text), so this demo authentication setup is not suitable for production deployment without correcting password storage/verification.
- Asadi's integration adds `Main.AuthorizeAsadi(req)` and requires session `role = admin` on every Asadi handler call. Lanyard's filter remains the login gate; the extra callback is the separate admin authorization gate. The only state-changing HTTP method is `POST` on the SQL workspace, which additionally requires a same-origin browser signal; the SQL itself is executed read-only.
- Asadi is registered only for the configured SQLite database under the directory read from `sqlite.ini`. The normal Pakai routes remain present. Non-SQLite build variants skip Asadi registration.

The user-created `demo/Objects` database/config/runtime output and `demo/AutoBackups` are kept out of version control by `.gitignore`; builds were run with `-NoClean=True`. Both `source/Pakai-Asadi.b4j` and `demo/demo.b4j` completed successful B4JBuilder 10.70 Build tasks.

## M2 implementation note (2026-10-28)

M2 adds schema-object detail pages and a bounded, read-only table/view browser to the existing handler. Object pages read only `sqlite_master` rows for indexes and triggers. Table pages use `PRAGMA table_info`, `PRAGMA foreign_key_list`, and `PRAGMA index_list`, then render up to 50 columns with 25 rows per request. Sorting is restricted to schema-derived column names; search values are bound and escaped for `LIKE`; pagination and search lengths are bounded. Every selected value is cast to text except BLOBs, which are represented by their byte length. Column data is rendered on one line with a capped ellipsis preview, and long values retain an escaped `title` attribute.

The standalone source host was launched on 2026-10-28 with Java 19.0.2 and exercised against a disposable `source/data/demo.db` containing a 61-row fixture with NULLs, BLOBs, long text, Unicode, an HTML payload, a view, an index, a trigger, and a foreign key. Verified behavior includes 25-row pages, last-page and empty-page states, ascending/descending sorting, literal `%`/`_` search, Unicode search, escaped HTML in data and reflected search text, quoted identifiers, schema details, sticky grid headers, security headers, and `400`/`404`/`405` handling. A non-loopback request received `403` from the standalone gate. The fixture and repeatable steps are in `tests/M2-fixture.sql` and `tests/M2-checklist.md`.

## M3 implementation note (2026-10-28)

M3 adds a read-only SQL workspace at `/asadi/db/<name>/sql`. Because `jSQL`'s `ResultSet` wrapper cannot expose column metadata or distinguish BLOBs without garbling them, this page uses raw JDBC through `JavaObject`: `DriverManager.getConnection("jdbc:sqlite:<path>?open_mode=1")`, `createStatement`, `execute`, and `getResultSet`. The read-only file handle is the enforcement layer; a single-statement scanner skips strings, quoted identifiers, line/block comments, and rejects anything after a statement terminator. Allowed starting keywords are `SELECT`, `WITH`, `VALUES`, `EXPLAIN`, and `PRAGMA`; `ATTACH`/`DETACH` are rejected explicitly, and `TABLE` is rejected because the installed driver reports it as a syntax error. Output is capped at 200 rows and 50 columns, displayed text at 160 characters, stored cell text at 2,000 characters, and input SQL at 20,000 characters. BLOBs are read with `getBytes` and shown by size. JDBC errors are cut at `[SQLITE` to drop Java class prefixes and redact the registered absolute path.

`PakaiAsadi.Start` now registers `GET <base>`, `GET <base>/*`, and `POST <base>/*`; the handler accepts `POST` only on the SQL route and returns `405` with an explicit `Allow` header elsewhere. `POST` requires `Sec-Fetch-Site: same-origin`/`none` when present, otherwise a matching `Origin`/`Host`; the preview proxy's `Origin: null` is allowed because the host authorization gate remains authoritative.

Verified on 2026-10-28 against the disposable fixture: form GET, typed grids for `SELECT`/`PRAGMA`/`EXPLAIN`/`VALUES`, NULL and BLOB rendering, Unicode and literal search, semicolons inside strings, trailing semicolons, leading comments, no-result statements, both output caps, multi-statement/`DELETE`/`ATTACH` rejection, `[SQLITE_READONLY]` for a write CTE, sanitized syntax errors, 400/403/405 paths, `Allow` headers, security headers, an unchanged 61-row fixture, and the origin matrix. The grid was checked in a browser for sticky headers, the `60vh` scroll container, and preserved SQL. Steps are in `tests/M3-checklist.md`.

M1/M2/M3 remaining limitations:

- The component still references the host main module (`Main`) for its authorization callback. A `BuildLibrary` attempt therefore fails with "Cannot access excluded module: main". M5 packaging will need an adapter contract that does not reference the main module, or must ship the handler/state modules outside the library with host wiring. Both normal B4J Build tasks succeed.
- The demo's Lanyard authentication stores/compares plaintext passwords; it is a host sample, not a production authentication implementation.
- At M3, editing, exports, and a packaged `.b4xlib` did not exist and there was no CSRF token. M4 adds editing, exports, and CSRF (see the M4 note below); packaging remains open. The SQL workspace is still read-only.
- The installed Xerial driver accepts `Statement.setQueryTimeout` but does not enforce it. A runaway query holds its request thread until SQLite finishes; there is no cancellation path. The driver also materializes each returned BLOB/text value before the display cap, so large values can consume memory even though the page keeps only previews. Restrict the workspace to trusted administrators and apply host/proxy timeouts.
- Search performs a parameterized `LIKE` scan over up to 50 non-BLOB columns; there is no FTS index or query timeout. It is appropriate for an admin tool on bounded databases, not as a public search endpoint.

## M4 implementation note (2026-10-28)

M4 adds CSRF-protected row editing and CSV/JSON exports while keeping the SQL workspace read-only.

CSRF uses a signed double-submit token: a random 16-byte nonce plus an HMAC-SHA256 signature over it, keyed by a per-process secret generated with `SecureRandom` and stored as base64url. The token is written to the `asadi_csrf` cookie (`Path=<base>`, `Max-Age=28800`, `HttpOnly`, `SameSite=Strict`, `Secure` only when the request is secure) and into a hidden `csrf` field. A write is accepted only when the field equals the cookie, the signature verifies, and the request is same-origin by `Sec-Fetch-Site` (`same-origin` or `none`) or, when that header is absent, by comparing the `Origin` host with `Host`. `Origin: null` is allowed for the preview proxy; the host admin gate remains authoritative.

Editing uses the existing `open_mode=2` JDBC handle. A key plan prefers declared primary-key columns and otherwise uses the first unshadowed `rowid` alias (`_rowid_`, `rowid`, `oid`). BLOB keys and tables that shadow all three aliases are not editable; views, BLOB columns, and primary-key values are read-only in the form. Insert skips blank integer primary keys, blank columns with declared defaults, and blank numeric columns (so they store `NULL` rather than text), and rejects a blank `NOT NULL` numeric column without a default. Update and delete carry hidden original values for every non-key, non-BLOB column and append `col IS ?` predicates; an affected-row count of zero returns `409` when the row still exists and `400` when it does not. All writes are single-row and parameterized.

Exports are GET-only `SELECT *` reads over `open_mode=1`, capped at 10,000 rows and 200 columns. CSV writes a UTF-8 BOM, quotes every field, doubles embedded quotes, uses CRLF, emits `NULL` as an empty field and BLOBs as `base64:...`, and prefixes formula-leading characters with an apostrophe while leaving numeric signs intact. JSON emits an array of row objects with `null`, unquoted numbers for numeric JDBC types whose text matches a number, quoted strings otherwise, and `base64:...` BLOBs. The NUMERIC/DECIMAL JDBC types are included because SQLite `NUMERIC` columns hold real numbers in the demo schema; stored text in those columns remains quoted.

`PakaiAsadi.Start` still registers only `GET <base>`, `GET <base>/*`, and `POST <base>/*`; the handler accepts `POST` on `/sql` and `/edit` and returns `405` with `Allow` elsewhere, including `/export`.

Verified on 2026-10-28 against the disposable fixture and a disposable copy of the Lanyard host's `pakai.db`: insert/update/delete with and without the NULL checkbox, default and `NOT NULL` insert rules, rowid and composite-key editing, BLOB-key/view rejection, stale-form `409`, the CSRF matrix (missing, forged, mismatched, cross-site, cross-origin → `403`), cookie flags, the method matrix, CSV BOM/quoting/base64/formula neutralization, JSON `null`/numeric typing in a `NUMERIC` column, the 10,000-row and 200-column caps, and the authorization split (unauthenticated `302` to `/login`, role `user` `403`, role `admin` `200`). Steps are in `tests/M4-checklist.md`.

M4 limitations add to the list above:

- The demo's `#If Release` sets `App.ssl.Enabled = True`; EndsMeet's SSL settings come from a `.env` bundled from `Files/`, which the demo does not ship, so HTTP requests redirect to `https://127.0.0.1:` with an empty port. Add a `.env`/keystore or build locally with SSL disabled.
- Editing is table-only, one row per request, with no schema editor or bulk mode. Optimistic conflict detection compares values; it has no version counter, so a concurrent change that restores identical values is invisible.
- CSV cannot represent `NULL` distinctly from an empty string. Exports materialize every value before writing and have no enforced statement timeout.
- The packaged `.b4xlib` remains M5 work.
