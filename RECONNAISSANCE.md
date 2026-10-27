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

The public B4J component will be configured by trusted host code with an existing `EndsMeet` instance, a normalized base path, explicit named database paths, and a required host authorization gate. `Start` means “register Asadi's GET routes”; it never means “start the HTTP server”. Database names are opaque logical identifiers, and HTTP paths never contain filesystem paths. Registration canonicalizes an already existing file, rejects duplicate/invalid names, and uses MiniORMUtils' SQLite open API with `createIfNecessary=False`; each request sets SQLite `PRAGMA query_only=ON` before fixed metadata reads. Every request checks the host gate before serving database information. Unknown names map to 404; missing authorization integration denies access.

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
3. The host authentication and CSRF integration remains application-specific. The M1 vertical slice is GET-only and therefore has no state-changing browser routes; configure an explicit host admin gate before exposure.
4. EndsMeet has no public route removal method, so runtime uninstall after registration is unsupported; opt-out is before `App.Start`.

## M1 implementation note (2026-10-27)

Added `source/Pakai-Asadi.b4j`, `PakaiAsadi.bas`, `AsadiState.bas`, and `AsadiHandler.bas`. M1 has an allowlisted existing-file registration API, canonical allowed-directory checks, a host authorization callback checked on every request, pre-registration route-overlap detection against `App.routes`, per-request MiniORM-managed connections with SQLite `query_only`, MiniHTML rendering, a bounded schema listing, and escaped names. Driver and MiniHTML/MiniORM dependencies are pinned in `source/libs.json`. `tests/M1-checklist.md` lists repeatable checks; they have not been executed. No `.b4xlib` has been generated and no compilation success is claimed.

## User-created Pakai/Lanyard host integration (2026-10-27)

The checkout now also contains the user's Pakai Server (6.99) host at `demo/demo.b4j`, with Lanyard auth modules and `App.srvr.AddFilter("/*", "AuthFilter", False)`. The actual source generated by the user's prior B4J build under `demo/Objects/src` reports EndsMeet **4.03**, whereas the template's initial `demo/libs.json` declared 4.02. The project manifest was updated to 4.03 to match that observed compiled source. The installed `sqlite-jdbc.jar` was inspected and is version 3.53.2.1; both manifests now pin this actual host artifact.

Verified Lanyard host behavior from the checked-out files:

- `AuthFilter` allows `/assets/`, `/login`, `/register`; other unauthenticated requests are redirected to `/login`. An authenticated session only proves there is a `user` attribute; it does not authorize admin access.
- `AuthHandler` stores both `user` and `role` in the session. New registrations use role `user`; `AuthModel` uses direct stored-password comparison (plain text), so this demo authentication setup is not suitable for production deployment without correcting password storage/verification.
- Asadi's integration adds `Main.AuthorizeAsadi(req)` and requires session `role = admin` on every Asadi handler call. Lanyard's filter remains the login gate; the extra callback is the separate admin authorization gate. Current Asadi routes are GET-only, so no Asadi state-changing request is exposed in this milestone.
- Asadi is registered only for the configured SQLite database under the directory read from `sqlite.ini`. The normal Pakai routes remain present. Non-SQLite build variants skip Asadi registration.

The user-created `demo/Objects` database/config/runtime output and `demo/AutoBackups` are kept out of version control by `.gitignore`; builds were run with `-NoClean=True`. Both `source/Pakai-Asadi.b4j` and `demo/demo.b4j` completed successful B4JBuilder 10.70 Build tasks. The applications were not launched, so no runtime behavior is claimed.
