B4J=true
Group=Handlers
ModulesStructureVersion=1
Type=Class
Version=10.7
@EndOfDesignText@
' Read-only dashboard handler. Every request is gated independently.
Sub Class_Globals
	Private Const MAX_OBJECTS As Int = 500
End Sub

Public Sub Initialize
End Sub

Sub Handle (req As ServletRequest, resp As ServletResponse)
	If AsadiState.Host.IsInitialized = False Or AsadiState.Databases.IsInitialized = False Then
		WriteError(resp, 503, "Administration module is unavailable")
		Return
	End If
	If SubExists(Main, AsadiState.AuthorizationSub) = False Then
		WriteError(resp, 403, "Administration access is not configured")
		Return
	End If
	Dim Authorized As Boolean = False
	Try
		Dim GateResult As Object = CallSub2(Main, AsadiState.AuthorizationSub, req)
		If GateResult Is Boolean Then Authorized = GateResult
	Catch
		Authorized = False
	End Try
	If Authorized = False Then
		WriteError(resp, 403, "You are not authorized to administer databases")
		Return
	End If
	If req.Method.EqualsIgnoreCase("GET") = False Then
		resp.Status = 405
		resp.SetHeader("Allow", "GET")
		WriteError(resp, 405, "Method not allowed")
		Return
	End If
	Dim Path As String = req.RequestURI
	If Path = AsadiState.BasePath Or Path = AsadiState.BasePath & "/" Then
		WriteDashboard(resp)
		Return
	End If
	Dim DbPrefix As String = AsadiState.BasePath & "/db/"
	If Path.StartsWith(DbPrefix) = False Then
		WriteError(resp, 404, "Page not found")
		Return
	End If
	Dim DbName As String = Path.SubString(DbPrefix.Length)
	If DbName.Contains("/") Or Regex.IsMatch("^[A-Za-z][A-Za-z0-9_-]{0,63}$", DbName) = False Or AsadiState.Databases.ContainsKey(DbName) = False Then
		WriteError(resp, 404, "Database not found")
		Return
	End If
	WriteDatabase(resp, DbName)
End Sub

Private Sub WriteDashboard (resp As ServletResponse)
	Dim Content As MiniHtml = NewTag(Null, "section", "workspace")
	AddText(Content, "div", "eyebrow", "DATABASES")
	AddText(Content, "h1", "", "Your data workspace")
	AddText(Content, "p", "muted", "SQLite files explicitly registered by this application.")
	If AsadiState.Databases.Size = 0 Then
		Dim Empty As MiniHtml = NewTag(Content, "section", "empty")
		AddText(Empty, "div", "empty-icon", "◫")
		AddText(Empty, "h2", "", "No databases registered")
		AddText(Empty, "p", "", "Add a database from trusted host code to make it available here.")
	Else
		Dim Grid As MiniHtml = NewTag(Content, "section", "db-grid")
		For Each Name As String In AsadiState.Databases.Keys
			Dim Stats As Map = ReadStats(Name)
			Dim Card As MiniHtml = NewTag(Grid, "a", "db-card")
			Card.attr("href", AsadiState.BasePath & "/db/" & Name)
			AddText(Card, "span", "db-icon", "▤")
			AddText(Card, "span", "db-name", Name)
			AddText(Card, "span", "db-meta", Stats.Get("objects") & " schema objects · " & FormatSize(Stats.Get("size")) & " on disk")
			AddText(Card, "span", "card-arrow", "↗")
		Next
	End If
	WritePage(resp, "Workspace", Content)
End Sub

