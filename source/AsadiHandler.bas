B4J=true
Group=Handlers
ModulesStructureVersion=1
Type=Class
Version=10.7
@EndOfDesignText@
' Read-only dashboard handler. Every request is gated independently.
Sub Class_Globals
	Private Const MAX_OBJECTS As Int = 500
	Private Const PAGE_SIZE As Int = 25
	Private Const MAX_DATA_COLUMNS As Int = 50
	Private Const MAX_SEARCH_COLUMNS As Int = 50
	Private Const MAX_SEARCH_LENGTH As Int = 200
	Private Const MAX_TEXT_LENGTH As Int = 160
	Private Const MAX_SQL_LENGTH As Int = 20000
	Private Const MAX_QUERY_ROWS As Int = 200
	Private Const MAX_QUERY_COLUMNS As Int = 50
	Private Const MAX_SQL_VALUE_LENGTH As Int = 2000
End Sub

Public Sub Initialize
End Sub

Sub Handle (req As ServletRequest, resp As ServletResponse)
	resp.SetHeader("Cache-Control", "no-store")
	resp.SetHeader("X-Content-Type-Options", "nosniff")
	resp.SetHeader("X-Frame-Options", "DENY")
	resp.SetHeader("Referrer-Policy", "no-referrer")
	resp.SetHeader("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'")
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
	Dim Method As String = req.Method.ToUpperCase
	Dim Path As String = req.RequestURI
	If Path = AsadiState.BasePath Or Path = AsadiState.BasePath & "/" Then
		If Method <> "GET" Then
			MethodNotAllowed(resp, "GET")
			Return
		End If
		WriteDashboard(resp)
		Return
	End If
	Dim DbPrefix As String = AsadiState.BasePath & "/db/"
	If Path.StartsWith(DbPrefix) = False Then
		WriteError(resp, 404, "Page not found")
		Return
	End If
	Dim Remainder As String = Path.SubString(DbPrefix.Length)
	Dim DbName As String = Remainder
	Dim SubRoute As String = ""
	Dim SlashIndex As Int = Remainder.IndexOf("/")
	If SlashIndex >= 0 Then
		DbName = Remainder.SubString2(0, SlashIndex)
		SubRoute = Remainder.SubString(SlashIndex + 1)
	End If
	If Regex.IsMatch("^[A-Za-z][A-Za-z0-9_-]{0,63}$", DbName) = False Or AsadiState.Databases.ContainsKey(DbName) = False Then
		WriteError(resp, 404, "Database not found")
		Return
	End If
	If SubRoute = "sql" Then
		If Method <> "GET" And Method <> "POST" Then
			MethodNotAllowed(resp, "GET, POST")
			Return
		End If
		If Method = "POST" And IsSameOriginPost(req) = False Then
			WriteError(resp, 403, "This form submission did not come from this application")
			Return
		End If
		WriteSqlWorkspace(resp, DbName, req)
		Return
	End If
	If SubRoute <> "" Then
		WriteError(resp, 404, "Page not found")
		Return
	End If
	If Method <> "GET" Then
		MethodNotAllowed(resp, "GET")
		Return
	End If
	Dim TableName As String = req.GetParameter("table")
	Dim ObjectName As String = req.GetParameter("object")
	If TableName = Null Then TableName = ""
	If ObjectName = Null Then ObjectName = ""
	If TableName <> "" And ObjectName <> "" Then
		WriteError(resp, 400, "Choose a table or a schema object")
		Return
	End If
	WriteDatabase(resp, DbName, TableName, ObjectName, req)
End Sub

Private Sub MethodNotAllowed (resp As ServletResponse, Allowed As String)
	resp.SetHeader("Allow", Allowed)
	WriteError(resp, 405, "Method not allowed")
End Sub

' Browsers mark form posts with Sec-Fetch-Site, which is the most reliable signal.
' Fall back to Origin/Host for clients that do not send it. Origin "null" comes from
' sandboxed or proxied contexts and cannot be compared, so authorization remains the gate.
Private Sub IsSameOriginPost (req As ServletRequest) As Boolean
	Dim FetchSite As String = req.GetHeader("Sec-Fetch-Site")
	If FetchSite <> Null And FetchSite <> "" Then
		Return FetchSite.EqualsIgnoreCase("same-origin") Or FetchSite.EqualsIgnoreCase("none")
	End If
	Dim Origin As String = req.GetHeader("Origin")
	If Origin = Null Or Origin = "" Or Origin.EqualsIgnoreCase("null") Then Return True
	Dim Host As String = req.GetHeader("Host")
	If Host = Null Or Host = "" Then Return False
	Dim OriginHost As String = Origin
	Dim SchemeEnd As Int = OriginHost.IndexOf("://")
	If SchemeEnd >= 0 Then OriginHost = OriginHost.SubString(SchemeEnd + 3)
	Dim Slash As Int = OriginHost.IndexOf("/")
	If Slash >= 0 Then OriginHost = OriginHost.SubString2(0, Slash)
	Return OriginHost.EqualsIgnoreCase(Host)
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

Private Sub WriteDatabase (resp As ServletResponse, Name As String, TableName As String, ObjectName As String, req As ServletRequest)
	Dim Path As String = AsadiState.Databases.Get(Name)
	If ValidateRegisteredPath(Path) = False Then
		WriteError(resp, 404, "Database is unavailable")
		Return
	End If
	Dim Db As MiniORM
	Try
		Db = OpenMetadataDatabase(Path)
		If TableName <> "" Then
			WriteTablePage(resp, Name, TableName, req, Db)
		Else If ObjectName <> "" Then
			WriteObjectPage(resp, Name, ObjectName, Db)
		Else
			WriteDatabaseOverview(resp, Name, Db)
		End If
		Db.Close
	Catch
		Try
			If Db.IsInitialized Then Db.Close
		Catch
		End Try
		WriteError(resp, 500, "Unable to inspect this database. Check that it is a readable SQLite file.")
	End Try
End Sub

