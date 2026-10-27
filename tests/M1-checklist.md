# M1 manual verification checklist

Run these checks against the B4J demo host with a disposable copy of its SQLite database. The current host registers the template's `pakai.db` under `demo/Objects`; do not perform mutating or destructive test setup against that host file. They are repeatable manual checks, not yet executed in this environment.

## Host and routes

1. Start `source/Pakai-Asadi.b4j` and verify one listener on port 8080 serves both `/` and `/asadi`.
2. Verify `/asadi` lists `demo`, and `/asadi/db/demo` shows the `notes` table and database overview.
3. Verify the demo's configured database remains unchanged by ordinary GET requests (compare its row count before/after).
4. Request `/asadi` without a Lanyard session; expect redirect to `/login`. Sign in as a `user`-role account; expect 403. Sign in as an `admin`-role account; expect 200. Replace the host gate with a missing or throwing callback in a test host; verify access is denied.
5. Register a host GET route at the configured base path; `Asadi.Start` should reject the collision and should not start the host server.

## Registration/path validation

1. Register two existing disposable SQLite files under different valid logical names; verify both appear.
2. Try unknown/non-ASCII/empty/overlong names and duplicate names; each registration must return `False`.
3. Try a missing file, directory, unreadable file, file outside the allowed directory, and a symlink inside the allowed directory pointing outside; each registration must return `False` and must not create files.
4. Request an unregistered database name, a name containing `../`, a slash, encoded traversal, or an invalid name; expect 404 and no filesystem path in the response.
5. Rename or replace a registered file with an escaping symlink after registration; the request must fail path validation rather than follow the new target.

## Metadata and rendering

1. Test empty databases, tables, views, indexes, triggers, and a database with more than 500 schema objects; verify the empty state and object cap.
2. Create database/table/object names containing `<`, `>`, `&`, quotes, and Unicode; verify visible text is escaped and no injected HTML runs.
3. Enable WAL mode and create a WAL sidecar; verify the displayed footprint reflects main file plus WAL when those files remain present.
4. Verify database/table names do not expose an absolute path or JDBC exception details in success or error responses.

## Driver behavior

1. Use MiniORMUtils 6.04 with Xerial SQLite JDBC 3.53.4.0; verify its `Open` path with `createIfNecessary=False` does not create a removed/missing file and `PRAGMA query_only=ON` rejects a write on the request connection.
2. Test database paths with spaces and non-ASCII characters; verify registration and read-only opening work on Windows and a POSIX platform.

Run with B4J 10.7+ and the declared libraries. Record actual output and driver/JDK versions before treating the checks as passed.