Private Sub WriteDatabase (resp As ServletResponse, Name As String)
	Dim Path As String = AsadiState.Databases.Get(Name)
	If ValidateRegisteredPath(Path) = False Then
		WriteError(resp, 404, "Database is unavailable")
		Return
	End If
	Dim Db As MiniORM
	Try
		Db = OpenMetadataDatabase(Path)
		Dim Sql As SQL = Db.SQL
		Dim Objects As ResultSet = Sql.ExecQuery("SELECT type, name FROM sqlite_master WHERE type IN ('table','view','index','trigger') AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 1 WHEN 'view' THEN 2 WHEN 'index' THEN 3 ELSE 4 END, name LIMIT 501")
		Dim SchemaObjects As List
		SchemaObjects.Initialize
		Dim Tables As Int
		Dim Views As Int
		Dim Indexes As Int
		Dim Triggers As Int
		Do While Objects.NextRow
			Dim ObjectInfo As Map = CreateMap("type": Objects.GetString("type"), "name": Objects.GetString("name"))
			SchemaObjects.Add(ObjectInfo)
			Select ObjectInfo.Get("type")
				Case "table": Tables = Tables + 1
				Case "view": Views = Views + 1
				Case "index": Indexes = Indexes + 1
				Case "trigger": Triggers = Triggers + 1
			End Select
		Loop
		Objects.Close
		Dim Content As MiniHtml = NewTag(Null, "section", "workspace")
		Dim Back As MiniHtml = AddText(Content, "a", "back", "← All databases")
		Back.attr("href", AsadiState.BasePath)
		AddText(Content, "div", "eyebrow", "DATABASE OVERVIEW")
		AddText(Content, "h1", "", Name)
		AddText(Content, "p", "muted", "Schema objects in this registered SQLite database.")
		Dim Stats As MiniHtml = NewTag(Content, "section", "stats")
		AddStat(Stats, "Tables", Tables)
		AddStat(Stats, "Views", Views)
		AddStat(Stats, "Indexes", Indexes)
		AddStat(Stats, "Triggers", Triggers)
		Dim ObjectList As MiniHtml = NewTag(Content, "section", "objects")
		Dim SectionHead As MiniHtml = NewTag(ObjectList, "div", "section-head")
		AddText(SectionHead, "h2", "", "Schema objects")
		Dim DisplayCount As Int = Min(SchemaObjects.Size, MAX_OBJECTS)
		AddText(SectionHead, "span", "count", "" & DisplayCount)
		If SchemaObjects.Size = 0 Then
			Dim Empty As MiniHtml = NewTag(ObjectList, "div", "empty compact")
			AddText(Empty, "div", "empty-icon", "⌁")
			AddText(Empty, "h2", "", "Nothing here yet")
			AddText(Empty, "p", "", "This database has no user tables, views, indexes, or triggers.")
		Else
			Dim Rows As MiniHtml = NewTag(ObjectList, "div", "object-list")
			For i = 0 To DisplayCount - 1
				Dim ObjectInfo As Map = SchemaObjects.Get(i)
				Dim Row As MiniHtml = NewTag(Rows, "div", "object-row")
				AddText(Row, "span", "object-symbol", TypeIcon(ObjectInfo.Get("type")))
				AddText(Row, "span", "object-title", ObjectInfo.Get("name"))
				AddText(Row, "span", "object-type", ObjectInfo.Get("type"))
			Next
			If SchemaObjects.Size > MAX_OBJECTS Then AddText(ObjectList, "p", "muted note", "Showing the first 500 objects.")
		End If
		Db.Close
		WritePage(resp, Name, Content)
	Catch
		Try
			If Db.IsInitialized Then Db.Close
		Catch
		End Try
		WriteError(resp, 500, "Unable to inspect this database. Check that it is a readable SQLite file.")
	End Try
End Sub

' MiniORM opens the trusted, existing SQLite file with createIfNecessary=False.
' The connection is per request; query_only protects it from writes in this read-only milestone.
Private Sub OpenMetadataDatabase (Path As String) As MiniORM
	Dim FileObject As JavaObject
	FileObject.InitializeNewInstance("java.io.File", Array(Path))
	Dim DbSettings As MiniORMSettings
	DbSettings.Initialize
	Dim Db As MiniORM
	Db.Initialize
	DbSettings.DBType = Db.SQLITE
	DbSettings.DBDir = FileObject.RunMethod("getParent", Null)
	DbSettings.DBFile = FileObject.RunMethod("getName", Null)
	Db.Settings = DbSettings
	Dim Sql As SQL = Db.Open
	Sql.ExecNonQuery("PRAGMA query_only = ON")
	Return Db
End Sub

Private Sub ReadStats (Name As String) As Map
	Dim Result As Map = CreateMap("objects": "Unavailable", "size": 0)
	Dim Path As String = AsadiState.Databases.Get(Name)
	If ValidateRegisteredPath(Path) = False Then Return Result
	Dim Db As MiniORM
	Try
		Db = OpenMetadataDatabase(Path)
		Dim Sql As SQL = Db.SQL
		Result.Put("objects", Sql.ExecQuerySingleResult("SELECT COUNT(*) FROM sqlite_master WHERE type IN ('table','view','index','trigger') AND name NOT LIKE 'sqlite_%'"))
		Db.Close
		Result.Put("size", DatabaseFootprint(Path))
	Catch
		Try
			If Db.IsInitialized Then Db.Close
		Catch
		End Try
	End Try
	Return Result
