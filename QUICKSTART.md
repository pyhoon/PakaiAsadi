# Pakai Asadi quick start

This guide is for B4J developers adding the Pakai Asadi SQLite workspace to an existing server. It covers the Pakai Server template (Lanyard authentication) and a plain B4J + EndsMeet host.

Asadi is not a standalone application. It registers pages on the server you already run, reuses that server's authentication, and never opens its own port.

## 1. What you need

| Component | Version tested here |
|---|---|
| B4J | 10.7 or newer |
| EndsMeet | 4.03 |
| MiniHTML | 4.02 |
| MiniORMUtils | 6.04 |
| Xerial `sqlite-jdbc` | 3.53.2.1 |
| Pakai Asadi | 1.00 (`.b4xlib`) |

The `.b4xlib` declares these as `B4J.DependsOn`, so the B4J IDE adds them when you add Asadi. If you manage libraries by hand, install them first.

## 2. Install the library

If you received a release archive, skip the build command and copy that file into the additional libraries folder. To build it from this repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\package-b4xlib.ps1
```

That writes `release/PakaiAsadi.b4xlib`.

Copy it into the B4J additional libraries folder, then restart B4J:

```powershell
Copy-Item -LiteralPath release\PakaiAsadi.b4xlib -Destination C:\B4X\Additional\B4J\
```

In the IDE, open **Libraries** and tick **PakaiAsadi**. Keep EndsMeet, MiniHTML, and MiniORMUtils ticked; `sqlite-jdbc` is resolved from the library manifest. The archive contains `AsadiHandler`, `AsadiState`, and `PakaiAsadi`; you do not copy any `.bas` files into your project.

## 3. Prepare a database file

Asadi only manages SQLite files that already exist. It never creates a database and never accepts a path from a web request.

Create the directory and the file yourself, for example:

```powershell
New-Item -ItemType Directory -Force data | Out-Null
sqlite3 data\app.db "CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY, title TEXT NOT NULL, body TEXT);"
```

The file must be:

- readable (and writable if you want the table editor),
- inside the directory you pass to `Initialize`,
- registered under a name matching `[A-Za-z][A-Za-z0-9_-]{0,63}`.

Canonical paths are checked, so `..`, symlinks, and files outside the allowed directory are rejected.

## 4. Integrate with a Pakai Server template

The included `demo/demo.b4j` is a working example based on the Pakai Server/Lanyard template. It consumes the packaged archive exactly as an integrator would: tick `pakaiasadi` and install `release/PakaiAsadi.b4xlib` into `C:\B4X\Additional\B4J` before building; the demo contains no Asadi modules. The template already provides `EndsMeet`, `MiniORM` (`ORM`), the global `AuthFilter`, and `tbl_users` with a `role` column.

### 4.1 Declare the component

```vb
Sub Process_Globals
    Public App As EndsMeet
    Private Asadi As PakaiAsadi
    ' ... the template's existing globals
End Sub
```

### 4.2 Register Asadi before the server starts

In `AppStart`, after the template has loaded its configuration and initialized its own database, and before `App.Start`:

```vb
Sub AppStart (Args() As String)
    App.Initialize
    App.LoadConfig

    ' ... the template's normal route registration ...

    App.srvr.AddFilter("/*", "AuthFilter", False)
    ORM.InitDatabase

    ' Asadi manages SQLite files only. Skip it for the MariaDB/MySQL builds.
    #If MariaDB
    Log("Pakai Asadi routes are not registered for non-SQLite builds")
    #Else If MySQL
    Log("Pakai Asadi routes are not registered for non-SQLite builds")
    #Else
    RegisterAsadi
    #End If

    App.Start
    Log(App.StartupMessage)
    StartMessageLoop
