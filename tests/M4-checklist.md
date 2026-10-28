# M4 row editing and export checklist

These checks cover row insert/update/delete and the CSV/JSON table exports. Run them against a disposable SQLite database. Never apply the fixture to the user-created `demo/Objects/pakai.db`, and do not run mutating requests against a registered production file.

## Setup

1. Build both hosts from their project directories:

   ```powershell
   cd source
   & 'C:\Program Files\B4X\B4J\B4JBuilder.exe' -Task=Build -NoClean=True -ShowWarnings=True

   cd ..\demo
   & 'C:\Program Files\B4X\B4J\B4JBuilder.exe' -Task=Build -NoClean=True -ShowWarnings=True
   ```

2. Start the standalone source host from `source` with the Java 19 runtime:

   ```powershell
   cd source
   & 'C:\Java\jdk-19.0.2\bin\java.exe' -jar Objects\result.jar
   ```

3. Apply [M2-fixture.sql](M2-fixture.sql) so the fixture provides `people` (integer primary key, BLOB, NULLs, 61 rows), `teams`, `people_directory` (a view), and `empty_table`.

4. Open `http://127.0.0.1:8080/asadi/db/demo?table=people`.

### Testing the Lanyard demo host

The demo project embeds its `main` module and uses `#If Release`, which sets `App.ssl.Enabled = True`. EndsMeet then registers its `HttpsFilter` on `/*`, and its SSL settings are read from a `.env` file in `Files/` (bundled into `DirAssets`). The demo does not ship that file, so the server logs `Ssl KeystoreFile is not set` and redirects every HTTP request to `https://127.0.0.1:` with an empty port. HTTP is unusable until either:

- a `.env` with `SSL_ENABLED`, `SSL_PORT`, `SSL_KEYSTORE_DIR`, `SSL_KEYSTORE_FILE`, and `SSL_KEYSTORE_PASSWORD` plus a matching keystore is added to `demo/Files/`, or
- `demo/demo.b4j` is built with `App.ssl.Enabled = False` for the local test.

Verification below used a temporary `App.ssl.Enabled = False` build, then restored `demo.b4j` and rebuilt. Do not commit that change. The demo's login uses plaintext password comparison; use it only on loopback with disposable data.

## Routes and methods

| Request | Expected |
|---|---|
| `GET /asadi/db/demo?table=people` | `200`, per-row `Edit` links, `+ New row`, `Export CSV`, `Export JSON` |
| `GET /asadi/db/demo/edit?table=people&k0=7` | `200`, edit form for row 7 |
| `GET /asadi/db/demo/edit?table=people&new=1` | `200`, insert form |
| `GET /asadi/db/demo/edit?table=people&k0=999999` | `404`, row not found |
| `GET /asadi/db/demo/edit?table=people_directory&k0=1` | `400`, "Only tables can be edited" |
| `GET /asadi/db/demo/export?table=people&format=csv` | `200`, CSV attachment |
| `GET /asadi/db/demo/export?table=people&format=json` | `200`, JSON attachment |
| `GET /asadi/db/demo/export?table=people_directory&format=csv` | `200` (views are exportable) |
| `POST /asadi/db/demo/export?table=people&format=csv` | `405` with `Allow: GET` |
| `POST /asadi/db/demo` | `405` with `Allow: GET` |
| `PUT /asadi/db/demo/sql` | `405` |
| `GET /asadi/db/demo/export?table=nope&format=csv` | `404` |
| `GET /asadi/db/demo/export?table=people&format=xml` | `400` |
| `GET /asadi/db/demo/export?table=sqlite_master&format=csv` | `404` |
| `POST /asadi/db/demo/edit` with a stale form | `409` |
| `GET /asadi/db/nope` or `%2e%2e` in a path | `404` |

## Row editing