End Sub

Private Sub DatabaseFootprint (Path As String) As Long
	Dim MainFile As JavaObject
	MainFile.InitializeNewInstance("java.io.File", Array(Path))
	Dim Total As Long = MainFile.RunMethod("length", Null)
	Dim WalFile As JavaObject
	WalFile.InitializeNewInstance("java.io.File", Array(Path & "-wal"))
	If WalFile.RunMethod("isFile", Null) Then Total = Total + WalFile.RunMethod("length", Null)
	Return Total
End Sub

Private Sub ValidateRegisteredPath (Path As String) As Boolean
	Try
		Dim F As JavaObject
		F.InitializeNewInstance("java.io.File", Array(Path))
		Dim Canonical As String = F.RunMethod("getCanonicalPath", Null)
		If Canonical <> Path Or AsadiState.IsAllowedCanonicalPath(Canonical) = False Then Return False
		Return F.RunMethod("isFile", Null) And F.RunMethod("canRead", Null)
	Catch
		Return False
	End Try
End Sub

Private Sub WritePage (resp As ServletResponse, Title As String, Content As MiniHtml)
	Dim Html As MiniHtml = NewTag(Null, "html", "")
	Html.attr("lang", "en")
	Dim Head As MiniHtml = NewTag(Html, "head", "")
	Dim Charset As MiniHtml = NewTag(Head, "meta", "")
	Charset.attr("charset", "utf-8")
	Dim Viewport As MiniHtml = NewTag(Head, "meta", "")
	Viewport.attr("name", "viewport").attr("content", "width=device-width,initial-scale=1")
	Dim ColorScheme As MiniHtml = NewTag(Head, "meta", "")
	ColorScheme.attr("name", "color-scheme").attr("content", "light dark")
	Dim PageTitle As MiniHtml = NewTag(Head, "title", "")
	PageTitle.text(EscapeHtml(Title & " · Pakai Asadi"))
	Dim Style As MiniHtml = NewTag(Head, "style", "")
	Style.text(GetStyles, False)
	Dim Body As MiniHtml = NewTag(Html, "body", "")
	Dim Sidebar As MiniHtml = NewTag(Body, "aside", "sidebar")
	Dim Brand As MiniHtml = NewTag(Sidebar, "a", "brand")
	Brand.attr("href", AsadiState.BasePath)
	AddText(Brand, "span", "brand-mark", "P")
	AddText(Brand, "span", "", "pakai asadi")
	AddText(Sidebar, "div", "nav-label", "WORKSPACE")
	Dim Nav As MiniHtml = NewTag(Sidebar, "a", "nav-item active")
	Nav.attr("href", AsadiState.BasePath)
	Nav.text("▦ &nbsp; Databases")
	AddText(Sidebar, "div", "nav-label db-label", "REGISTERED")
	AddSidebarDatabases(Sidebar)
	Dim SideFoot As MiniHtml = NewTag(Sidebar, "div", "sidebar-foot")
	AddText(SideFoot, "span", "status-dot", "")
	SideFoot.text(" Connected to host server")
	Dim MainContent As MiniHtml = NewTag(Body, "main", "main")
	Dim Topbar As MiniHtml = NewTag(MainContent, "header", "topbar")
	Dim Breadcrumb As MiniHtml = NewTag(Topbar, "div", "crumb")
	AddText(Breadcrumb, "span", "", "Workspace")
	AddText(Breadcrumb, "span", "slash", "/")
	AddText(Breadcrumb, "strong", "", Title)
	Dim Readonly As MiniHtml = NewTag(Topbar, "span", "readonly")
	Readonly.text("♙ &nbsp; Read-only overview")
	Dim ContentArea As MiniHtml = NewTag(MainContent, "div", "content")
	ContentArea.add(Content)
	Dim Footer As MiniHtml = NewTag(ContentArea, "footer", "")
	Footer.text("PAKAI ASADI · Embedded database workspace")
	resp.ContentType = "text/html; charset=utf-8"
	resp.Write(Html.build)
End Sub

Private Sub AddSidebarDatabases (Parent As MiniHtml)
	For Each Name As String In AsadiState.Databases.Keys
		Dim Link As MiniHtml = NewTag(Parent, "a", "side-db")
		Link.attr("href", AsadiState.BasePath & "/db/" & Name)
		Link.text("▤ &nbsp; " & EscapeHtml(Name))
	Next