Private Sub WriteSqlWorkspace (resp As ServletResponse, DbName As String, req As ServletRequest)
	Dim Path As String = AsadiState.Databases.Get(DbName)
	If ValidateRegisteredPath(Path) = False Then
		WriteError(resp, 404, "Database is unavailable")
		Return
	End If
	Dim SqlText As String = ""
	Dim Problem As String = ""
	Dim Result As Map
	Dim HasSqlResult As Boolean = False
	Dim IsPost As Boolean = req.Method.EqualsIgnoreCase("POST")
	If IsPost Then
		SqlText = req.GetParameter("sql")
		If SqlText = Null Then SqlText = ""
		SqlText = SqlText.Trim
		If SqlText.Length = 0 Then
			Problem = "Enter a SQL statement to run."
		Else If SqlText.Length > MAX_SQL_LENGTH Then
			Problem = "SQL text is too long. Limit it to " & MAX_SQL_LENGTH & " characters."
		Else
			Problem = ValidateSqlStatement(SqlText)
		End If
		If Problem = "" Then
			Result = RunSqlQuery(Path, SqlText)
			HasSqlResult = True
			If Result.Get("error") <> "" Then Problem = Result.Get("error")
		End If
	End If
	Dim Content As MiniHtml = NewTag(Null, "section", "workspace sql-workspace")
	Dim Back As MiniHtml = AddText(Content, "a", "back", "← Database overview")
	Back.attr("href", AsadiState.BasePath & "/db/" & DbName)
	AddText(Content, "div", "eyebrow", "SQL WORKSPACE")
	AddText(Content, "h1", "", "Run a read-only query")
	AddText(Content, "p", "muted", "Statements run on a read-only connection to " & DbName & ". Results are capped at " & MAX_QUERY_ROWS & " rows and " & MAX_QUERY_COLUMNS & " columns.")
	Dim Form As MiniHtml = NewTag(Content, "form", "sql-form")
	Form.attr("method", "post").attr("action", AsadiState.BasePath & "/db/" & DbName & "/sql")
	Dim Area As MiniHtml = NewTag(Form, "textarea", "sql-input")
	Area.attr("name", "sql").attr("rows", "8").attr("spellcheck", "false").attr("maxlength", "" & MAX_SQL_LENGTH)
	Area.attr("placeholder", "SELECT name, type FROM sqlite_master ORDER BY name LIMIT 50;")
	Area.text(EscapeHtml(SqlText))
	Dim Actions As MiniHtml = NewTag(Form, "div", "sql-actions")
	Dim RunButton As MiniHtml = NewTag(Actions, "button", "btn-primary")
	RunButton.attr("type", "submit").text("Run query")
	AddText(Actions, "span", "sql-hint", "One statement per run. SELECT, WITH, VALUES, EXPLAIN, or PRAGMA only.")
	If IsPost Then
		If Problem = "" Then resp.Status = 200 Else resp.Status = 400
	End If
	If Problem <> "" Then
		Dim ErrorBox As MiniHtml = NewTag(Content, "section", "sql-error")
		AddText(ErrorBox, "strong", "", "Unable to run this statement")
		Dim ErrorText As MiniHtml = NewTag(ErrorBox, "pre", "sql-code")
		ErrorText.text(EscapeHtml(Problem))
	End If
	If HasSqlResult And Problem = "" Then AddSqlResult(Content, Result)
	WritePage(resp, DbName & " · SQL", Content)
End Sub

Private Sub AddSqlResult (Parent As MiniHtml, Result As Map)
	Dim Columns As List = Result.Get("columns")
	Dim Rows As List = Result.Get("rows")
	Dim RowCount As Int = Result.Get("row_count")
	Dim ColumnCount As Int = Result.Get("column_count")
	Dim Elapsed As Long = Result.Get("elapsed")
	Dim Meta As MiniHtml = NewTag(Parent, "div", "sql-meta")
	Dim Summary As String = RowCount & IIf(RowCount = 1, " row", " rows") & " · " & Elapsed & " ms"
	If Result.Get("has_more") Then Summary = Summary & " · showing the first " & MAX_QUERY_ROWS
	AddText(Meta, "span", "", Summary)
	If ColumnCount > MAX_QUERY_COLUMNS Then AddText(Meta, "span", "info-note", "Showing the first " & MAX_QUERY_COLUMNS & " of " & ColumnCount & " columns.")
	If Columns.Size = 0 Then
		AddText(Parent, "p", "info-note", "The statement completed and did not return a result set.")
		Return
	End If
	Dim Grid As MiniHtml = NewTag(Parent, "div", "table-scroll")
	Dim Table As MiniHtml = NewTag(Grid, "table", "data-grid")
	Dim Head As MiniHtml = NewTag(Table, "thead", "")
	Dim HeaderRow As MiniHtml = NewTag(Head, "tr", "")
	For Each Column As Map In Columns
		Dim HeaderCell As MiniHtml = NewTag(HeaderRow, "th", "")
		HeaderCell.text(EscapeHtml(Column.Get("name")))
		Dim TypeName As String = Column.Get("type")
		If TypeName <> "" Then HeaderCell.attr("title", EscapeHtml(TypeName))
	Next
	Dim Body As MiniHtml = NewTag(Table, "tbody", "")
	If Rows.Size = 0 Then
		Dim EmptyRow As MiniHtml = NewTag(Body, "tr", "")
		Dim EmptyCell As MiniHtml = NewTag(EmptyRow, "td", "empty-cell")
		EmptyCell.attr("colspan", "" & Columns.Size)
		AddText(EmptyCell, "span", "", "The query returned no rows.")
	Else
		For Each Values As List In Rows
			Dim Row As MiniHtml = NewTag(Body, "tr", "")
			For Each CellInfo As Map In Values
				Dim Cell As MiniHtml = NewTag(Row, "td", "")
				Dim Kind As String = CellInfo.Get("kind")
				Dim Text As String = CellInfo.Get("text")
				If Kind = "null" Then
					AddText(Cell, "span", "null-value", "NULL")
				Else If Kind = "blob" Then
					AddText(Cell, "span", "blob-value", Text)
				Else
					Dim Display As String = Text
					If Display.Length > MAX_TEXT_LENGTH Then Display = Display.SubString2(0, MAX_TEXT_LENGTH) & "…"
					Dim Style As String = "cell-value"
					If Text.Length > MAX_TEXT_LENGTH Then Style = "large-value"
					Dim ValueCell As MiniHtml = AddText(Cell, "span", Style, Display)
					ValueCell.attr("title", EscapeHtml(Text))
				End If
			Next
		Next
	End If
End Sub