| Case | Expected |
|---|---|
| Insert a row with a blank integer primary key | `302` to `...?notice=inserted`; SQLite assigns the next id |
| Insert a row with a blank column that has a declared default | `302`; the default applies (verified: `qty` default `7`, `code` default `'X'`) |
| Insert a row with a blank numeric `NOT NULL` column that has no default | `400`, "Column n requires a value."; no row is created |
| Insert a row with a blank text column | `302`; an empty string is stored (not `NULL`) |
| Update a row | `302` to `...?notice=saved`; only non-key, non-BLOB columns change |
| Tick "Set to NULL" on an update | `302`; the column stores `NULL` |
| Tick "Set to NULL" on a `NOT NULL` column | `400`, "Column x cannot be NULL." |
| Leave a numeric update field blank without ticking NULL | column set to `NULL`, or `400` when the column is `NOT NULL` |
| Change a column to more than 100,000 characters | `400`, "Column x is too long." |
| Submit a form after the row changed elsewhere | `409`, "This row changed after the form was loaded."; the other change is kept |
| Submit a form after the row was deleted | `400`, "This row no longer exists." |
| Delete a row | `302` to `...?notice=deleted`; the row is gone |
| Click "Delete row" | A confirmation modal opens (CSS-only `:target` dialog, no scripts required); Cancel, the backdrop, or `#` closes it and submits nothing |
| Confirm in the modal | Only the modal's "Delete row" button posts the `action=delete` form with the hidden key and originals |
| Table without a primary key | Edit links are shown; rows are addressed by an unshadowed `rowid` alias and the page says so |
| Table whose primary key contains a BLOB | No Edit links; direct edit URL returns `400`, "This table has no usable primary key or rowid and cannot be edited" |
| Composite primary key | Key columns are hidden read-only fields (`fN`/`kN`); editing non-key columns works |
| View | Edit and insert return `400`; the view is browse/export only |

Primary-key columns are rendered as hidden fields and are never rewritten by an update. BLOB columns are read-only and shown as `BLOB · n bytes`. Updates and deletes compare every submitted original non-key, non-BLOB value with `col IS ?`, so a stale form cannot overwrite newer data.

## CSRF

Write requests need a valid signed token in both the `asadi_csrf` cookie and the `csrf` form field, plus a same-origin browser signal.

| Case | Expected |
|---|---|
| Valid cookie, field, and `Sec-Fetch-Site: same-origin` | `302`, row updated |
| No `csrf` field | `403` |
| Forged token (`AAAA.BBBB`) | `403` |
| Cookie from one session, field token from another valid session | `403` |
| `Sec-Fetch-Site: cross-site` | `403` |
| `Sec-Fetch-Site: same-site` | `403` |
| `Origin: http://evil.example` with a valid token | `403` |
| Response cookie | `asadi_csrf=<66-char token>; Path=/asadi; Max-Age=28800; HttpOnly; SameSite=Strict`; `Secure` is appended only when the request is secure |
| Token format | `nonce.signature`, HMAC-SHA256 over the nonce with a per-process secret |

`Origin: null` is accepted when the `Sec-Fetch-Site` header is absent because the preview proxy emits it; the host authorization gate remains the primary control. GET requests never write, so the token is only checked on `POST`.

## Export

| Case | Expected |
|---|---|
| CSV response | `200`, `Content-Type: text/csv; charset=utf-8`, `Content-Disposition: attachment; filename="pakai-people.csv"` |
| CSV encoding | Starts with the UTF-8 BOM `EF BB BF`, CRLF line endings, every field quoted, embedded quotes doubled |
| CSV `NULL` | Empty quoted field |
| CSV BLOB | `base64:<data>` |
| CSV formula injection | Leading `=`, `@`, tab, CR, LF are prefixed with an apostrophe; `+`/`-` are neutralized unless the value is a number |
| JSON response | `200`, `Content-Type: application/json; charset=utf-8` |
| JSON shape | Array of row objects keyed by column label |
| JSON `NULL` | `null` |
| JSON numeric columns | Unquoted numbers for integer/real/numeric/decimal values (verified: `product_price NUMERIC` exports `99.9`, `score REAL` exports `1.5`); text stored in those columns stays quoted |
| JSON BLOB | `"base64:<data>"` |
| Row cap | 10,000 rows; `X-Asadi-Row-Limit: 10000`; a 10,001-row table produces 10,001 CSV lines including the header |
| Column cap | More than 200 columns returns `400`, "This table has more than 200 columns; narrow it before exporting" |
| Unknown table, `sqlite_master`, unknown database | `404` |
| Bad or missing `format` | `400` |
| `POST` export | `405` |

