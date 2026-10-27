# M3 SQL workspace checklist

These checks cover the read-only SQL workspace. Run them against a disposable SQLite database. Never apply the fixture to the user-created `demo/Objects/pakai.db`, and do not run mutating SQL against a registered production file.

## Setup

1. Build both hosts from their project directories and start the standalone source host as described in [M2-checklist.md](M2-checklist.md).
2. Apply the M2 fixture so the workspace has representative NULLs, BLOBs, Unicode text, and enough rows to exercise the caps.
3. Open `http://127.0.0.1:8080/asadi/db/demo/sql` from the database overview's **SQL workspace →** link.

## HTTP behavior

| Request | Expected |
|---|---|
| `GET /asadi/db/demo/sql` | `200`, form with a textarea and `Run query` button |
| `POST /asadi/db/demo/sql` with `sql=SELECT 1` | `200`, one-row grid |
| `POST` with `SELECT id, name, email FROM people ORDER BY id DESC LIMIT 30` | `200`, 30-row grid |
| `POST` with `PRAGMA table_info(people)` | `200`, six-column grid |
| `POST` with `EXPLAIN QUERY PLAN SELECT * FROM people WHERE id = 1` | `200`, plan grid |
| `POST` with `VALUES (1, 'a'), (2, NULL)` | `200`, two-row grid |
| `POST` with `PRAGMA query_only=ON` | `200`, "did not return a result set" message |
| `POST` with `SELECT 'a;b' AS x` | `200`, semicolon inside a string is not treated as a terminator |
| `POST` with a trailing `;` | `200` |
| `POST` with a leading `--` or `/* */` comment | `200` |
| `POST` with `SELECT 1; SELECT 2` | `400`, "Only one SQL statement can run at a time." |
| `POST` with `DELETE FROM people` | `400`, read-only statement message |
| `POST` with `WITH x AS (SELECT 1) DELETE FROM people WHERE 0` | `400`, `[SQLITE_READONLY]` |
| `POST` with `ATTACH DATABASE '...' AS x` | `400`, attaching is not allowed |
| `POST` with `SELECT nope FROM people` | `400`, sanitized `[SQLITE_ERROR]` without a file path or Java class prefix |
| `POST` with empty `sql` | `400`, "Enter a SQL statement to run." |
| `POST` with 20,001 characters | `400`, length-limit message |
| `POST /asadi/db/demo` | `405` with `Allow: GET` |
| `DELETE /asadi/db/demo/sql` | `405` with `Allow: GET, POST` |
| `POST /asadi` | `405` with `Allow: GET` |
| `POST` with `Sec-Fetch-Site: cross-site` | `403` |
| `POST` with `Sec-Fetch-Site: same-origin` or `none` | `200` |
| `POST` with `Origin: http://evil.example` | `403` |
| `POST` with `Origin: http://127.0.0.1:8080` | `200` |

## Content and safety checks

1. The form keeps the submitted SQL in the textarea on both success and error.
2. `NULL` renders as a `NULL` chip and BLOB values as `BLOB · n bytes`; binary data is not written to the page.
3. Text longer than 160 characters is ellipsized in the cell and the full 2,000-character-capped value is available through the escaped `title` attribute.
4. A result wider than 50 columns shows the first 50 with "Showing the first 50 of n columns."
5. A result longer than 200 rows shows the first 200 with "showing the first 200" and row 201 is not rendered.
6. The result grid scrolls inside `60vh` and the header row stays visible.
7. Database paths and Java exception class names do not appear in error output.
8. Responses keep `Cache-Control: no-store`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, and the restrictive content security policy.
9. Running read-only statements repeatedly leaves the fixture row count unchanged (`SELECT COUNT(*) FROM people` remains 61).
10. The workspace is reachable only after the host authorization callback succeeds; a `user` role and an unauthenticated request are still denied in the Lanyard host.

## Last verified

2026-10-28, B4JBuilder 10.70 / Java 19.0.2, standalone source host with the fixture applied to `source/data/demo.db`: both projects built successfully; all rows above were observed with `curl`, including the origin matrix, 405 `Allow` headers, 200-row and 50-column caps, multi-statement and `ATTACH` rejection, `[SQLITE_READONLY]` enforcement for a write CTE, sanitized errors, and an unchanged 61-row fixture. The grid was also checked in a browser: 30 rows, six columns, sticky header, `60vh` scroll container, NULL chips, and BLOB sizes. Query timeout is not enforced by the installed Xerial driver (see limitations).

## Known limitations

- No enforced query timeout in Xerial 3.53.2.1: a deliberately long `WITH RECURSIVE` query ran to completion, so a runaway statement holds its request thread. Mitigate at the host/proxy level and expose the workspace only to trusted administrators.
- The driver materializes each returned BLOB/text value before the display cap is applied. The 200-row/50-column caps bound what the page keeps, not peak memory for a query that returns very large values.
- Statement length, row count, column count, and preview size are bounded; execution time and total bytes read are not.