End Sub

Private Sub WriteError (resp As ServletResponse, Code As Int, Message As String)
	Dim Html As MiniHtml = NewTag(Null, "html", "")
	Html.attr("lang", "en")
	Dim Head As MiniHtml = NewTag(Html, "head", "")
	Dim Charset As MiniHtml = NewTag(Head, "meta", "")
	Charset.attr("charset", "utf-8")
	Dim PageTitle As MiniHtml = NewTag(Head, "title", "")
	PageTitle.text("" & Code & " · Pakai Asadi")
	Dim Body As MiniHtml = NewTag(Html, "body", "error-page")
	Dim Card As MiniHtml = NewTag(Body, "main", "error-card")
	AddText(Card, "small", "eyebrow", "PAKAI ASADI · " & Code)
	AddText(Card, "h1", "", Message)
	AddText(Card, "p", "muted", "The request could not be completed.")
	Dim Style As MiniHtml = NewTag(Head, "style", "")
	Style.text("body{font:16px system-ui;background:#f5f7fb;color:#172033;padding:10vh 8vw}.error-card{max-width:620px;margin:auto;background:white;border:1px solid #e5eaf1;border-radius:18px;padding:40px}.eyebrow{color:#4263eb;font-weight:700;letter-spacing:.12em}.muted{color:#68748a}", False)
	resp.Status = Code
	resp.ContentType = "text/html; charset=utf-8"
	resp.Write(Html.build)
End Sub

Private Sub NewTag (Parent As MiniHtml, TagName As String, Classes As String) As MiniHtml
	Dim Tag As MiniHtml
	Tag.Initialize(TagName)
	If Classes <> "" Then Tag.cls(Classes)
	If Parent <> Null Then Parent.add(Tag)
	Return Tag
End Sub

Private Sub AddText (Parent As MiniHtml, TagName As String, Classes As String, Value As String) As MiniHtml
	Dim Tag As MiniHtml = NewTag(Parent, TagName, Classes)
	Tag.text(EscapeHtml(Value))
	Return Tag
End Sub

Private Sub AddStat (Parent As MiniHtml, Label As String, Value As Int)
	Dim Stat As MiniHtml = NewTag(Parent, "div", "stat")
	AddText(Stat, "span", "stat-label", Label)
	AddText(Stat, "strong", "", "" & Value)
	AddText(Stat, "span", "stat-foot", "in this database")
End Sub

Private Sub TypeIcon (Value As String) As String
	Select Value
		Case "table": Return "▤"
		Case "view": Return "◉"
		Case "index": Return "⌕"
		Case Else: Return "ϟ"
	End Select
End Sub

Private Sub FormatSize (Bytes As Long) As String
	If Bytes < 1024 Then Return Bytes & " B"
	If Bytes < 1048576 Then Return NumberFormat2(Bytes / 1024, 1, 1, 1, False) & " KB"
	If Bytes < 1073741824 Then Return NumberFormat2(Bytes / 1048576, 1, 1, 1, False) & " MB"
	Return NumberFormat2(Bytes / 1073741824, 1, 2, 2, False) & " GB"
End Sub

Private Sub EscapeHtml (Value As String) As String
	Return AsadiState.Host.EscapeHtml(Value)
End Sub