' Runs a single already-validated statement on a fresh read-only connection.
' open_mode=1 asks SQLite for a read-only file handle; statement validation limits
' the allowed starting keywords, and SQLite rejects writes that get past it.
Private Sub RunSqlQuery (Path As String, SqlText As String) As Map
	Dim Result As Map = CreateMap("error": "", "columns": Null, "rows": Null, "elapsed": 0, "has_more": False, "column_count": 0, "row_count": 0)
	Dim Conn As JavaObject
	Dim Stmt As JavaObject
	Dim Rs As JavaObject
	Dim StartTime As Long = DateTime.Now
	Try
		Conn = OpenReadOnlyConnection(Path)
		Stmt = Conn.RunMethodJO("createStatement", Null)
		Dim HasResult As Boolean = Stmt.RunMethod("execute", Array(SqlText))
		Dim Columns As List
		Columns.Initialize
		Dim Rows As List
		Rows.Initialize
		Dim ColumnCount As Int = 0
		Dim HasMore As Boolean = False
		If HasResult Then
			Rs = Stmt.RunMethodJO("getResultSet", Null)
			Dim Meta As JavaObject = Rs.RunMethodJO("getMetaData", Null)
			ColumnCount = Meta.RunMethod("getColumnCount", Null)
			Dim DisplayCount As Int = Min(ColumnCount, MAX_QUERY_COLUMNS)
			For i = 0 To DisplayCount - 1
				Columns.Add(CreateMap("name": SafeString(Meta.RunMethod("getColumnName", Array(i + 1)), ""), _
					"type": TypeLabel(Meta.RunMethod("getColumnType", Array(i + 1)))))
			Next
			Do While Rs.RunMethod("next", Null)
				If Rows.Size >= MAX_QUERY_ROWS Then
					HasMore = True
					Exit
				End If
				Dim Values As List
				Values.Initialize
				For i = 0 To DisplayCount - 1
					Values.Add(ReadSqlValue(Rs, Meta.RunMethod("getColumnType", Array(i + 1)), i + 1))
				Next
				Rows.Add(Values)
			Loop
		End If
		Result.Put("columns", Columns)
		Result.Put("rows", Rows)
		Result.Put("has_more", HasMore)
		Result.Put("column_count", ColumnCount)
		Result.Put("row_count", Rows.Size)
	Catch
		Result.Put("error", SanitizeDbError(LastException.Message, Path))
	End Try
	Result.Put("elapsed", DateTime.Now - StartTime)
	CloseQuietly(Rs)
	CloseQuietly(Stmt)
	CloseQuietly(Conn)
	Return Result
End Sub