End Sub
```

### 4.3 Read the database settings and register the file

The Pakai template stores its SQLite target in `sqlite.ini`:

```ini
DbType=SQLite
DbDir=
DbFile=pakai.db
```

Register the same file with Asadi:

```vb
Private Sub RegisterAsadi
    Dim DbConfig As Map = File.ReadMap(File.DirApp, "sqlite.ini")
    Dim DbDirectory As String = DbConfig.GetDefault("DbDir", "")
    If DbDirectory = "" Then DbDirectory = File.DirApp

    Dim DirectoryFile As JavaObject
    DirectoryFile.InitializeNewInstance("java.io.File", Array(DbDirectory))
    If DirectoryFile.RunMethod("isAbsolute", Null) = False Then
        DbDirectory = File.Combine(File.DirApp, DbDirectory)
    End If
    DirectoryFile.InitializeNewInstance("java.io.File", Array(DbDirectory))
    DbDirectory = DirectoryFile.RunMethod("getCanonicalPath", Null)

    Dim DbPath As String = File.Combine(DbDirectory, DbConfig.GetDefault("DbFile", "pakai.db"))

    Asadi.Initialize(App, DbDirectory, "AuthorizeAsadi")
    Asadi.BasePath = "/asadi"
    If Asadi.AddDatabase("pakai", DbPath) = False Then
        Log("Pakai Asadi: configured SQLite file was not registered")
        Return
    End If
    If Asadi.Start = False Then Log("Pakai Asadi: routes were not registered")
End Sub
```

`ORM.InitDatabase` runs first so the template has created `pakai.db`; `AddDatabase` refuses a missing file.

### 4.4 Gate the workspace to admins

The global `AuthFilter` handles login. Asadi additionally calls a sub in your main module on every request and denies access unless it returns `True`:

```vb
Public Sub AuthorizeAsadi (req As ServletRequest) As Boolean
    Try
        Dim Role As Object = req.GetSession.GetAttribute("role")
        If Role = Null Then Return False
        Return Role.As(String).EqualsIgnoreCase("admin")
    Catch
        Return False
    End Try
End Sub
```

New Lanyard accounts get role `user`. Promote a trusted account through your normal admin provisioning process; never let self-registration grant `admin`. For the demo's SQLite database, a direct promotion looks like:

```sql
UPDATE tbl_users SET role = 'admin' WHERE username = 'your-admin-name';
```

The demo compares plaintext passwords. Treat it as a template, not as a production authentication system.

### 4.5 Optional navigation link

The demo adds the workspace to the template's navbar:

```vb
MH.NavLinkItem("Asadi", "/asadi", "bi bi-database me-2", "Asadi").up(nav1)
```

## 5. Integrate with a plain B4J + EndsMeet server

If you are not using the Pakai template, the whole integration is the block below. Register your own routes as usual, then initialize Asadi before `App.Start`.

```vb
Sub Process_Globals
    Private App As EndsMeet
    Private Asadi As PakaiAsadi
End Sub

Sub AppStart (Args() As String)
    App.Initialize
    App.Port = 8080
    App.Get("", "HomeHandler")   ' your existing root route

    File.MakeDir(File.DirApp, "data")
    Dim DbDirectory As String = File.Combine(File.DirApp, "data")
    Dim DbPath As String = File.Combine(DbDirectory, "app.db")

    Asadi.Initialize(App, DbDirectory, "AuthorizeAsadi")
    Asadi.BasePath = "/asadi"   ' the default
    If Asadi.AddDatabase("app", DbPath) = False Then
        Log("Asadi: database was not registered")
        Return
    End If
    If Asadi.Start = False Then
        Log("Asadi: routes were not registered")
        Return
    End If

    App.Start
    Log(App.StartupMessage)
    StartMessageLoop
End Sub

' Replace this with your real admin check.
' The loopback test is for local development only and must not ship to production.
Public Sub AuthorizeAsadi (req As ServletRequest) As Boolean
    Dim Address As String = req.RemoteAddress
    Return Address = "127.0.0.1" Or Address = "::1" Or Address = "0:0:0:0:0:0:0:1"
