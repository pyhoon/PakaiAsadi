# M2 read-only table browser checklist

These checks cover the schema-object detail pages and the bounded table/view browser. Run them against a disposable SQLite database. Never apply the fixture to the user-created `demo/Objects/pakai.db`, and do not run mutating SQL against a registered production file.

## Setup

1. Build both hosts from their project directories:

   ```powershell
   cd source
   & 'C:\Program Files\B4X\B4J\B4JBuilder.exe' -Task=Build -NoClean=True -ShowWarnings=True

   cd ..\demo
   & 'C:\Program Files\B4X\B4J\B4JBuilder.exe' -Task=Build -NoClean=True -ShowWarnings=True
   ```

2. Start the standalone source host from `source` with the Java 19 runtime. In this environment `java` on `PATH` is Java 8 and cannot load the Java 19 classes.

   ```powershell
   cd source
   & 'C:\Java\jdk-19.0.2\bin\java.exe' -jar Objects\result.jar
   ```

3. The host creates `source/data/demo.db` and registers it as `demo`. Apply the fixture to a copy of that file (or to the demo-created file itself), using the `sqlite3` CLI:

   ```powershell
   sqlite3 source/data/demo.db ".read tests/M2-fixture.sql"
   ```

   The fixture adds `teams`, `people`, `people_directory`, `idx_people_team`, `people_touch`, and `empty_table`, including 61 people, NULLs, BLOBs, long text, Unicode, an HTML/script payload, and literal `%`/`_` characters.

4. Confirm there is exactly one listener on the configured port and that `/` and `/asadi` are served by the same host process.

## HTTP behavior

| Request | Expected |
|---|---|
| `GET /asadi` | `200`, registered database cards |
| `GET /asadi/db/demo` | `200`, table/view/index/trigger counts and object list |
| `GET /asadi/db/demo?table=people` | `200`, page 1, 25 rows plus a `Next` link |
| `GET /asadi/db/demo?table=people&page=3` | `200`, 11 rows, no `Next` link |
| `GET /asadi/db/demo?table=people&page=4` | `200`, empty-page message, `Previous` link only |
| `GET /asadi/db/demo?table=people&sort=name&dir=DESC` | `200`, `name` descending with a ↓ indicator |
| `GET /asadi/db/demo?table=people&sort=c55&dir=DESC` on a wide table | `200`; sorting is valid even when the column is outside the first 50 displayed columns |
| `GET /asadi/db/demo?table=people&q=Zo%C3%AB` | `200`, one matching row, escaped payload displayed as text |
| `GET /asadi/db/demo?table=people&q=100%25` | `200`, one literal match, not all rows |
| `GET /asadi/db/demo?table=people&q=nomatch` | `200`, "No rows match this search." |
| `GET /asadi/db/demo?table=people_directory` | `200`, view notice, no primary-key notice |
| `GET /asadi/db/demo?object=idx_people_team` | `200`, index SQL definition |
| `GET /asadi/db/demo?object=people_touch` | `200`, trigger SQL definition |
| `GET /asadi/db/demo?table=empty_table` | `200`, empty-table message |
| `GET /asadi/db/demo?table=sqlite_master` | `404` |
| `GET /asadi/db/demo?table=..%2Fdemo` | `404` |
| `GET /asadi/db/nope` | `404` |
| `GET /asadi/db/demo?table=people&object=people_touch` | `400` |
| `GET /asadi/db/demo?table=people&page=0` | `400` |
| `GET /asadi/db/demo?table=people&page=abc` | `400` |
| `GET /asadi/db/demo?table=people&sort=nope` | `400` |
| `GET /asadi/db/demo?table=people&dir=sideways` | `400` |
| `GET /asadi/db/demo?table=people&q=` + 201 characters | `400` |
| `POST /asadi` | `405` with `Allow: GET` |

## Content and safety checks

1. Page 1 shows 25 data rows and `Page 1 · 25+ rows shown`. Page 3 shows 11 rows and no `Next` link.
2. `NULL` values render as a `NULL` chip; BLOB cells render as `BLOB · n bytes` without dumping binary data.
3. Long text is capped in the grid, kept on one line, and ellipsized; the cell's `title` attribute contains the truncated preview.
4. A row containing `<script>alert(1)</script>` is displayed as text. The response must not contain an executable `<script>` element or a raw `"><script>` reflection in the search field.
5. Column names containing quotes, ampersands, or spaces work when encoded in `table`, `sort`, and `object` parameters; identifiers are quoted in SQL.
6. The schema section reports column type, nullability, primary-key position, default, and foreign-key target, plus indexes and the SQL definition.
7. The data grid's header remains visible while scrolling inside the grid.
8. Responses include:

   ```text
   Cache-Control: no-store
   X-Content-Type-Options: nosniff
   X-Frame-Options: DENY
   Referrer-Policy: no-referrer
   Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'
   ```

9. Requesting a normal page several times does not change the fixture row count (`SELECT COUNT(*) FROM people` remains 61).
10. From a non-loopback address, the standalone demo's `AuthorizeAsadi` gate returns `403`. Replace the gate with a missing or throwing callback in a test host and confirm access is still denied.
11. In the Lanyard host, no session redirects to `/login`, a `user` role receives `403`, and an `admin` role receives `200`. Use a disposable copy of the host database for account provisioning.

## Last verified

2026-10-28, B4JBuilder 10.70 / Java 19.0.2, standalone source host with the fixture applied to `source/data/demo.db`: build succeeded; all status codes above were observed; page counts, sorting, search escaping, NULL/BLOB rendering, schema details, sticky header, response headers, and the loopback-only gate were verified. The Lanyard role matrix (item 11) was not re-run in this pass.