CSV cannot distinguish `NULL` from an empty string; JSON can. Both formats stream row by row, but each value is materialized by the driver before it is written.

## Authorization (Lanyard demo host)

| Case | Expected |
|---|---|
| Unauthenticated `GET /asadi` | `302` to `/login` (host `AuthFilter`) |
| Unauthenticated `POST /asadi/db/pakai/edit` | `302` to `/login` |
| Registered account with role `user` (`GET /asadi`, table, edit, export) | `403` on every Asadi route |
| Account with role `admin` | `200`, full editing and export flows |
| Standalone source host from a non-loopback address | `403` (see [M2-checklist.md](M2-checklist.md)) |

Promote a test account to `admin` only through a trusted provisioning step; `/register` must not grant admin.

## Last verified

2026-10-28, B4JBuilder 10.70 / Java 19.0.2.

- Both projects built successfully from the final M4 sources.
- Standalone host, `source/data/demo.db` with the 61-row fixture: insert, update (including the NULL checkbox), and delete on `empty_table`; the delete confirmation modal opens and cancels without a request; default and `NOT NULL` insert rules; rowid-table editing; BLOB-key and view rejection; composite-key editing; a stale form returning `409`; the CSRF matrix (missing, forged, mismatched, cross-site, cross-origin → `403`); the method matrix; CSV/JSON exports including BOM, quoting, base64 BLOBs, numeric JSON typing, the 10,000-row cap, and the 200-column `400`; `sqlite_master` and traversal returning `404`. Fixture afterward: 61 `people` rows, `empty_table` empty, row 7 still `Person 7`.
- Lanyard demo host on a disposable copy of `pakai.db`: unauthenticated requests redirected to `/login`; a role `user` account received `403` on all four Asadi routes; an `admin` account loaded the overview, table page, and edit page; an update (and restore), an insert and delete, and both exports succeeded; the CSRF cookie/field mismatch returned `403`.
- Browser checks on the standalone host: table page shows Edit links, `+ New row`, and both export links; edit page shows `id · INTEGER · PRIMARY KEY`, `name · TEXT · required`, a read-only BLOB, NULL chips, and no horizontal overflow; "Delete row" opens the confirmation dialog and Cancel closes it without submitting; the workspace badge reads `♙ Read and write`; no console errors.
- Demo host caveat: `#If Release` enables SSL, and without a bundled `.env`/keystore EndsMeet redirects HTTP to `https://127.0.0.1:`. The demo was verified with a temporary `App.ssl.Enabled = False` build; `demo.b4j` was restored and rebuilt afterwards.

## Known limitations

- Editing covers tables only. Views, BLOB columns, BLOB primary keys, and primary-key values cannot be changed through the form.
- There is no schema editor, no bulk edit, and each request changes at most one row. Inserts and updates are single statements, so there is no multi-row transaction.
- Conflict detection compares submitted originals with `IS ?`; a concurrent change that restores the exact same values is indistinguishable from no change. There is no monotonic version column.
- The driver materializes values before the 100,000-character edit cap and before export writes, and no query timeout is enforced. Keep the workspace on trusted databases behind a host/proxy timeout.
- The demo host stores passwords in plain text and must not be deployed as-is.
- A packaged `.b4xlib` (M5) does not exist yet; both hosts are built as applications.