End Sub
```

The callback must be `Public` and live in the main code module (B4J names it `Main`). Asadi resolves it by name so the check also works when the library is packaged.

If your host needs a different URL prefix, set `Asadi.BasePath` before `Start`. A prefix that overlaps an existing EndsMeet route is rejected.

## 6. Build and run

Build your host project normally. Launch it with the same Java runtime the B4J IDE uses. Open:

```
http://127.0.0.1:8080/asadi
```

With the Pakai demo, log in first as an account whose role is `admin`. The workspace shows one card per registered database.

### First checks

1. The dashboard lists the database and its table/view/index counts.
2. Open a table. The structure panel shows columns, keys, and indexes.
3. Use **Edit** on a row, change a harmless value, and save. The table reloads with the new value.
4. Open the SQL workspace and run `SELECT 1`. Writes such as `DELETE` are rejected there.
5. Export a small table as CSV and confirm a spreadsheet opens it with correct Unicode.

## 7. Security checklist

- **Host authorization is the only login.** Asadi has no accounts, sessions, or password store. If your callback returns `True` for everyone, you have published a database editor.
- Run behind HTTPS. The CSRF cookie is marked `Secure` automatically when the request is secure.
- Limit the workspace to trusted administrators. The SQL workspace can read anything in the registered file.
- Keep registered files in a dedicated directory and back them up. The table editor writes; exports are not backups.
- Do not use the loopback gate from the sample in production.
- One Asadi instance per host process. `Initialize` logs and ignores a second one.

Built-in protections you do not need to add: the fail-closed authorization callback, signed double-submit CSRF tokens on every write, origin/`Sec-Fetch-Site` checks, parameterized SQL, identifier whitelisting, a read-only SQL workspace, path allowlisting, escaped output, and restrictive response headers.

## 8. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `/asadi` returns `404` | `Start` was not called, returned `False`, or ran after `App.Start`. Check the log for `routes were not registered` or a `BasePath` overlap. |
| Redirected to `/login` | Your global auth filter rejected the request. Log in first. |
| Demo redirects to `https://127.0.0.1:` | The demo's Release build enables SSL but ships no `.env`. Add SSL settings or build locally with `App.ssl.Enabled = False`. |
| `403 Administration access is not configured` | The main module has no `Public Sub` with the name passed to `Initialize`. |
| `403 You are not authorized to administer databases` | `AuthorizeAsadi` returned `False`, or the `role` session attribute is not `admin`. |
| `AddDatabase` returns `False` | The file does not exist, is outside the allowed directory, is unreadable, has an invalid name, is already registered, or was added after `Start`. |
| Log: `configured database directory is invalid` | The allowed directory passed to `Initialize` does not exist; create it first. |
| Log: `configured BasePath overlaps an existing EndsMeet route` | Choose a different `BasePath` or remove the conflicting route. |
| Log: `authorization check failed: ...` | The callback threw. Read the exception text and fix the host check. |
| Server fails to start or JDBC errors appear | Ensure `sqlite-jdbc` is on the classpath. The library declares it, but a hand-managed project must include it. |
| Edit/delete returns `409` | Another change landed after the form was loaded. Reload the row and retry. |

## 9. Limits worth knowing

- Editing is table-only, one row per request. Views are browse/export only. There is no schema editor and no bulk edit.
- Primary-key and BLOB values are read-only in the editor. Tables without a primary key are edited through a `rowid` alias when one is available.
- Tables with more than 50 columns show the first 50; search covers the first 50 non-BLOB columns.
- CSV/JSON exports stop at 10,000 rows and 200 columns.
- The SQL workspace returns at most 200 rows and 50 columns and has no enforced query timeout.
- It can manage several registered files, but it is an admin tool for one host, not a multi-tenant database service.

For the public API, behavior, and verification details, see [README.md](README.md), [tests/M5-checklist.md](tests/M5-checklist.md), and [RECONNAISSANCE.md](RECONNAISSANCE.md).