Private Sub getStyles As String
	Return ":root{--ink:#182235;--muted:#778398;--line:#e8edf3;--blue:#4263eb;--bg:#f7f9fc;--surface:#fff;--sidebar:#101a2c;--green:#34c98b}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px system-ui,-apple-system,'Segoe UI',sans-serif;min-height:100vh}.sidebar{position:fixed;inset:0 auto 0 0;width:240px;background:var(--sidebar);color:#fff;padding:24px 16px;display:flex;flex-direction:column}.brand{height:42px;display:flex;align-items:center;gap:11px;color:#fff;text-decoration:none;font-weight:700;padding:0 9px}.brand-mark{display:grid;place-items:center;width:28px;height:28px;background:#4263eb;border-radius:9px}.nav-label{font-size:10px;font-weight:700;letter-spacing:.13em;color:#8290a8;margin:34px 10px 10px}.nav-item,.side-db{display:block;text-decoration:none;color:#cbd4e2;border-radius:9px;padding:11px 12px;font-weight:600}.nav-item.active{background:#202e48}.side-db{font-size:13px;font-weight:500;color:#aab6c9;padding:9px 12px}.sidebar-foot{margin-top:auto;border-top:1px solid #263249;padding:17px 10px 0;color:#aab6c9;font-size:11px}.status-dot{display:inline-block;width:7px;height:7px;border-radius:50%;background:var(--green);margin-right:8px}.main{margin-left:240px;min-height:100vh}.topbar{height:64px;background:var(--surface);border-bottom:1px solid var(--line);display:flex;align-items:center;justify-content:space-between;padding:0 36px;color:#778398}.topbar strong{color:var(--ink)}.slash{padding:0 10px;color:#c4ccd7}.readonly{font-size:11px;color:#66758d;background:#f1f4f8;border:1px solid var(--line);border-radius:20px;padding:7px 11px}.content{max-width:1100px;padding:44px 40px;margin:auto}.eyebrow{font-size:10px;font-weight:700;letter-spacing:.15em;color:var(--blue)}h1{font-size:30px;letter-spacing:-.04em;margin:10px 0 6px}.muted{color:var(--muted);line-height:1.6}.db-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px;margin-top:28px}.db-card{position:relative;background:var(--surface);border:1px solid var(--line);border-radius:13px;padding:20px;text-decoration:none;color:var(--ink);display:grid;grid-template-columns:34px 1fr;align-items:center}.db-card:hover{border-color:#aabaff}.db-icon{width:32px;height:32px;display:grid;place-items:center;background:#eef1ff;color:var(--blue);border-radius:9px;grid-row:span 2}.db-name{font-weight:700;padding-left:12px}.db-meta{font-size:11px;color:var(--muted);padding:5px 0 0 12px}.card-arrow{position:absolute;right:17px;top:17px;color:#9aa6b8}.empty{margin-top:28px;background:var(--surface);border:1px dashed #d6deea;border-radius:14px;text-align:center;padding:45px 20px}.empty h2{font-size:17px}.empty p{color:var(--muted)}.empty-icon{margin:auto auto 14px;width:44px;height:44px;display:grid;place-items:center;border-radius:13px;background:#eef1ff;color:var(--blue);font-size:23px}.back{display:inline-block;text-decoration:none;color:#5d6c83;font-weight:600;margin:0 0 24px}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:26px 0}.stat{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:16px;display:flex;flex-direction:column}.stat-label,.stat-foot{font-size:11px;color:var(--muted)}.stat strong{font-size:25px;margin:8px 0}.objects{background:var(--surface);border:1px solid var(--line);border-radius:13px;overflow:hidden}.section-head{display:flex;justify-content:space-between;padding:18px 20px;border-bottom:1px solid var(--line)}.section-head h2{font-size:17px;margin:0}.count,.object-type{background:#f0f3f8;border-radius:14px;color:#718098;font-size:11px;padding:4px 9px}.object-row{min-height:49px;display:flex;align-items:center;padding:0 20px;border-bottom:1px solid #f0f2f6;gap:12px}.object-symbol{color:#70819c}.object-title{font-weight:600;flex:1}.object-type{font-size:10px}.content footer{margin-top:60px;padding:15px 0;color:#a2acba;font-size:9px;letter-spacing:.1em;font-weight:700}.note{padding:0 20px 12px}@media(max-width:850px){.sidebar{width:200px}.main{margin-left:200px}.content{padding:34px 24px}.topbar{padding:0 22px}.stats{grid-template-columns:repeat(2,1fr)}}@media(max-width:600px){.sidebar{position:relative;width:auto;height:auto;padding:12px;display:block}.nav-label,.side-db,.sidebar-foot{display:none}.nav-item{margin-top:8px}.main{margin-left:0}.topbar{height:54px;padding:0 14px}.readonly{font-size:0;padding:7px}.content{padding:28px 15px}h1{font-size:25px}.db-grid{grid-template-columns:1fr}.stats{gap:8px}.stat{padding:12px}}@media(prefers-reduced-motion:reduce){*{transition:none!important}}@media(prefers-color-scheme:dark){:root{--ink:#e5eaf3;--muted:#9aa7bb;--line:#293449;--bg:#101827;--surface:#172235}.readonly,.count,.object-type{background:#202d42;color:#a9b8d1}.db-icon,.empty-icon{background:#242f50}.object-row{border-color:#243147}.empty{border-color:#35425a}}"
End Sub