Private Sub OpenReadOnlyConnection (Path As String) As JavaObject
	Dim DriverClass As JavaObject
	DriverClass.InitializeStatic("java.lang.Class")
	Try
		DriverClass.RunMethod("forName", Array("org.sqlite.JDBC"))
	Catch
		' The driver is normally registered as a service; the connection attempt reports a clear error otherwise.
	End Try
	Dim Manager As JavaObject
	Manager.InitializeStatic("java.sql.DriverManager")
	Dim Url As String = "jdbc:sqlite:" & Path.Replace("\", "/") & "?open_mode=1"
	Return Manager.RunMethodJO("getConnection", Array(Url))
End Sub

' JDBC reports BLOB as 2004. Reading bytes is the only reliable way to show its size
' because SQLite's getString decodes BLOBs into unreadable text.
Private Sub ReadSqlValue (Rs As JavaObject, TypeId As Int, ColumnIndex As Int) As Map
	If TypeId = 2004 Then
		Dim Bytes() As Byte = Rs.RunMethod("getBytes", Array(ColumnIndex))
		If Bytes = Null Then Return CreateMap("kind": "null", "text": "NULL")
		Return CreateMap("kind": "blob", "text": "BLOB · " & Bytes.Length & " bytes")
	End If
	Dim Value As String = Rs.RunMethod("getString", Array(ColumnIndex))
	If Value = Null Then Return CreateMap("kind": "null", "text": "NULL")
	Dim Stored As String = Value
	If Stored.Length > MAX_SQL_VALUE_LENGTH Then Stored = Stored.SubString2(0, MAX_SQL_VALUE_LENGTH) & "…"
	Return CreateMap("kind": "text", "text": Stored)
End Sub

Private Sub TypeLabel (TypeId As Int) As String
	Select TypeId
		Case 2004: Return "BLOB"
		Case 4, 5, -5, -6: Return "INTEGER"
		Case 6, 7, 8: Return "REAL"
		Case 1, 12, -1, -9, -15, -16: Return "TEXT"
		Case 2, 3: Return "NUMERIC"
		Case 16: Return "BOOLEAN"
	End Select
	Return ""
End Sub

Private Sub CloseQuietly (Target As JavaObject)
	If Target = Null Then Return
	Try
		Target.RunMethod("close", Null)
	Catch
	End Try
End Sub

' Rejects empty input, multiple statements, and anything that is not a read-only statement.
' The scanner ignores separators inside strings, quoted identifiers, and comments.
Private Sub ValidateSqlStatement (SqlText As String) As String
	Dim Scan As Map = ScanSql(SqlText)
	If Scan.Get("started") = False Then Return "Enter a SQL statement to run."
	If Scan.Get("multiple") Then Return "Only one SQL statement can run at a time."
	Dim Keyword As String = Scan.Get("keyword")
	Select Keyword
		Case "SELECT", "WITH", "VALUES", "EXPLAIN", "PRAGMA"
			Return ""
		Case "ATTACH", "DETACH"
			Return "Attaching or detaching databases is not allowed."
	End Select
	Return "Only read-only statements are allowed (SELECT, WITH, VALUES, EXPLAIN, or PRAGMA)."
End Sub

Private Sub ScanSql (SqlText As String) As Map
	Dim Multiple As Boolean = False
	Dim Started As Boolean = False
	Dim Keyword As String = ""
	Dim KeywordDone As Boolean = False
	Dim AfterSemicolon As Boolean = False
	Dim InString As Boolean = False
	Dim InQuotedIdent As Boolean = False
	Dim QuoteEnd As String = ""
	Dim InLineComment As Boolean = False
	Dim InBlockComment As Boolean = False
	Dim i As Int = 0
	Do While i < SqlText.Length
		Dim Ch As String = SqlText.CharAt(i)
		Dim NextCh As String = ""
		If i + 1 < SqlText.Length Then NextCh = SqlText.CharAt(i + 1)
		If InLineComment Then
			If Ch = Chr(10) Or Ch = Chr(13) Then InLineComment = False
		Else If InBlockComment Then
			If Ch = "*" And NextCh = "/" Then
				InBlockComment = False
				i = i + 1
			End If
		Else If InString Then
			If Ch = "'" Then
				If NextCh = "'" Then
					i = i + 1
				Else
					InString = False
				End If
			End If
		Else If InQuotedIdent Then
			If Ch = QuoteEnd Then
				If NextCh = QuoteEnd And QuoteEnd <> "]" Then
					i = i + 1
				Else
					InQuotedIdent = False
				End If
			End If
		Else
			If Ch = "-" And NextCh = "-" Then
				If Keyword <> "" Then KeywordDone = True
				InLineComment = True
				i = i + 1
			Else If Ch = "/" And NextCh = "*" Then
				If Keyword <> "" Then KeywordDone = True
				InBlockComment = True
				i = i + 1
			Else If Ch = ";" Then
				If Keyword <> "" Then KeywordDone = True
				AfterSemicolon = True
			Else If IsSqlSpace(Ch) Then
				If Keyword <> "" Then KeywordDone = True
			Else
				If Ch = "'" Then
					If Keyword <> "" Then KeywordDone = True
					InString = True
					If AfterSemicolon Then Multiple = True
				Else If Ch = Chr(34) Or Ch = "`" Or Ch = "[" Then
					If Keyword <> "" Then KeywordDone = True
					InQuotedIdent = True
					QuoteEnd = Ch
					If Ch = "[" Then QuoteEnd = "]"
					If AfterSemicolon Then Multiple = True
				Else
					If Started = False Then
						Started = True
						If IsSqlIdentChar(Ch) Then
							Keyword = Ch
						Else
							KeywordDone = True
						End If
					Else If KeywordDone = False Then
						If Keyword <> "" And IsSqlIdentChar(Ch) Then
							Keyword = Keyword & Ch
						Else
							KeywordDone = True
						End If
					End If
					If AfterSemicolon Then Multiple = True
				End If
			End If
		End If
		i = i + 1
	Loop
	Return CreateMap("started": Started, "multiple": Multiple, "keyword": Keyword.ToUpperCase)
End Sub

Private Sub IsSqlSpace (Ch As String) As Boolean
	Return Ch = " " Or Ch = Chr(9) Or Ch = Chr(10) Or Ch = Chr(13)
End Sub

Private Sub IsSqlIdentChar (Ch As String) As Boolean
	Dim Code As Int = Asc(Ch)
	Return (Code >= 65 And Code <= 90) Or (Code >= 97 And Code <= 122) Or (Code >= 48 And Code <= 57) Or Code = 95
End Sub

Private Sub SanitizeDbError (Message As Object, Path As String) As String
	Dim Clean As String = SafeString(Message, "The database rejected this statement.")
	Dim Marker As Int = Clean.IndexOf("[SQLITE")
	If Marker > 0 Then Clean = Clean.SubString(Marker)
	Dim Prefix As String = "java.sql.SQLException: "
	If Clean.StartsWith(Prefix) Then Clean = Clean.SubString(Prefix.Length)
	Clean = Clean.Replace(Path, "[database]").Replace(Path.Replace("\", "/"), "[database]")
	If Clean.Length > 500 Then Clean = Clean.SubString2(0, 500) & "…"
	Return Clean
End Sub

Private Sub WriteDatabaseOverview (resp As ServletResponse, Name As String, Db As MiniORM)
	Dim Sql As SQL = Db.SQL
	Dim Objects As ResultSet = Sql.ExecQuery("SELECT type, name FROM sqlite_master WHERE type IN ('table','view','index','trigger') AND name NOT LIKE 'sqlite_%' ORDER BY CASE type WHEN 'table' THEN 1 WHEN 'view' THEN 2 WHEN 'index' THEN 3 ELSE 4 END, name LIMIT 501")
	Dim SchemaObjects As List
	SchemaObjects.Initialize
	Dim Tables As Int
	Dim Views As Int
	Dim Indexes As Int
	Dim Triggers As Int
	Do While Objects.NextRow
		Dim Info As Map = CreateMap("type": Objects.GetString("type"), "name": Objects.GetString("name"))
		SchemaObjects.Add(Info)
		Select Info.Get("type")
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
	AddText(Content, "p", "muted", "Tables, views, indexes and triggers. Select a table or view to inspect its schema and browse rows.")
	Dim Actions As MiniHtml = NewTag(Content, "div", "page-actions")
	Dim SqlLink As MiniHtml = NewTag(Actions, "a", "action-link")
	SqlLink.attr("href", AsadiState.BasePath & "/db/" & Name & "/sql").text("SQL workspace →")
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
			Dim Info As Map = SchemaObjects.Get(i)
			Dim ObjectName As String = Info.Get("name")
			Dim ObjectType As String = Info.Get("type")
			Dim Row As MiniHtml = NewTag(Rows, "div", "object-row")
			AddText(Row, "span", "object-symbol", TypeIcon(ObjectType))
			Dim Link As MiniHtml = NewTag(Row, "a", "object-title")
			If ObjectType = "table" Or ObjectType = "view" Then
				Link.attr("href", EscapeHtml(TableUrl(Name, ObjectName, 1, "", "ASC", "")))
			Else
				Link.attr("href", EscapeHtml(ObjectUrl(Name, ObjectName)))
			End If
			Link.text(EscapeHtml(ObjectName))
			AddText(Row, "span", "object-type", ObjectType)
		Next
		If SchemaObjects.Size > MAX_OBJECTS Then AddText(ObjectList, "p", "muted note", "Showing the first 500 objects.")
	End If
	WritePage(resp, Name, Content)
End Sub

Private Sub WriteObjectPage (resp As ServletResponse, DbName As String, ObjectName As String, Db As MiniORM)
	Dim Sql As SQL = Db.SQL
	Dim Cur As ResultSet = Sql.ExecQuery2("SELECT type, sql FROM sqlite_master WHERE name = ? AND type IN ('index','trigger') AND name NOT LIKE 'sqlite_%'", Array As String(ObjectName))
	If Cur.NextRow = False Then
		Cur.Close
		WriteError(resp, 404, "Schema object not found")
		Return
	End If
	Dim ObjectType As String = Cur.GetString("type")
	Dim Definition As String = Cur.GetString("sql")
	Cur.Close
	Dim Content As MiniHtml = NewTag(Null, "section", "workspace")
	Dim Back As MiniHtml = AddText(Content, "a", "back", "← Database overview")
	Back.attr("href", AsadiState.BasePath & "/db/" & DbName)
	AddText(Content, "div", "eyebrow", ObjectType.ToUpperCase)
	AddText(Content, "h1", "", ObjectName)
	Dim DefinitionSection As MiniHtml = NewTag(Content, "section", "objects sql-definition")
	If Definition = Null Or Definition = "" Then
		AddText(DefinitionSection, "p", "muted", "SQLite does not retain a SQL definition for this object.")
	Else
		AddText(DefinitionSection, "pre", "sql-code", Definition)
	End If
	WritePage(resp, ObjectName, Content)
End Sub

Private Sub WriteTablePage (resp As ServletResponse, DbName As String, TableName As String, req As ServletRequest, Db As MiniORM)
	Dim Sql As SQL = Db.SQL
	Dim Check As ResultSet = Sql.ExecQuery2("SELECT type FROM sqlite_master WHERE name = ? AND type IN ('table','view') AND name NOT LIKE 'sqlite_%'", Array As String(TableName))
	If Check.NextRow = False Then
		Check.Close
		WriteError(resp, 404, "Table or view not found")
		Return
	End If
	Dim IsView As Boolean = Check.GetString("type") = "view"
	Check.Close
	Dim Columns As List = ReadColumns(Sql, TableName)
	If Columns.Size = 0 Then
		WriteError(resp, 422, "No columns are available for this table or view")
		Return
	End If
	Dim ForeignKeys As List = ReadForeignKeys(Sql, TableName, IsView)
	Dim Indexes As List = ReadIndexes(Sql, TableName, IsView)
	Dim Definition As String = ReadDefinition(Sql, TableName, IsView)
	Dim SearchText As String = req.GetParameter("q")
	If SearchText = Null Then SearchText = ""
	If SearchText.Length > MAX_SEARCH_LENGTH Then
		WriteError(resp, 400, "Search text is too long")
		Return
	End If
	Dim Page As Int = ParsePage(req.GetParameter("page"))
	If Page = 0 Then
		WriteError(resp, 400, "Invalid page number")
		Return
	End If
	Dim SortColumn As String = req.GetParameter("sort")
	If SortColumn = Null Then SortColumn = ""
	Dim SortDirection As String = req.GetParameter("dir")
	If SortDirection = Null Or SortDirection = "" Then SortDirection = "ASC"
	SortDirection = SortDirection.ToUpperCase
	If SortDirection <> "ASC" And SortDirection <> "DESC" Then
		WriteError(resp, 400, "Invalid sort direction")
		Return
	End If
	Dim PrimaryKeys As List = PrimaryKeyColumns(Columns)
	If SortColumn = "" Then
		If PrimaryKeys.Size > 0 Then
			SortColumn = PrimaryKeys.Get(0)
		Else
			Dim FirstColumn As Map = Columns.Get(0)
			SortColumn = FirstColumn.Get("name")
		End If
	Else If FindColumn(Columns, SortColumn) = -1 Then
		WriteError(resp, 400, "Invalid sort column")
		Return
	End If
	Dim DataColumns As List
	DataColumns.Initialize
	For Each Column As Map In Columns
		If DataColumns.Size < MAX_DATA_COLUMNS Then DataColumns.Add(Column)
	Next
	Dim SearchColumns As List = SearchableColumns(DataColumns)
	If SearchText <> "" And SearchColumns.Size = 0 Then
		WriteError(resp, 400, "No searchable columns are available")
		Return
	End If
	Dim Query As String = BuildPageQuery(TableName, DataColumns, SearchColumns, PrimaryKeys, SearchText, SortColumn, SortDirection, Page)
	Dim Args As List = SearchArguments(SearchColumns, SearchText)
	Dim Rows As ResultSet
	If Args.Size = 0 Then
		Rows = Sql.ExecQuery(Query)
	Else
		Rows = Sql.ExecQuery2(Query, Args)
	End If
	Dim Content As MiniHtml = NewTag(Null, "section", "workspace table-workspace")
	Dim Back As MiniHtml = AddText(Content, "a", "back", "← Database overview")
	Back.attr("href", AsadiState.BasePath & "/db/" & DbName)
	AddText(Content, "div", "eyebrow", IIf(IsView, "VIEW DATA", "TABLE DATA"))
	AddText(Content, "h1", "", TableName)
	AddText(Content, "p", "muted", "Read-only browser · Page " & Page)
	If IsView Then AddText(Content, "p", "info-note", "This object is a view; its displayed rows are read-only.")
	If PrimaryKeys.Size = 0 Then AddText(Content, "p", "info-note", "No primary key is defined. Rows are browse-only and ordered by the selected column.")
	If Columns.Size > MAX_DATA_COLUMNS Then AddText(Content, "p", "info-note", "Showing the first " & MAX_DATA_COLUMNS & " of " & Columns.Size & " columns in the data grid.")
	If Columns.Size > MAX_SEARCH_COLUMNS Then AddText(Content, "p", "info-note", "Search checks at most the first " & MAX_SEARCH_COLUMNS & " non-BLOB columns.")
	AddSchemaSection(Content, TableName, Columns, ForeignKeys, Indexes, Definition, IsView)
	AddSearchForm(Content, DbName, TableName, SearchText)
	Dim Grid As MiniHtml = NewTag(Content, "div", "table-scroll")
	Dim DataGrid As MiniHtml = NewTag(Grid, "table", "data-grid")
	Dim Head As MiniHtml = NewTag(DataGrid, "thead", "")
	Dim HeaderRow As MiniHtml = NewTag(Head, "tr", "")
	For Each Column As Map In DataColumns
		Dim ColumnName As String = Column.Get("name")
		Dim NextDirection As String = IIf(SortColumn = ColumnName And SortDirection = "ASC", "DESC", "ASC")
		Dim HeaderCell As MiniHtml = NewTag(HeaderRow, "th", "")
		Dim HeaderLink As MiniHtml = NewTag(HeaderCell, "a", "sort-link")
		HeaderLink.attr("href", EscapeHtml(TableUrl(DbName, TableName, 1, ColumnName, NextDirection, SearchText)))
		HeaderLink.text(EscapeHtml(ColumnName))
		If SortColumn = ColumnName Then AddText(HeaderCell, "span", "sort-state", IIf(SortDirection = "ASC", " ↑", " ↓"))
	Next
	Dim Body As MiniHtml = NewTag(DataGrid, "tbody", "")
	Dim RowsShown As Int
	Dim HasMore As Boolean
	Do While Rows.NextRow
		If RowsShown >= PAGE_SIZE Then
			HasMore = True
			Exit
		End If
		Dim Row As MiniHtml = NewTag(Body, "tr", "")
		For i = 0 To DataColumns.Size - 1
			Dim Cell As MiniHtml = NewTag(Row, "td", "")
			Dim StorageType As String = Rows.GetString2(DataColumns.Size + i)
			If StorageType = "null" Then
				AddText(Cell, "span", "null-value", "NULL")
			Else If StorageType = "blob" Then
				Dim BlobLength As Long = Rows.GetLong2(DataColumns.Size * 2 + i)
				AddText(Cell, "span", "blob-value", "BLOB · " & BlobLength & " bytes")
			Else
				Dim Value As String = Rows.GetString2(i)
				If Value = Null Then
					AddText(Cell, "span", "null-value", "NULL")
				Else If Value.Length > MAX_TEXT_LENGTH Then
					Dim Large As MiniHtml = AddText(Cell, "span", "large-value", Value.SubString2(0, MAX_TEXT_LENGTH) & "…")
					Large.attr("title", EscapeHtml(Value))
				Else
					Dim Normal As MiniHtml = AddText(Cell, "span", "cell-value", Value)
					Normal.attr("title", EscapeHtml(Value))
				End If
			End If
		Next
		RowsShown = RowsShown + 1
	Loop
	Rows.Close
	If RowsShown = 0 Then
		Dim EmptyRow As MiniHtml = NewTag(Body, "tr", "")
		Dim EmptyCell As MiniHtml = NewTag(EmptyRow, "td", "empty-cell")
		EmptyCell.attr("colspan", "" & DataColumns.Size)
		AddText(EmptyCell, "span", "", IIf(SearchText = "", "This table has no rows on this page.", "No rows match this search."))
	End If
	Dim Pagination As MiniHtml = NewTag(Content, "nav", "pagination")
	If Page > 1 Then
		Dim Previous As MiniHtml = NewTag(Pagination, "a", "page-link")
		Previous.attr("href", EscapeHtml(TableUrl(DbName, TableName, Page - 1, SortColumn, SortDirection, SearchText)))
		Previous.text("← Previous")
	End If
	Dim RowLabel As String = " rows shown"
	If RowsShown = 1 Then RowLabel = " row shown"
	AddText(Pagination, "span", "page-state", "Page " & Page & " · " & RowsShown & IIf(HasMore, "+", "") & RowLabel)
	If HasMore Then
		Dim NextPage As MiniHtml = NewTag(Pagination, "a", "page-link")
		NextPage.attr("href", EscapeHtml(TableUrl(DbName, TableName, Page + 1, SortColumn, SortDirection, SearchText)))
		NextPage.text("Next →")
	End If
	WritePage(resp, TableName, Content)
End Sub

Private Sub ReadColumns (Sql As SQL, TableName As String) As List
	Dim Columns As List
	Columns.Initialize
	Dim Cur As ResultSet = Sql.ExecQuery("PRAGMA table_info(" & QuoteIdentifier(TableName) & ")")
	Do While Cur.NextRow
		Dim ColumnInfo As Map = CreateMap("name": Cur.GetString("name"), "type": Cur.GetString("type"), _
			"notnull": Cur.GetInt("notnull"), "pk": Cur.GetInt("pk"), "default": Cur.GetString("dflt_value"))
		Columns.Add(ColumnInfo)
	Loop
	Cur.Close
	Return Columns
End Sub

Private Sub ReadForeignKeys (Sql As SQL, TableName As String, IsView As Boolean) As List
	Dim Keys As List
	Keys.Initialize
	If IsView Then Return Keys
	Dim Cur As ResultSet = Sql.ExecQuery("PRAGMA foreign_key_list(" & QuoteIdentifier(TableName) & ")")
	Do While Cur.NextRow
		Keys.Add(CreateMap("from": Cur.GetString("from"), "table": Cur.GetString("table"), "to": Cur.GetString("to"), _
			"on_update": Cur.GetString("on_update"), "on_delete": Cur.GetString("on_delete")))
	Loop
	Cur.Close
	Return Keys
End Sub

Private Sub ReadIndexes (Sql As SQL, TableName As String, IsView As Boolean) As List
	Dim Indexes As List
	Indexes.Initialize
	If IsView Then Return Indexes
	Dim Cur As ResultSet = Sql.ExecQuery("PRAGMA index_list(" & QuoteIdentifier(TableName) & ")")
	Do While Cur.NextRow
		Indexes.Add(CreateMap("name": Cur.GetString("name"), "unique": Cur.GetInt("unique"), "origin": Cur.GetString("origin")))
	Loop
	Cur.Close
	Return Indexes
End Sub

Private Sub ReadDefinition (Sql As SQL, TableName As String, IsView As Boolean) As String
	Dim ObjectType As String = "table"
	If IsView Then ObjectType = "view"
	Dim Cur As ResultSet = Sql.ExecQuery2("SELECT sql FROM sqlite_master WHERE type = ? AND name = ?", Array As String(ObjectType, TableName))
	If Cur.NextRow = False Then
		Cur.Close
		Return ""
	End If
	Dim Definition As String = Cur.GetString("sql")
	Cur.Close
	Return Definition
End Sub

Private Sub PrimaryKeyColumns (Columns As List) As List
	Dim Primary As List
	Primary.Initialize
	Dim MaxKey As Int
	For Each Column As Map In Columns
		MaxKey = Max(MaxKey, Column.Get("pk"))
	Next
	For KeyNumber = 1 To MaxKey
		For Each Column As Map In Columns
			If Column.Get("pk") = KeyNumber Then Primary.Add(Column.Get("name"))
		Next
	Next
	Return Primary
End Sub

Private Sub FindColumn (Columns As List, ColumnName As String) As Int
	For i = 0 To Columns.Size - 1
		Dim Column As Map = Columns.Get(i)
		If Column.Get("name") = ColumnName Then Return i
	Next
	Return -1
End Sub

Private Sub SearchableColumns (Columns As List) As List
	Dim Searchable As List
	Searchable.Initialize
	For Each Column As Map In Columns
		Dim DeclaredType As String = Column.Get("type")
		If DeclaredType = Null Then DeclaredType = ""
		If DeclaredType.ToUpperCase.Contains("BLOB") = False And Searchable.Size < MAX_SEARCH_COLUMNS Then Searchable.Add(Column)
	Next
	Return Searchable
End Sub


Private Sub BuildPageQuery (TableName As String, DataColumns As List, SearchColumns As List, PrimaryKeys As List, SearchText As String, _
		SortColumn As String, SortDirection As String, Page As Int) As String
	Dim Query As StringBuilder
	Query.Initialize
	Query.Append("SELECT ")
	For Each Column As Map In DataColumns
		If Query.ToString.EndsWith("SELECT ") = False Then Query.Append(", ")
		Dim Ident As String = QuoteIdentifier(Column.Get("name"))
		Query.Append("CASE WHEN typeof(").Append(Ident).Append(") = 'blob' THEN NULL ELSE CASE WHEN length(CAST(").Append(Ident)
		Query.Append(" AS TEXT)) > ").Append(MAX_TEXT_LENGTH + 1).Append(" THEN substr(CAST(").Append(Ident).Append(" AS TEXT), 1, ")
		Query.Append(MAX_TEXT_LENGTH + 1).Append(") ELSE CAST(").Append(Ident).Append(" AS TEXT) END END")
	Next
	For Each Column As Map In DataColumns
		Query.Append(", typeof(").Append(QuoteIdentifier(Column.Get("name"))).Append(")")
	Next
	For Each Column As Map In DataColumns
		Dim Ident As String = QuoteIdentifier(Column.Get("name"))
		Query.Append(", CASE WHEN typeof(").Append(Ident).Append(") = 'blob' THEN length(").Append(Ident).Append(") ELSE 0 END")
	Next
	Query.Append(" FROM ").Append(QuoteIdentifier(TableName))
	If SearchText <> "" Then
		Query.Append(" WHERE ")
		For i = 0 To SearchColumns.Size - 1
			If i > 0 Then Query.Append(" OR ")
			Dim SearchColumn As Map = SearchColumns.Get(i)
			Dim Ident As String = QuoteIdentifier(SearchColumn.Get("name"))
			Query.Append("(typeof(").Append(Ident).Append(") <> 'blob' AND CAST(").Append(Ident).Append(" AS TEXT) LIKE ? ESCAPE '\')")
		Next
	End If
	Query.Append(" ORDER BY ").Append(QuoteIdentifier(SortColumn)).Append(" ").Append(SortDirection)
	For Each PrimaryKey As String In PrimaryKeys
		If PrimaryKey <> SortColumn Then Query.Append(", ").Append(QuoteIdentifier(PrimaryKey)).Append(" ASC")
	Next
	Query.Append(" LIMIT ").Append(PAGE_SIZE + 1).Append(" OFFSET ").Append((Page - 1) * PAGE_SIZE)
	Return Query.ToString
End Sub

Private Sub SearchArguments (SearchColumns As List, SearchText As String) As List
	Dim Args As List
	Args.Initialize
	If SearchText = "" Then Return Args
	Dim Pattern As String = "%" & EscapeLike(SearchText) & "%"
	For i = 0 To SearchColumns.Size - 1
		Args.Add(Pattern)
	Next
	Return Args
End Sub

Private Sub EscapeLike (Value As String) As String
	Return Value.Replace("\", "\\").Replace("%", "\%").Replace("_", "\_")
End Sub

Private Sub QuoteIdentifier (Identifier As String) As String
	Dim QuoteChar As String = Chr(34)
	Return QuoteChar & Identifier.Replace(QuoteChar, QuoteChar & QuoteChar) & QuoteChar
End Sub

Private Sub ParsePage (Value As String) As Int
	If Value = Null Or Value = "" Then Return 1
	If Regex.IsMatch("^[1-9][0-9]{0,5}$", Value) = False Then Return 0
	Dim Page As Int = Value
	If Page > 100000 Then Return 0
	Return Page
End Sub

Private Sub TableUrl (DbName As String, TableName As String, Page As Int, SortColumn As String, SortDirection As String, SearchText As String) As String
	Dim Url As String = AsadiState.BasePath & "/db/" & DbName & "?table=" & EncodeQuery(TableName) & "&page=" & Page
	If SortColumn <> "" Then Url = Url & "&sort=" & EncodeQuery(SortColumn) & "&dir=" & SortDirection
	If SearchText <> "" Then Url = Url & "&q=" & EncodeQuery(SearchText)
	Return Url
End Sub

Private Sub ObjectUrl (DbName As String, ObjectName As String) As String
	Return AsadiState.BasePath & "/db/" & DbName & "?object=" & EncodeQuery(ObjectName)
End Sub

Private Sub EncodeQuery (Value As String) As String
	Dim Encoder As JavaObject
	Encoder.InitializeStatic("java.net.URLEncoder")
	Dim Encoded As String = Encoder.RunMethod("encode", Array(Value, "UTF-8"))
	Return Encoded.Replace("+", "%20")
End Sub

Private Sub AddSchemaSection (Parent As MiniHtml, TableName As String, Columns As List, ForeignKeys As List, Indexes As List, Definition As String, IsView As Boolean)
	Dim Section As MiniHtml = NewTag(Parent, "details", "objects schema-section")
	Dim Summary As MiniHtml = NewTag(Section, "summary", "section-head")
	Summary.text("Structure · " & Columns.Size & " columns")
	Dim Scroll As MiniHtml = NewTag(Section, "div", "table-scroll")
	Dim Table As MiniHtml = NewTag(Scroll, "table", "schema-grid")
	Dim Head As MiniHtml = NewTag(Table, "thead", "")
	Dim Header As MiniHtml = NewTag(Head, "tr", "")
	For Each Label As String In Array As String("Column", "Type", "Nullable", "Key", "Default", "Reference")
		AddText(Header, "th", "", Label)
	Next
	Dim Body As MiniHtml = NewTag(Table, "tbody", "")
	For Each Column As Map In Columns
		Dim Row As MiniHtml = NewTag(Body, "tr", "")
		Dim Name As String = Column.Get("name")
		Dim ColumnType As String = Column.Get("type")
		If ColumnType = Null Or ColumnType = "" Then ColumnType = "(untyped)"
		Dim Nullable As String = "YES"
		If Column.Get("notnull") = 1 Then Nullable = "NO"
		Dim KeyLabel As String = ""
		If Column.Get("pk") > 0 Then KeyLabel = "PK " & Column.Get("pk")
		AddText(Row, "td", "", Name)
		AddText(Row, "td", "", ColumnType)
		AddText(Row, "td", "", Nullable)
		AddText(Row, "td", "", KeyLabel)
		AddText(Row, "td", "", SafeString(Column.Get("default"), "—"))
		AddText(Row, "td", "", ForeignReference(ForeignKeys, Name))
	Next
	If Indexes.Size > 0 Then
		Dim IndexSection As MiniHtml = NewTag(Section, "div", "schema-subsection")
		AddText(IndexSection, "h3", "", "Indexes")
		For Each Index As Map In Indexes
			Dim UniqueLabel As String = ""
			If Index.Get("unique") = 1 Then UniqueLabel = " · unique"
			AddText(IndexSection, "div", "schema-detail", Index.Get("name") & UniqueLabel & " · " & IndexOrigin(Index.Get("origin")))
		Next
	End If
	Dim DefinitionSection As MiniHtml = NewTag(Section, "details", "schema-subsection")
	Dim DefinitionSummary As MiniHtml = NewTag(DefinitionSection, "summary", "")
	DefinitionSummary.text("SQL definition")
	If Definition = Null Or Definition = "" Then
		AddText(DefinitionSection, "p", "muted", "SQLite does not retain a SQL definition for this object.")
	Else
		AddText(DefinitionSection, "pre", "sql-code", Definition)
	End If
End Sub

Private Sub ForeignReference (ForeignKeys As List, ColumnName As String) As String
	For Each Foreign As Map In ForeignKeys
		If Foreign.Get("from") = ColumnName Then
			Return Foreign.Get("table") & "." & Foreign.Get("to")
		End If
	Next
	Return ""
End Sub

Private Sub IndexOrigin (Origin As Object) As String
	Dim Value As String = SafeString(Origin, "")
	Select Value
		Case "c"
			Return "created with CREATE INDEX"
		Case "u"
			Return "UNIQUE constraint"
		Case "pk"
			Return "PRIMARY KEY constraint"
	End Select
	Return "unknown origin"
End Sub

Private Sub SafeString (Value As Object, Fallback As String) As String
	If Value = Null Then Return Fallback
	Return Value
End Sub

Private Sub AddSearchForm (Parent As MiniHtml, DbName As String, TableName As String, SearchText As String)
	Dim Form As MiniHtml = NewTag(Parent, "form", "table-search")
	Form.attr("method", "get").attr("action", AsadiState.BasePath & "/db/" & DbName)
	Dim TableInput As MiniHtml = NewTag(Form, "input", "")
	TableInput.attr("type", "hidden").attr("name", "table").attr("value", EscapeHtml(TableName))
	Dim SearchInput As MiniHtml = NewTag(Form, "input", "search-input")
	SearchInput.attr("type", "search").attr("name", "q").attr("maxlength", "200").attr("value", EscapeHtml(SearchText)).attr("placeholder", "Search visible columns")
	Dim Button As MiniHtml = NewTag(Form, "button", "btn-search")
	Button.attr("type", "submit").text("Search")
	If SearchText <> "" Then
		Dim Clear As MiniHtml = NewTag(Form, "a", "clear-search")
		Clear.attr("href", EscapeHtml(TableUrl(DbName, TableName, 1, "", "ASC", ""))).text("Clear")
	End If
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
	Style.text(GetTableStyles, False)
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
	Readonly.text("♙ &nbsp; Read-only workspace")
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

Private Sub GetTableStyles As String
	Return ".table-search{display:flex;gap:8px;margin:20px 0}.search-input{flex:1;min-width:130px;border:1px solid var(--line);border-radius:8px;padding:10px 12px;background:var(--surface);color:var(--ink)}.btn-search,.page-link{border:1px solid var(--line);border-radius:8px;background:var(--surface);color:var(--ink);padding:9px 13px;text-decoration:none;cursor:pointer}.clear-search{padding:10px;color:var(--blue)}.table-scroll{overflow:auto;max-width:100%;background:var(--surface);border:1px solid var(--line);border-radius:12px}.table-workspace>.table-scroll{max-height:68vh}.data-grid,.schema-grid{border-collapse:separate;border-spacing:0;width:100%;white-space:nowrap}.object-title{color:var(--ink);text-decoration:none}.object-title:hover,.object-title:focus{color:var(--blue);text-decoration:underline}.data-grid th,.schema-grid th{position:sticky;top:0;background:#f1f4f8;text-align:left;font-size:11px;color:#62718a;padding:11px 13px;border-bottom:1px solid var(--line);z-index:1}.data-grid td,.schema-grid td{padding:10px 13px;border-bottom:1px solid #edf0f4;white-space:nowrap}.data-grid tr:last-child td,.schema-grid tr:last-child td{border-bottom:0}.sort-link{color:inherit;text-decoration:none}.sort-link:hover,.sort-link:focus,.page-link:hover,.page-link:focus{color:var(--blue);outline:2px solid #aabaff;outline-offset:2px}.sort-state{color:var(--blue);font-size:10px}.null-value,.blob-value{display:inline-block;border-radius:5px;background:#f0f3f8;color:#718098;padding:3px 6px;font-size:10px}.cell-value,.large-value{display:inline-block;max-width:280px;overflow:hidden;text-overflow:ellipsis;vertical-align:bottom}.pagination{display:flex;gap:12px;align-items:center;justify-content:flex-end;margin:14px 0}.page-state,.info-note{font-size:12px;color:var(--muted)}.schema-section{margin:18px 0;background:var(--surface);border:1px solid var(--line);border-radius:12px}.schema-section>summary,.schema-subsection>summary{cursor:pointer;padding:14px 18px;color:var(--ink)}.schema-grid{font-size:12px}.schema-subsection{padding:12px 18px;border-top:1px solid var(--line)}.schema-subsection h3{font-size:13px}.schema-detail{padding:5px 0;color:var(--muted)}.sql-code{white-space:pre-wrap;overflow-wrap:anywhere;background:#f4f6fa;padding:14px;border-radius:8px;color:#34435a}.empty-cell{text-align:center!important;color:var(--muted);padding:30px!important}@media(max-width:600px){.table-search{flex-wrap:wrap}.pagination{justify-content:center}.data-grid td,.data-grid th{padding:8px}.schema-section{overflow:hidden}}@media(prefers-color-scheme:dark){.data-grid th,.schema-grid th,.null-value,.blob-value{background:#202d42;color:#a9b8d1}.data-grid td,.schema-grid td{border-color:#243147}.sql-code{background:#101827;color:#d1d9e6}.search-input,.btn-search,.page-link{background:var(--surface);color:var(--ink)}}.page-actions{margin:16px 0 0}.action-link{display:inline-block;background:var(--blue);color:#fff;text-decoration:none;font-weight:600;border-radius:8px;padding:9px 14px}.action-link:hover,.action-link:focus{background:#3350d6;outline:2px solid #aabaff;outline-offset:2px}.sql-form{margin:22px 0}.sql-input{width:100%;min-height:170px;padding:14px 16px;border:1px solid var(--line);border-radius:10px;background:var(--surface);color:var(--ink);font:13px/1.55 ui-monospace,SFMono-Regular,Consolas,monospace;resize:vertical}.sql-actions{display:flex;align-items:center;gap:14px;margin-top:10px;flex-wrap:wrap}.btn-primary{border:0;border-radius:8px;background:var(--blue);color:#fff;padding:10px 16px;font-weight:600;cursor:pointer}.btn-primary:hover,.btn-primary:focus{background:#3350d6;outline:2px solid #aabaff;outline-offset:2px}.sql-hint,.sql-meta{font-size:12px;color:var(--muted)}.sql-meta{display:flex;gap:14px;align-items:center;flex-wrap:wrap;margin:18px 0 8px}.sql-error{margin:18px 0;padding:16px 18px;border:1px solid #e3a3a3;border-left:4px solid #d64545;background:var(--surface);border-radius:10px}.sql-error strong{display:block;margin-bottom:8px;color:#d64545}.sql-error .sql-code{margin:0;white-space:pre-wrap;word-break:break-word}.sql-workspace>.table-scroll{max-height:60vh}"
End Sub
