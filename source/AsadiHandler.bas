B4J=true
Group=Handlers
ModulesStructureVersion=1
Type=Class
Version=10.7
@EndOfDesignText@
' Read/write dashboard handler. Every request is gated independently.
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
	Private Const MAX_EDIT_VALUE As Int = 100000
	Private Const MAX_EXPORT_ROWS As Int = 10000
	Private Const MAX_EXPORT_COLUMNS As Int = 200
	Private Const CSRF_COOKIE As String = "asadi_csrf"
	Private Const CSRF_MAX_AGE As Int = 28800
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
	If SubExists(AsadiState.HostModule, AsadiState.AuthorizationSub) = False Then
		WriteError(resp, 403, "Administration access is not configured")
		Return
	End If
	Dim Authorized As Boolean = False
	Try
		Dim GateResult As Object = CallSub2(AsadiState.HostModule, AsadiState.AuthorizationSub, req)
		If GateResult Is Boolean Then Authorized = GateResult
	Catch
		Authorized = False
		Log("Pakai Asadi: authorization check failed: " & LastException.Message)
	End Try
	If Authorized = False Then
		WriteError(resp, 403, "You are not authorized to administer databases")
		Return
	End If
	Dim CsrfToken As String = EnsureCsrfToken(req, resp)
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
		If Method = "POST" And (IsSameOriginPost(req) = False Or IsValidCsrf(req) = False) Then
			WriteError(resp, 403, "This form submission could not be verified. Reload the page and try again.")
			Return
		End If
		WriteSqlWorkspace(resp, DbName, req, CsrfToken)
		Return
	End If
	If SubRoute = "edit" Then
		If Method <> "GET" And Method <> "POST" Then
			MethodNotAllowed(resp, "GET, POST")
			Return
		End If
		If Method = "POST" And (IsSameOriginPost(req) = False Or IsValidCsrf(req) = False) Then
			WriteError(resp, 403, "This form submission could not be verified. Reload the page and try again.")
			Return
		End If
		WriteEditPage(resp, DbName, Method, req, CsrfToken)
		Return
	End If
	If SubRoute = "export" Then
		If Method <> "GET" Then
			MethodNotAllowed(resp, "GET")
			Return
		End If
		WriteExport(resp, DbName, req)
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

' Double-submit token: the value is stored in an HttpOnly SameSite cookie and repeated
' in the form. It is HMAC-signed with a per-process key so a subdomain cannot inject an
' arbitrary cookie value. Both the cookie and the submitted field must match.
Private Sub EnsureCsrfToken (req As ServletRequest, resp As ServletResponse) As String
	Dim Token As String = ReadCsrfCookie(req)
	If Token = "" Or VerifyCsrfToken(Token) = False Then Token = CreateCsrfToken
	Dim Cookie As String = CSRF_COOKIE & "=" & Token & "; Path=" & AsadiState.BasePath & _
		"; Max-Age=" & CSRF_MAX_AGE & "; HttpOnly; SameSite=Strict"
	If req.Secure Then Cookie = Cookie & "; Secure"
	resp.SetHeader("Set-Cookie", Cookie)
	Return Token
End Sub

Private Sub IsValidCsrf (req As ServletRequest) As Boolean
	Dim CookieValue As String = ReadCsrfCookie(req)
	Dim Submitted As String = req.GetParameter("csrf")
	If CookieValue = "" Or Submitted = Null Or Submitted = "" Then Return False
	If CookieValue <> Submitted Then Return False
	Return VerifyCsrfToken(Submitted)
End Sub

Private Sub ReadCsrfCookie (req As ServletRequest) As String
	Dim Header As String = req.GetHeader("Cookie")
	If Header = Null Or Header = "" Then Return ""
	For Each Part As String In Regex.Split(";", Header)
		Dim Pair As String = Part.Trim
		If Pair.StartsWith(CSRF_COOKIE & "=") Then Return Pair.SubString(CSRF_COOKIE.Length + 1)
	Next
	Return ""
End Sub

Private Sub CreateCsrfToken As String
	Dim Nonce As String = RandomBase64Url(16)
	Return Nonce & "." & SignNonce(Nonce)
End Sub

Private Sub VerifyCsrfToken (Token As String) As Boolean
	Dim Dot As Int = Token.IndexOf(".")
	If Dot <= 0 Or Dot >= Token.Length - 1 Then Return False
	Dim Nonce As String = Token.SubString2(0, Dot)
	Dim ProvidedText As String = Token.SubString(Dot + 1)
	Dim Provided() As Byte = Base64UrlDecode(ProvidedText)
	Dim Expected() As Byte = Base64UrlDecode(SignNonce(Nonce))
	If Provided = Null Or Expected = Null Then Return False
	Dim Digest As JavaObject
	Digest.InitializeStatic("java.security.MessageDigest")
	Return Digest.RunMethod("isEqual", Array(Provided, Expected))
End Sub

Private Sub SignNonce (Nonce As String) As String
	Dim NonceBytes() As Byte = Base64UrlDecode(Nonce)
	Dim SecretBytes() As Byte = Base64UrlDecode(AsadiState.CsrfSecret)
	If NonceBytes = Null Or SecretBytes = Null Then Return ""
	Dim MacClass As JavaObject
	MacClass.InitializeStatic("javax.crypto.Mac")
	Dim Mac As JavaObject = MacClass.RunMethodJO("getInstance", Array("HmacSHA256"))
	Dim KeySpec As JavaObject
	KeySpec.InitializeNewInstance("javax.crypto.spec.SecretKeySpec", Array(SecretBytes, "HmacSHA256"))
	Mac.RunMethod("init", Array(KeySpec))
	Dim Signature() As Byte = Mac.RunMethod("doFinal", Array(NonceBytes))
	Return Base64Url(Signature)
End Sub

Private Sub RandomBase64Url (ByteCount As Int) As String
	Dim Generator As JavaObject
	Generator.InitializeNewInstance("java.security.SecureRandom", Null)
	Dim Buffer(ByteCount) As Byte
	Generator.RunMethod("nextBytes", Array(Buffer))
	Return Base64Url(Buffer)
End Sub

Private Sub Base64Url (Data() As Byte) As String
	Dim Base64 As JavaObject
	Base64.InitializeStatic("java.util.Base64")
	Dim Encoder As JavaObject = Base64.RunMethodJO("getUrlEncoder", Null)
	Encoder = Encoder.RunMethodJO("withoutPadding", Null)
	Return Encoder.RunMethod("encodeToString", Array(Data))
End Sub

Private Sub Base64UrlDecode (Text As String) As Byte()
	If Text = Null Or Text = "" Then Return Null
	Try
		Dim Base64 As JavaObject
		Base64.InitializeStatic("java.util.Base64")
		Dim Decoder As JavaObject = Base64.RunMethodJO("getUrlDecoder", Null)
		Return Decoder.RunMethod("decode", Array(Text))
	Catch
		Return Null
	End Try
End Sub

Private Sub AddHiddenInput (Parent As MiniHtml, FieldName As String, Value As String) As MiniHtml
	Dim Input As MiniHtml = NewTag(Parent, "input", "")
	Input.attr("type", "hidden").attr("name", FieldName).attr("value", EscapeHtml(Value))
	Return Input
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
			Log(LastException.Message)
		End Try
		WriteError(resp, 500, "Unable to inspect this database. Check that it is a readable SQLite file.")
	End Try
End Sub

Private Sub WriteSqlWorkspace (resp As ServletResponse, DbName As String, req As ServletRequest, CsrfToken As String)
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
			If "" <> Result.Get("error") Then Problem = Result.Get("error")
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
	AddHiddenInput(Form, "csrf", CsrfToken)
	Dim Area As MiniHtml = NewTag(Form, "textarea", "sql-input")
	Area.attr("name", "sql").attr("rows", "8").attr("spellcheck", "false").attr("maxlength", "" & MAX_SQL_LENGTH)
	Area.attr("placeholder", "SELECT name, type FROM sqlite_master ORDER BY name LIMIT 50;")
	Area.text(SqlText)
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
		ErrorText.text(Problem)
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
		HeaderCell.text(Column.Get("name"))
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
	Return OpenJdbcConnection(Path, 1)
End Sub

' open_mode 1 = read-only, 2 = read-write without create. Both reject a missing file,
' so a registered database that disappears is never recreated by a request.
Private Sub OpenJdbcConnection (Path As String, Mode As Int) As JavaObject
	Dim DriverClass As JavaObject
	DriverClass.InitializeStatic("java.lang.Class")
	Try
		DriverClass.RunMethod("forName", Array("org.sqlite.JDBC"))
	Catch
		' The driver is normally registered as a service; the connection attempt reports a clear error otherwise.
		Log(LastException.Message)
	End Try
	Dim Manager As JavaObject
	Manager.InitializeStatic("java.sql.DriverManager")
	Dim Url As String = "jdbc:sqlite:" & Path.Replace("\", "/") & "?open_mode=" & Mode
	Return Manager.RunMethodJO("getConnection", Array(Url))
End Sub

' JDBC reports BLOB as 2004. Reading bytes is the only reliable way to show its size
' because SQLite's getString decodes BLOBs into unreadable text.
Private Sub ReadSqlValue (Rs As JavaObject, TypeId As Int, ColumnIndex As Int) As Map
	If TypeId = 2004 Then
		Dim Bytes() As Byte = Rs.RunMethod("getBytes", Array(ColumnIndex))
		If Rs.RunMethod("wasNull", Null) Then Return CreateMap("kind": "null", "text": "NULL")
		Dim BlobSize As Int = 0
		If Bytes <> Null Then BlobSize = Bytes.Length
		Return CreateMap("kind": "blob", "text": "BLOB · " & BlobSize & " bytes")
	End If
	Dim Value As String = Rs.RunMethod("getString", Array(ColumnIndex))
	If Rs.RunMethod("wasNull", Null) Then Return CreateMap("kind": "null", "text": "NULL")
	Dim Stored As String = Value
	If Stored = Null Then Stored = ""
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
		Log(LastException.Message)
	End Try
End Sub

' Rejects empty input, multiple statements, and anything that is not a read-only statement.
' The scanner ignores separators inside strings, quoted identifiers, and comments.
Private Sub ValidateSqlStatement (SqlText As String) As String
	Dim Scan As Map = ScanSql(SqlText)
	If False = Scan.Get("started") Then Return "Enter a SQL statement to run."
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

Private Sub WriteEditPage (resp As ServletResponse, DbName As String, Method As String, req As ServletRequest, CsrfToken As String)
	Dim Path As String = AsadiState.Databases.Get(DbName)
	If ValidateRegisteredPath(Path) = False Then
		WriteError(resp, 404, "Database is unavailable")
		Return
	End If
	Dim TableName As String = req.GetParameter("table")
	If TableName = Null Or TableName = "" Then
		WriteError(resp, 400, "Choose a table to edit")
		Return
	End If
	Dim IsPost As Boolean = Method = "POST"
	Dim Action As String = ""
	If IsPost Then Action = SafeLower(req.GetParameter("action"))
	Dim IsInsert As Boolean = IsPost And Action = "insert"
	If IsPost = False And req.GetParameter("new") = "1" Then IsInsert = True
	Dim Conn As JavaObject
	Dim Columns As List
	Columns.Initialize
	Dim PrimaryKeys As List
	PrimaryKeys.Initialize
	Dim RowValues As List
	RowValues.Initialize
	Dim RowLoaded As Boolean = False
	Dim KeyMode As String = ""
	Dim RowidExpr As String = ""
	Dim Problem As String = ""
	Dim IsConflict As Boolean = False
	Dim Redirect As String = ""
	Try
		Conn = OpenJdbcConnection(Path, 2)
		Dim ObjectType As String = ReadTableTypeJdbc(Conn, TableName)
		If ObjectType = "" Then
			CloseQuietly(Conn)
			WriteError(resp, 404, "Table not found")
			Return
		End If
		If ObjectType <> "table" Then
			CloseQuietly(Conn)
			WriteError(resp, 400, "Only tables can be edited")
			Return
		End If
		Columns = ReadColumnsJdbc(Conn, TableName)
		If Columns.Size = 0 Then
			CloseQuietly(Conn)
			WriteError(resp, 422, "No columns are available for this table")
			Return
		End If
		PrimaryKeys = PrimaryKeyColumns(Columns)
		Dim KeyPlan As Map = BuildKeyPlan(Columns, PrimaryKeys)
		KeyMode = KeyPlan.Get("mode")
		RowidExpr = KeyPlan.Get("rowid")
		If KeyMode = "" Then
			CloseQuietly(Conn)
			WriteError(resp, 400, "This table has no usable primary key or rowid and cannot be edited")
			Return
		End If
		If IsPost Then
			If IsInsert Then
				Problem = SaveInsert(Conn, TableName, Columns, req)
				If Problem = "" Then Redirect = TableUrl(DbName, TableName, 1, "", "ASC", "") & "&notice=inserted"
			Else
				Dim KeyResult As Map = ReadKeyFromRequest(req, KeyMode, PrimaryKeys)
				If False = KeyResult.Get("ok") Then
					Problem = KeyResult.Get("message")
				Else
					Dim KeyValues As List = KeyResult.Get("values")
					Dim WhereSql As String = BuildKeyWhere(KeyMode, RowidExpr, PrimaryKeys)
					RowValues = FetchEditRow(Conn, TableName, Columns, WhereSql, KeyValues)
					RowLoaded = RowValues.Size > 0
					If RowLoaded = False Then
						Problem = "This row no longer exists."
					Else If Action = "update" Then
						Dim UpdateOutcome As Map = SaveUpdate(Conn, TableName, Columns, PrimaryKeys, KeyMode, RowidExpr, KeyValues, req)
						If UpdateOutcome.Get("ok") Then
							Redirect = TableUrl(DbName, TableName, 1, "", "ASC", "") & "&notice=saved"
						Else
							Problem = UpdateOutcome.Get("message")
							IsConflict = UpdateOutcome.Get("conflict")
						End If
					Else If Action = "delete" Then
						Dim DeleteOutcome As Map = SaveDelete(Conn, TableName, Columns, PrimaryKeys, KeyMode, RowidExpr, KeyValues, req)
						If DeleteOutcome.Get("ok") Then
							Redirect = TableUrl(DbName, TableName, 1, "", "ASC", "") & "&notice=deleted"
						Else
							Problem = DeleteOutcome.Get("message")
							IsConflict = DeleteOutcome.Get("conflict")
						End If
					Else
						Problem = "Unknown edit action."
					End If
				End If
			End If
		Else If IsInsert = False Then
			Dim GetKey As Map = ReadKeyFromRequest(req, KeyMode, PrimaryKeys)
			If False = GetKey.Get("ok") Then
				CloseQuietly(Conn)
				WriteError(resp, 400, GetKey.Get("message"))
				Return
			End If
			Dim RowKeyValues As List = GetKey.Get("values")
			RowValues = FetchEditRow(Conn, TableName, Columns, BuildKeyWhere(KeyMode, RowidExpr, PrimaryKeys), RowKeyValues)
			RowLoaded = RowValues.Size > 0
			If RowLoaded = False Then
				CloseQuietly(Conn)
				WriteError(resp, 404, "Row not found")
				Return
			End If
		End If
	Catch
		Problem = SanitizeDbError(LastException.Message, Path)
	End Try
	CloseQuietly(Conn)
	If Redirect <> "" Then
		resp.SendRedirect(Redirect)
		Return
	End If
	If Problem <> "" Then
		If IsConflict Then
			resp.Status = 409
		Else If IsPost Then
			resp.Status = 400
		End If
	End If
	RenderEditPage(resp, DbName, TableName, Columns, PrimaryKeys, KeyMode, RowValues, RowLoaded, IsInsert, Problem, req, IsPost, CsrfToken)
End Sub

Private Sub RenderEditPage (resp As ServletResponse, DbName As String, TableName As String, Columns As List, PrimaryKeys As List, _
		KeyMode As String, RowValues As List, RowLoaded As Boolean, IsInsert As Boolean, Problem As String, _
		req As ServletRequest, FromRequest As Boolean, CsrfToken As String)
	Dim Content As MiniHtml = NewTag(Null, "section", "workspace edit-workspace")
	Dim Back As MiniHtml = AddText(Content, "a", "back", "← " & TableName)
	Back.attr("href", EscapeHtml(TableUrl(DbName, TableName, 1, "", "ASC", "")))
	AddText(Content, "div", "eyebrow", IIf(IsInsert, "NEW ROW", "EDIT ROW"))
	AddText(Content, "h1", "", TableName)
	If Problem <> "" Then
		Dim ErrorBox As MiniHtml = NewTag(Content, "section", "sql-error")
		AddText(ErrorBox, "strong", "", IIf(IsInsert, "Unable to insert this row", "Unable to save this row"))
		Dim ErrorText As MiniHtml = NewTag(ErrorBox, "pre", "sql-code")
		ErrorText.text(Problem)
	End If
	If IsInsert = False And RowLoaded = False Then
		WritePage(resp, TableName & " · Edit", Content)
		Return
	End If
	AddText(Content, "p", "muted", IIf(IsInsert, "Values are written with bound parameters. Leave an integer primary key blank to autoassign it.", _
		"Change the fields below. The update is rejected if the row changed after this form was loaded."))
	Dim Form As MiniHtml = NewTag(Content, "form", "edit-form")
	Form.attr("method", "post").attr("action", AsadiState.BasePath & "/db/" & DbName & "/edit")
	AddHiddenInput(Form, "csrf", CsrfToken)
	AddHiddenInput(Form, "table", TableName)
	AddHiddenInput(Form, "action", IIf(IsInsert, "insert", "update"))
	If IsInsert = False Then
		AddKeyHiddenInputs(Form, req, PrimaryKeys, KeyMode)
		AddOriginalHiddenInputs(Form, Columns, RowValues)
	End If
	For i = 0 To Columns.Size - 1
		Dim Column As Map = Columns.Get(i)
		Dim ColumnName As String = Column.Get("name")
		Dim DeclaredType As String = SafeString(Column.Get("type"), "")
		Dim IsPk As Boolean = (0 < Column.Get("pk"))
		Dim NotNull As Boolean = (1 = Column.Get("notnull"))
		Dim Blob As Boolean = DeclaredType.ToUpperCase.Contains("BLOB")
		Dim FieldText As String = ""
		Dim FieldNull As Boolean = False
		Dim BlobLength As Long = 0
		Dim TooLarge As Boolean = False
		If RowLoaded Then
			Dim Current As Map = RowValues.Get(i)
			FieldText = Current.Get("text")
			FieldNull = Current.Get("is_null")
			BlobLength = Current.Get("blob_len")
			TooLarge = Current.Get("too_large")
		End If
		If FromRequest And Blob = False And HasParameter(req, "f" & i) Then
			Dim Submitted As String = req.GetParameter("f" & i)
			FieldText = Submitted
			FieldNull = (req.GetParameter("n" & i) = "1")
		End If
		Dim Group As MiniHtml = NewTag(Form, "div", "edit-field")
		Dim Label As MiniHtml = NewTag(Group, "label", "edit-label")
		Dim LabelText As String = ColumnName & IIf(DeclaredType = "", "", " · " & DeclaredType)
		If IsPk Then LabelText = LabelText & " · PRIMARY KEY"
		If NotNull And IsPk = False Then LabelText = LabelText & " · required"
		Label.text(LabelText)
		If Blob And FieldNull Then
			Dim NullBlobBox As MiniHtml = NewTag(Group, "div", "edit-readonly")
			AddText(NullBlobBox, "span", "null-value", "NULL")
			AddText(Group, "p", "field-note", "Binary values are not editable in this form.")
		Else If Blob Then
			Dim BlobBox As MiniHtml = NewTag(Group, "div", "edit-readonly")
			AddText(BlobBox, "span", "blob-value", "BLOB · " & BlobLength & " bytes")
			AddText(Group, "p", "field-note", "Binary values are not editable in this form.")
		Else If IsInsert = False And IsPk Then
			Dim KeyBox As MiniHtml = NewTag(Group, "div", "edit-readonly")
			KeyBox.text(FieldText)
			AddHiddenInput(Group, "f" & i, FieldText)
		Else If TooLarge Then
			Dim LargeBox As MiniHtml = NewTag(Group, "div", "edit-readonly")
			LargeBox.text("Value is larger than " & MAX_EDIT_VALUE & " characters and is shown read-only.")
			AddText(Group, "p", "field-note", "This column is preserved unchanged when other fields are saved.")
		Else
			AddEditFieldInput(Group, i, DeclaredType, FieldText)
			If NotNull = False Then
				Dim NullLabel As MiniHtml = NewTag(Group, "label", "null-toggle")
				Dim NullBox As MiniHtml = NewTag(NullLabel, "input", "")
				NullBox.attr("type", "checkbox").attr("name", "n" & i).attr("value", "1")
				If FieldNull Then NullBox.attr("checked", "checked")
				AddText(NullLabel, "span", "", " Set to NULL")
			End If
		End If
	Next
	Dim Actions As MiniHtml = NewTag(Form, "div", "sql-actions")
	Dim SaveButton As MiniHtml = NewTag(Actions, "button", "btn-primary")
	SaveButton.attr("type", "submit").text(IIf(IsInsert, "Insert row", "Save changes"))
	AddText(Actions, "span", "sql-hint", "Writes are authenticated and CSRF-checked.")
	If IsInsert = False And RowLoaded Then
		Dim DeleteWrap As MiniHtml = NewTag(Content, "section", "delete-box")
		AddText(DeleteWrap, "h2", "", "Delete this row")
		AddText(DeleteWrap, "p", "muted", "This action is permanent. It is rejected if the row changed after this form was loaded.")
		Dim DeleteOpen As MiniHtml = NewTag(DeleteWrap, "a", "btn-danger")
		DeleteOpen.attr("href", "#delete-row").text("Delete row")
		Dim Modal As MiniHtml = NewTag(Content, "div", "modal")
		Modal.attr("id", "delete-row").attr("role", "dialog").attr("aria-modal", "true").attr("aria-labelledby", "delete-row-title")
		Dim Backdrop As MiniHtml = NewTag(Modal, "a", "modal-backdrop")
		Backdrop.attr("href", "#").attr("aria-label", "Close delete confirmation")
		Dim Panel As MiniHtml = NewTag(Modal, "div", "modal-panel")
		Dim ModalTitle As MiniHtml = AddText(Panel, "h2", "", "Delete this row?")
		ModalTitle.attr("id", "delete-row-title")
		AddText(Panel, "p", "muted", "The row is deleted only if it still matches the values loaded in this form. This cannot be undone.")
		Dim DeleteForm As MiniHtml = NewTag(Panel, "form", "delete-form")
		DeleteForm.attr("method", "post").attr("action", AsadiState.BasePath & "/db/" & DbName & "/edit")
		AddHiddenInput(DeleteForm, "csrf", CsrfToken)
		AddHiddenInput(DeleteForm, "table", TableName)
		AddHiddenInput(DeleteForm, "action", "delete")
		AddKeyHiddenInputs(DeleteForm, req, PrimaryKeys, KeyMode)
		AddOriginalHiddenInputs(DeleteForm, Columns, RowValues)
		Dim ModalActions As MiniHtml = NewTag(DeleteForm, "div", "modal-actions")
		Dim CancelLink As MiniHtml = NewTag(ModalActions, "a", "btn-secondary")
		CancelLink.attr("href", "#").text("Cancel")
		Dim DeleteButton As MiniHtml = NewTag(ModalActions, "button", "btn-danger")
		DeleteButton.attr("type", "submit").text("Delete row")
	End If
	WritePage(resp, TableName & IIf(IsInsert, " · New row", " · Edit"), Content)
End Sub

Private Sub AddEditFieldInput (Parent As MiniHtml, Index As Int, DeclaredType As String, Value As String)
	Dim UpperType As String = DeclaredType.ToUpperCase
	Dim UseInput As Boolean = UpperType.Contains("INT") Or UpperType.Contains("REAL") Or UpperType.Contains("NUM") Or _
		UpperType.Contains("DEC") Or UpperType.Contains("BOOL") Or UpperType.Contains("DATE") Or Value.Length <= 80
	If UseInput Then
		Dim Input As MiniHtml = NewTag(Parent, "input", "edit-input")
		Input.attr("type", "text").attr("name", "f" & Index).attr("value", EscapeHtml(Value)).attr("maxlength", "" & MAX_EDIT_VALUE)
	Else
		Dim Area As MiniHtml = NewTag(Parent, "textarea", "edit-input edit-textarea")
		Area.attr("name", "f" & Index).attr("rows", "3").attr("maxlength", "" & MAX_EDIT_VALUE)
		Area.text(Value)
	End If
End Sub

Private Sub AddKeyHiddenInputs (Parent As MiniHtml, req As ServletRequest, PrimaryKeys As List, KeyMode As String)
	If KeyMode = "rowid" Then
		AddHiddenInput(Parent, "k0", SafeString(req.GetParameter("k0"), ""))
		Return
	End If
	For i = 0 To PrimaryKeys.Size - 1
		If HasParameter(req, "k" & i) = False Then
			AddHiddenInput(Parent, "k" & i, "")
			AddHiddenInput(Parent, "kn" & i, "1")
		Else
			AddHiddenInput(Parent, "k" & i, req.GetParameter("k" & i))
		End If
	Next
End Sub

Private Sub AddOriginalHiddenInputs (Parent As MiniHtml, Columns As List, RowValues As List)
	For i = 0 To Columns.Size - 1
		Dim Column As Map = Columns.Get(i)
		Dim DeclaredType As String = SafeUpper(Column.Get("type"))
		If DeclaredType.Contains("BLOB") = False Then
			Dim Current As Map = RowValues.Get(i)
			If False = Current.Get("too_large") Then
				AddHiddenInput(Parent, "o" & i, Current.Get("text"))
				If Current.Get("is_null") Then AddHiddenInput(Parent, "on" & i, "1")
			End If
		End If
	Next
End Sub

Private Sub ReadTableTypeJdbc (Conn As JavaObject, TableName As String) As String
	Dim Ps As JavaObject = Conn.RunMethodJO("prepareStatement", Array("SELECT type FROM sqlite_master WHERE name = ? AND name NOT LIKE 'sqlite_%'"))
	Ps.RunMethod("setString", Array(1, TableName))
	Dim Rs As JavaObject = Ps.RunMethodJO("executeQuery", Null)
	Dim Result As String = ""
	If Rs.RunMethod("next", Null) Then Result = SafeString(Rs.RunMethod("getString", Array(1)), "")
	CloseQuietly(Rs)
	CloseQuietly(Ps)
	Return Result
End Sub

Private Sub ReadColumnsJdbc (Conn As JavaObject, TableName As String) As List
	Dim Columns As List
	Columns.Initialize
	Dim Stmt As JavaObject = Conn.RunMethodJO("createStatement", Null)
	Dim Rs As JavaObject = Stmt.RunMethodJO("executeQuery", Array("PRAGMA table_info(" & QuoteIdentifier(TableName) & ")"))
	Do While Rs.RunMethod("next", Null)
		Dim ColumnName As String = SafeString(Rs.RunMethod("getString", Array("name")), "")
		Dim ColumnType As String = SafeString(Rs.RunMethod("getString", Array("type")), "")
		Dim NotNullFlag As Int = Rs.RunMethod("getInt", Array("notnull"))
		Dim PkFlag As Int = Rs.RunMethod("getInt", Array("pk"))
		Dim DefaultValue As Object = Rs.RunMethod("getString", Array("dflt_value"))
		If Rs.RunMethod("wasNull", Null) Then DefaultValue = Null
		Columns.Add(CreateMap("name": ColumnName, "type": ColumnType, "notnull": NotNullFlag, "pk": PkFlag, "default": DefaultValue))
	Loop
	CloseQuietly(Rs)
	CloseQuietly(Stmt)
	Return Columns
End Sub

Private Sub FetchEditRow (Conn As JavaObject, TableName As String, Columns As List, WhereSql As String, KeyValues As List) As List
	Dim Values As List
	Values.Initialize
	Dim Ps As JavaObject = Conn.RunMethodJO("prepareStatement", Array("SELECT * FROM " & QuoteIdentifier(TableName) & " WHERE " & WhereSql))
	BindValues(Ps, KeyValues, 1)
	Dim Rs As JavaObject = Ps.RunMethodJO("executeQuery", Null)
	If Rs.RunMethod("next", Null) = False Then
		CloseQuietly(Rs)
		CloseQuietly(Ps)
		Return Values
	End If
	Dim Meta As JavaObject = Rs.RunMethodJO("getMetaData", Null)
	For i = 0 To Columns.Size - 1
		Dim TypeId As Int = Meta.RunMethod("getColumnType", Array(i + 1))
		Dim Info As Map = CreateMap("is_null": False, "text": "", "blob_len": 0, "too_large": False)
		If TypeId = 2004 Then
			Dim Bytes() As Byte = Rs.RunMethod("getBytes", Array(i + 1))
			If Rs.RunMethod("wasNull", Null) Then
				Info.Put("is_null", True)
			Else
				Dim BlobSize As Int = 0
				If Bytes <> Null Then BlobSize = Bytes.Length
				Info.Put("blob_len", BlobSize)
			End If
		Else
			Dim TextValue As String = Rs.RunMethod("getString", Array(i + 1))
			If Rs.RunMethod("wasNull", Null) Then
				Info.Put("is_null", True)
			Else
				If TextValue = Null Then TextValue = ""
				Info.Put("text", TextValue)
				If TextValue.Length > MAX_EDIT_VALUE Then Info.Put("too_large", True)
			End If
		End If
		Values.Add(Info)
	Next
	CloseQuietly(Rs)
	CloseQuietly(Ps)
	Return Values
End Sub

Private Sub ReadKeyFromRequest (req As ServletRequest, KeyMode As String, PrimaryKeys As List) As Map
	Dim Values As List
	Values.Initialize
	If KeyMode = "" Then Return CreateMap("ok": False, "message": "This table cannot be edited.", "values": Values)
	If KeyMode = "rowid" Then
		If HasParameter(req, "k0") = False Then
			Return CreateMap("ok": False, "message": "Invalid row identifier.", "values": Values)
		End If
		Dim RowidValue As String = req.GetParameter("k0")
		If Regex.IsMatch("^-?[0-9]{1,19}$", RowidValue) = False Then
			Return CreateMap("ok": False, "message": "Invalid row identifier.", "values": Values)
		End If
		Values.Add(RowidValue)
		Return CreateMap("ok": True, "message": "", "values": Values)
	End If
	For i = 0 To PrimaryKeys.Size - 1
		If HasParameter(req, "k" & i) = False Then
			If req.GetParameter("kn" & i) = "1" Then
				Values.Add(Null)
			Else
				Return CreateMap("ok": False, "message": "The primary-key value is missing.", "values": Values)
			End If
		Else
			Values.Add(req.GetParameter("k" & i))
		End If
	Next
	Return CreateMap("ok": True, "message": "", "values": Values)
End Sub

Private Sub BuildKeyWhere (KeyMode As String, RowidExpr As String, PrimaryKeys As List) As String
	If KeyMode = "rowid" Then Return RowidExpr & " = ?"
	Dim Parts As List
	Parts.Initialize
	For Each KeyName As String In PrimaryKeys
		Parts.Add(QuoteIdentifier(KeyName) & " IS ?")
	Next
	Return JoinParts(Parts, " AND ")
End Sub

Private Sub SaveInsert (Conn As JavaObject, TableName As String, Columns As List, req As ServletRequest) As String
	Dim Names As List
	Names.Initialize
	Dim Args As List
	Args.Initialize
	For i = 0 To Columns.Size - 1
		Dim Column As Map = Columns.Get(i)
		Dim ColumnName As String = Column.Get("name")
		Dim DeclaredType As String = SafeUpper(Column.Get("type"))
		If DeclaredType.Contains("BLOB") = False And HasParameter(req, "f" & i) Then
			Dim FieldNull As Boolean = (req.GetParameter("n" & i) = "1")
			Dim Value As String = req.GetParameter("f" & i)
			If Value = Null Then Value = ""
			If Value.Length > MAX_EDIT_VALUE Then Return "Column " & ColumnName & " is too long."
			If FieldNull Then
				If 1 = Column.Get("notnull") And 0 = Column.Get("pk") Then Return "Column " & ColumnName & " cannot be NULL."
				If IsAutoKey(Columns, i) Then
					' Leave the integer primary key to SQLite.
				Else
					Names.Add(QuoteIdentifier(ColumnName))
					Args.Add(Null)
				End If
			Else If Value = "" And IsAutoKey(Columns, i) Then
				' SQLite assigns the next rowid.
			Else If Value = "" And IsNumericType(DeclaredType) Then
				If HasDefault(Column) Then
					' Omit the column so its declared default applies.
				Else If 1 = Column.Get("notnull") Then
					Return "Column " & ColumnName & " requires a value."
				End If
				' Otherwise omit it so SQLite stores NULL instead of text in a numeric column.
			Else If Value = "" And HasDefault(Column) Then
				' Omit the column so its declared default applies.
			Else
				Names.Add(QuoteIdentifier(ColumnName))
				Args.Add(Value)
			End If
		End If
	Next
	Dim SqlText As String
	If Names.Size = 0 Then
		SqlText = "INSERT INTO " & QuoteIdentifier(TableName) & " DEFAULT VALUES"
	Else
		Dim Marks As List
		Marks.Initialize
		For i = 1 To Names.Size
			Marks.Add("?")
		Next
		SqlText = "INSERT INTO " & QuoteIdentifier(TableName) & " (" & JoinParts(Names, ", ") & ") VALUES (" & JoinParts(Marks, ", ") & ")"
	End If
	Dim Affected As Int = ExecuteWrite(Conn, SqlText, Args)
	If Affected = 1 Then Return ""
	Return "The insert affected " & Affected & " rows and was not accepted."
End Sub

Private Sub SaveUpdate (Conn As JavaObject, TableName As String, Columns As List, PrimaryKeys As List, KeyMode As String, _
		RowidExpr As String, KeyValues As List, req As ServletRequest) As Map
	Dim Sets As List
	Sets.Initialize
	Dim Args As List
	Args.Initialize
	For i = 0 To Columns.Size - 1
		Dim Column As Map = Columns.Get(i)
		Dim DeclaredType As String = SafeUpper(Column.Get("type"))
		Dim IsPk As Boolean = (0 < Column.Get("pk"))
		If DeclaredType.Contains("BLOB") = False And IsPk = False And HasParameter(req, "f" & i) Then
			Dim Submitted As String = req.GetParameter("f" & i)
			If Submitted = Null Then Submitted = ""
			Dim NullRequested As Boolean = (req.GetParameter("n" & i) = "1")
			Dim Problem As String = ValidateEditValue(Column, Submitted, NullRequested)
			If Problem <> "" Then Return EditOutcome(False, Problem, False)
			If Submitted = "" And IsNumericType(DeclaredType) And NullRequested = False Then
				If 1 = Column.Get("notnull") Then Return EditOutcome(False, "Column " & Column.Get("name") & " requires a value.", False)
				NullRequested = True
			End If
			Sets.Add(QuoteIdentifier(Column.Get("name")) & " = ?")
			If NullRequested Then
				Args.Add(Null)
			Else
				Args.Add(Submitted)
			End If
		End If
	Next
	If Sets.Size = 0 Then Return EditOutcome(False, "There are no editable fields to update.", False)
	Dim Version As Map = BuildVersionPredicate(Columns, req)
	Dim SqlText As String = "UPDATE " & QuoteIdentifier(TableName) & " SET " & JoinParts(Sets, ", ") & _
		" WHERE " & BuildKeyWhere(KeyMode, RowidExpr, PrimaryKeys) & Version.Get("sql")
	Dim AllArgs As List
	AllArgs.Initialize
	AppendAll(AllArgs, Args)
	AppendAll(AllArgs, KeyValues)
	AppendAll(AllArgs, Version.Get("args"))
	Dim Affected As Int = ExecuteWrite(Conn, SqlText, AllArgs)
	If Affected = 1 Then Return EditOutcome(True, "", False)
	If Affected = 0 Then
		If RowExists(Conn, TableName, BuildKeyWhere(KeyMode, RowidExpr, PrimaryKeys), KeyValues) Then
			Return EditOutcome(False, "This row changed after the form was loaded. Review the current values and submit again.", True)
		End If
		Return EditOutcome(False, "This row no longer exists.", False)
	End If
	Return EditOutcome(False, "The update matched " & Affected & " rows and was not accepted.", False)
End Sub

Private Sub SaveDelete (Conn As JavaObject, TableName As String, Columns As List, PrimaryKeys As List, KeyMode As String, _
		RowidExpr As String, KeyValues As List, req As ServletRequest) As Map
	Dim Version As Map = BuildVersionPredicate(Columns, req)
	Dim SqlText As String = "DELETE FROM " & QuoteIdentifier(TableName) & " WHERE " & _
		BuildKeyWhere(KeyMode, RowidExpr, PrimaryKeys) & Version.Get("sql")
	Dim AllArgs As List
	AllArgs.Initialize
	AppendAll(AllArgs, KeyValues)
	AppendAll(AllArgs, Version.Get("args"))
	Dim Affected As Int = ExecuteWrite(Conn, SqlText, AllArgs)
	If Affected = 1 Then Return EditOutcome(True, "", False)
	If Affected = 0 Then
		If RowExists(Conn, TableName, BuildKeyWhere(KeyMode, RowidExpr, PrimaryKeys), KeyValues) Then
			Return EditOutcome(False, "This row changed after the form was loaded. Review the current values and try again.", True)
		End If
		Return EditOutcome(False, "This row no longer exists.", False)
	End If
	Return EditOutcome(False, "The delete matched " & Affected & " rows and was not accepted.", False)
End Sub

Private Sub BuildVersionPredicate (Columns As List, req As ServletRequest) As Map
	Dim Parts As List
	Parts.Initialize
	Dim Args As List
	Args.Initialize
	For i = 0 To Columns.Size - 1
		Dim Column As Map = Columns.Get(i)
		Dim DeclaredType As String = SafeUpper(Column.Get("type"))
		If DeclaredType.Contains("BLOB") = False And 0 = Column.Get("pk") And HasParameter(req, "o" & i) Then
			Dim Original As String = req.GetParameter("o" & i)
			Parts.Add(QuoteIdentifier(Column.Get("name")) & " IS ?")
			If req.GetParameter("on" & i) = "1" Then
				Args.Add(Null)
			Else
				Args.Add(Original)
			End If
		End If
	Next
	Dim Suffix As String = ""
	If Parts.Size > 0 Then Suffix = " AND " & JoinParts(Parts, " AND ")
	Return CreateMap("sql": Suffix, "args": Args)
End Sub

Private Sub ValidateEditValue (Column As Map, Value As String, NullRequested As Boolean) As String
	Dim ColumnName As String = Column.Get("name")
	If Value.Length > MAX_EDIT_VALUE Then Return "Column " & ColumnName & " is too long."
	If NullRequested And 1 = Column.Get("notnull") Then Return "Column " & ColumnName & " cannot be NULL."
	Return ""
End Sub

Private Sub IsNumericType (DeclaredType As String) As Boolean
	Dim UpperType As String = DeclaredType.ToUpperCase
	Return UpperType.Contains("INT") Or UpperType.Contains("REAL") Or UpperType.Contains("NUM") Or _
		UpperType.Contains("DEC") Or UpperType.Contains("BOOL")
End Sub

Private Sub IsAutoKey (Columns As List, Index As Int) As Boolean
	Dim Column As Map = Columns.Get(Index)
	If 0 = Column.Get("pk") Then Return False
	Dim PrimaryCount As Int
	For Each Candidate As Map In Columns
		If 0 < Candidate.Get("pk") Then PrimaryCount = PrimaryCount + 1
	Next
	If PrimaryCount <> 1 Then Return False
	Dim DeclaredType As String = SafeUpper(Column.Get("type"))
	Return DeclaredType.Trim.ToUpperCase = "INTEGER"
End Sub

Private Sub HasDefault (Column As Map) As Boolean
	Dim Value As Object = Column.Get("default")
	If Value = Null Then Return False
	Return SafeString(Value, "") <> ""
End Sub

Private Sub ExecuteWrite (Conn As JavaObject, SqlText As String, Values As List) As Int
	Dim Ps As JavaObject = Conn.RunMethodJO("prepareStatement", Array(SqlText))
	BindValues(Ps, Values, 1)
	Dim Affected As Int = Ps.RunMethod("executeUpdate", Null)
	CloseQuietly(Ps)
	Return Affected
End Sub

Private Sub BindValues (Ps As JavaObject, Values As List, StartIndex As Int)
	For i = 0 To Values.Size - 1
		Dim Value As Object = Values.Get(i)
		If Value = Null Then
			Ps.RunMethod("setNull", Array(StartIndex + i, 12))
		Else
			Ps.RunMethod("setObject", Array(StartIndex + i, Value))
		End If
	Next
End Sub

Private Sub RowExists (Conn As JavaObject, TableName As String, WhereSql As String, KeyValues As List) As Boolean
	Dim Ps As JavaObject = Conn.RunMethodJO("prepareStatement", Array("SELECT 1 FROM " & QuoteIdentifier(TableName) & " WHERE " & WhereSql))
	BindValues(Ps, KeyValues, 1)
	Dim Rs As JavaObject = Ps.RunMethodJO("executeQuery", Null)
	Dim Found As Boolean = Rs.RunMethod("next", Null)
	CloseQuietly(Rs)
	CloseQuietly(Ps)
	Return Found
End Sub

Private Sub JoinParts (Parts As List, Separator As String) As String
	Dim Builder As StringBuilder
	Builder.Initialize
	For i = 0 To Parts.Size - 1
		If i > 0 Then Builder.Append(Separator)
		Builder.Append(Parts.Get(i))
	Next
	Return Builder.ToString
End Sub

Private Sub AppendAll (Target As List, Source As List)
	For Each Value As Object In Source
		Target.Add(Value)
	Next
End Sub

Private Sub EditOutcome (Ok As Boolean, Message As String, Conflict As Boolean) As Map
	Return CreateMap("ok": Ok, "message": Message, "conflict": Conflict)
End Sub

' Exports stream rows as they are read. CSV quotes every field, prefixes spreadsheet
' formula triggers, and base64-encodes BLOBs. JSON distinguishes NULL, numbers, text,
' and base64 BLOBs. Both formats are capped at MAX_EXPORT_ROWS rows and
' MAX_EXPORT_COLUMNS columns; a single value is not length-capped.
Private Sub WriteExport (resp As ServletResponse, DbName As String, req As ServletRequest)
	Dim Path As String = AsadiState.Databases.Get(DbName)
	If ValidateRegisteredPath(Path) = False Then
		WriteError(resp, 404, "Database is unavailable")
		Return
	End If
	Dim TableName As String = req.GetParameter("table")
	If TableName = Null Then TableName = ""
	If TableName = "" Then
		WriteError(resp, 400, "Choose a table or view to export")
		Return
	End If
	Dim Format As String = SafeLower(req.GetParameter("format"))
	If Format <> "csv" And Format <> "json" Then
		WriteError(resp, 400, "Choose csv or json as the export format")
		Return
	End If
	Dim Conn As JavaObject
	Dim Stmt As JavaObject
	Dim Rs As JavaObject
	Dim Started As Boolean = False
	Try
		Conn = OpenReadOnlyConnection(Path)
		Dim ObjectType As String = ReadTableTypeJdbc(Conn, TableName)
		If ObjectType <> "table" And ObjectType <> "view" Then
			WriteError(resp, 404, "Table or view not found")
		Else
			Stmt = Conn.RunMethodJO("createStatement", Null)
			Stmt.RunMethod("setMaxRows", Array(MAX_EXPORT_ROWS))
			Rs = Stmt.RunMethodJO("executeQuery", Array("SELECT * FROM " & QuoteIdentifier(TableName)))
			Dim Meta As JavaObject = Rs.RunMethodJO("getMetaData", Null)
			Dim ColumnCount As Int = Meta.RunMethod("getColumnCount", Null)
			If ColumnCount = 0 Then
				WriteError(resp, 422, "No columns are available to export")
			Else If ColumnCount > MAX_EXPORT_COLUMNS Then
				WriteError(resp, 400, "This table has more than " & MAX_EXPORT_COLUMNS & " columns; narrow it before exporting")
			Else
				Dim Names As List
				Names.Initialize
				Dim Types As List
				Types.Initialize
				For i = 1 To ColumnCount
					Names.Add(SafeString(Meta.RunMethod("getColumnLabel", Array(i)), "column" & i))
					Types.Add(Meta.RunMethod("getColumnType", Array(i)))
				Next
				Dim FileBase As String = SafeDownloadName(DbName & "-" & TableName)
				resp.CharacterEncoding = "UTF-8"
				If Format = "csv" Then
					resp.ContentType = "text/csv; charset=utf-8"
					resp.SetHeader("Content-Disposition", "attachment; filename=" & Chr(34) & FileBase & ".csv" & Chr(34))
				Else
					resp.ContentType = "application/json; charset=utf-8"
					resp.SetHeader("Content-Disposition", "attachment; filename=" & Chr(34) & FileBase & ".json" & Chr(34))
				End If
				resp.SetHeader("X-Asadi-Row-Limit", "" & MAX_EXPORT_ROWS)
				If Format = "csv" Then
					' UTF-8 BOM so spreadsheet programs detect the encoding.
					resp.Write(Chr(65279))
					Started = True
					WriteCsvExport(resp, Rs, Names, Types, ColumnCount)
				Else
					resp.Write("[")
					Started = True
					WriteJsonExport(resp, Rs, Names, Types, ColumnCount)
					resp.Write("]")
				End If
			End If
		End If
	Catch
		If Started = False Then WriteError(resp, 500, SanitizeDbError(LastException.Message, Path))
	End Try
	CloseQuietly(Rs)
	CloseQuietly(Stmt)
	CloseQuietly(Conn)
End Sub

Private Sub WriteCsvExport (resp As ServletResponse, Rs As JavaObject, Names As List, Types As List, ColumnCount As Int)
	Dim Header As StringBuilder
	Header.Initialize
	For i = 0 To ColumnCount - 1
		If i > 0 Then Header.Append(",")
		Header.Append(CsvField(Names.Get(i)))
	Next
	Header.Append(Chr(13)).Append(Chr(10))
	resp.Write(Header.ToString)
	Do While Rs.RunMethod("next", Null)
		Dim Row As StringBuilder
		Row.Initialize
		For i = 0 To ColumnCount - 1
			Dim TypeId As Int = Types.Get(i)
			Dim Cell As Map = ReadExportCell(Rs, TypeId, i + 1)
			If i > 0 Then Row.Append(",")
			If Cell.Get("is_null") Then
				Row.Append(CsvField(""))
			Else If Cell.Get("is_blob") Then
				Row.Append(CsvField("base64:" & Cell.Get("text")))
			Else
				Row.Append(CsvField(Cell.Get("text")))
			End If
		Next
		Row.Append(Chr(13)).Append(Chr(10))
		resp.Write(Row.ToString)
	Loop
End Sub

Private Sub WriteJsonExport (resp As ServletResponse, Rs As JavaObject, Names As List, Types As List, ColumnCount As Int)
	Dim FirstRow As Boolean = True
	Do While Rs.RunMethod("next", Null)
		Dim Row As StringBuilder
		Row.Initialize
		If FirstRow = False Then resp.Write(",")
		FirstRow = False
		Row.Append("{")
		For i = 0 To ColumnCount - 1
			Dim TypeId As Int = Types.Get(i)
			Dim Cell As Map = ReadExportCell(Rs, TypeId, i + 1)
			If i > 0 Then Row.Append(",")
			Row.Append(JsonQuote(Names.Get(i))).Append(":")
			If Cell.Get("is_null") Then
				Row.Append("null")
			Else If Cell.Get("is_blob") Then
				Row.Append(JsonQuote("base64:" & Cell.Get("text")))
			Else
				Dim Raw As String = Cell.Get("text")
				If IsJsonNumber(TypeId, Raw) Then
					Row.Append(Raw)
				Else
					Row.Append(JsonQuote(Raw))
				End If
			End If
		Next
		Row.Append("}")
		resp.Write(Row.ToString)
	Loop
End Sub

Private Sub ReadExportCell (Rs As JavaObject, TypeId As Int, Index As Int) As Map
	If TypeId = 2004 Then
		Dim Bytes() As Byte = Rs.RunMethod("getBytes", Array(Index))
		If Rs.RunMethod("wasNull", Null) Then Return CreateMap("is_null": True, "is_blob": True, "text": "")
		Dim Encoded As String = ""
		If Bytes <> Null Then Encoded = EncodeBase64(Bytes)
		Return CreateMap("is_null": False, "is_blob": True, "text": Encoded)
	End If
	Dim Value As String = Rs.RunMethod("getString", Array(Index))
	If Rs.RunMethod("wasNull", Null) Then Return CreateMap("is_null": True, "is_blob": False, "text": "")
	If Value = Null Then Value = ""
	Return CreateMap("is_null": False, "is_blob": False, "text": Value)
End Sub

Private Sub CsvField (Value As String) As String
	Dim QuoteChar As String = Chr(34)
	Dim Neutral As String = NeutralizeCsv(Value)
	Return QuoteChar & Neutral.Replace(QuoteChar, QuoteChar & QuoteChar) & QuoteChar
End Sub

' Spreadsheet programs execute cells that start with =, +, -, @, tab, CR, or LF.
' Numeric values keep their sign; everything else gets a leading apostrophe.
Private Sub NeutralizeCsv (Value As String) As String
	If Value = "" Then Return Value
	Dim First As String = Value.SubString2(0, 1)
	If First = "=" Or First = "@" Or First = Chr(9) Or First = Chr(10) Or First = Chr(13) Then Return "'" & Value
	If First = "+" Or First = "-" Then
		If Regex.IsMatch("^-?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$", Value) = False Then Return "'" & Value
	End If
	Return Value
End Sub

Private Sub JsonQuote (Value As String) As String
	Dim Builder As StringBuilder
	Builder.Initialize
	Builder.Append(Chr(34))
	For i = 0 To Value.Length - 1
		Dim Ch As String = Value.SubString2(i, i + 1)
		Dim Code As Int = Asc(Ch)
		If Ch = Chr(34) Then
			Builder.Append("\").Append(Chr(34))
		Else If Ch = "\" Then
			Builder.Append("\\")
		Else If Code = 8 Then
			Builder.Append("\").Append("b")
		Else If Code = 9 Then
			Builder.Append("\").Append("t")
		Else If Code = 10 Then
			Builder.Append("\").Append("n")
		Else If Code = 12 Then
			Builder.Append("\").Append("f")
		Else If Code = 13 Then
			Builder.Append("\").Append("r")
		Else If Code < 32 Then
			Builder.Append("\").Append("u").Append(Hex4(Code))
		Else
			Builder.Append(Ch)
		End If
	Next
	Builder.Append(Chr(34))
	Return Builder.ToString
End Sub

Private Sub Hex4 (Code As Int) As String
	Dim Digits As String = "0123456789abcdef"
	Dim Builder As StringBuilder
	Builder.Initialize
	For Shift = 12 To 0 Step -4
		Dim Nibble As Int = Bit.And(Bit.ShiftRight(Code, Shift), 15)
		Builder.Append(Digits.SubString2(Nibble, Nibble + 1))
	Next
	Return Builder.ToString
End Sub

Private Sub IsJsonNumber (TypeId As Int, Value As String) As Boolean
	Select TypeId
		Case 2, 3, 4, 5, -5, -6, 6, 7, 8
			' NUMERIC and DECIMAL are included: SQLite NUMERIC affinity columns hold
			' real numbers here, and the regex keeps any stored text quoted.
			Return Regex.IsMatch("^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$", Value)
	End Select
	Return False
End Sub

Private Sub EncodeBase64 (Data() As Byte) As String
	Dim Base64 As JavaObject
	Base64.InitializeStatic("java.util.Base64")
	Dim Encoder As JavaObject = Base64.RunMethodJO("getEncoder", Null)
	Return Encoder.RunMethod("encodeToString", Array(Data))
End Sub

Private Sub SafeDownloadName (Text As String) As String
	Dim Builder As StringBuilder
	Builder.Initialize
	For i = 0 To Text.Length - 1
		Dim Ch As String = Text.SubString2(i, i + 1)
		If Regex.IsMatch("^[A-Za-z0-9._-]$", Ch) Then
			Builder.Append(Ch)
		Else
			Builder.Append("_")
		End If
	Next
	Dim Result As String = Builder.ToString
	If Result = "" Then Result = "export"
	If Result.Length > 80 Then Result = Result.SubString2(0, 80)
	Return Result
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
			Link.text(ObjectName)
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
	Dim KeyPlan As Map = BuildKeyPlan(Columns, PrimaryKeys)
	Dim KeyMode As String = KeyPlan.Get("mode")
	Dim Editable As Boolean = (IsView = False And KeyMode <> "")
	Dim RowidExpr As String = KeyPlan.Get("rowid")
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
	Dim Query As String = BuildPageQuery(TableName, DataColumns, SearchColumns, PrimaryKeys, SearchText, SortColumn, SortDirection, Page, Editable, KeyMode, RowidExpr)
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
	Dim Notice As String = req.GetParameter("notice")
	If Notice = "inserted" Then
		AddText(Content, "p", "notice-banner", "Row inserted.")
	Else If Notice = "saved" Then
		AddText(Content, "p", "notice-banner", "Row updated.")
	Else If Notice = "deleted" Then
		AddText(Content, "p", "notice-banner", "Row deleted.")
	End If
	AddText(Content, "div", "eyebrow", IIf(IsView, "VIEW DATA", "TABLE DATA"))
	AddText(Content, "h1", "", TableName)
	AddText(Content, "p", "muted", IIf(IsView, "Read-only browser", "Row browser") & " · Page " & Page)
	Dim Actions As MiniHtml = NewTag(Content, "div", "page-actions")
	If Editable Then
		Dim NewLink As MiniHtml = NewTag(Actions, "a", "action-link")
		NewLink.attr("href", AsadiState.BasePath & "/db/" & DbName & "/edit?table=" & EncodeQuery(TableName) & "&new=1")
		NewLink.text("+ New row")
	End If
	Dim CsvLink As MiniHtml = NewTag(Actions, "a", "action-link secondary")
	CsvLink.attr("href", EscapeHtml(ExportUrl(DbName, TableName, "csv")))
	CsvLink.text("Export CSV")
	Dim JsonLink As MiniHtml = NewTag(Actions, "a", "action-link secondary")
	JsonLink.attr("href", EscapeHtml(ExportUrl(DbName, TableName, "json")))
	JsonLink.text("Export JSON")
	If IsView Then AddText(Content, "p", "info-note", "This object is a view; its displayed rows are read-only.")
	If IsView = False And Editable = False Then AddText(Content, "p", "info-note", "This table cannot be edited because it has no usable primary key or rowid.")
	If PrimaryKeys.Size = 0 And IsView = False Then AddText(Content, "p", "info-note", "No primary key is defined. Rows are ordered by the selected column and edited by rowid.")
	If IsView And PrimaryKeys.Size = 0 Then AddText(Content, "p", "info-note", "No primary key is defined. Rows are browse-only and ordered by the selected column.")
	If Editable Then AddText(Content, "p", "info-note", "Updates and deletes are checked against the row values loaded into the form; a stale form is rejected instead of overwriting newer data.")
	If Columns.Size > MAX_DATA_COLUMNS Then AddText(Content, "p", "info-note", "Showing the first " & MAX_DATA_COLUMNS & " of " & Columns.Size & " columns in the data grid.")
	If Columns.Size > MAX_SEARCH_COLUMNS Then AddText(Content, "p", "info-note", "Search checks at most the first " & MAX_SEARCH_COLUMNS & " non-BLOB columns.")
	AddSchemaSection(Content, Columns, ForeignKeys, Indexes, Definition)
	AddSearchForm(Content, DbName, TableName, SearchText)
	Dim Grid As MiniHtml = NewTag(Content, "div", "table-scroll")
	Dim DataGrid As MiniHtml = NewTag(Grid, "table", "data-grid")
	Dim Head As MiniHtml = NewTag(DataGrid, "thead", "")
	Dim HeaderRow As MiniHtml = NewTag(Head, "tr", "")
	If Editable Then AddText(HeaderRow, "th", "edit-head", "Edit")
	For Each Column As Map In DataColumns
		Dim ColumnName As String = Column.Get("name")
		Dim NextDirection As String = IIf(SortColumn = ColumnName And SortDirection = "ASC", "DESC", "ASC")
		Dim HeaderCell As MiniHtml = NewTag(HeaderRow, "th", "")
		Dim HeaderLink As MiniHtml = NewTag(HeaderCell, "a", "sort-link")
		HeaderLink.attr("href", EscapeHtml(TableUrl(DbName, TableName, 1, ColumnName, NextDirection, SearchText)))
		HeaderLink.text(ColumnName)
		If SortColumn = ColumnName Then AddText(HeaderCell, "span", "sort-state", IIf(SortDirection = "ASC", " ↑", " ↓"))
	Next
	Dim Body As MiniHtml = NewTag(DataGrid, "tbody", "")
	Dim RowsShown As Int
	Dim HasMore As Boolean
	Dim KeyOffset As Int = DataColumns.Size * 3
	Do While Rows.NextRow
		If RowsShown >= PAGE_SIZE Then
			HasMore = True
			Exit
		End If
		Dim Row As MiniHtml = NewTag(Body, "tr", "")
		If Editable Then
			Dim KeyValues As List = ReadRowKeys(Rows, KeyMode, PrimaryKeys, KeyOffset)
			Dim ActionCell As MiniHtml = NewTag(Row, "td", "edit-cell")
			If KeyValues.Size = 0 Then
				AddText(ActionCell, "span", "muted", "—")
			Else
				Dim EditLink As MiniHtml = NewTag(ActionCell, "a", "edit-link")
				EditLink.attr("href", EscapeHtml(EditUrl(DbName, TableName, KeyValues)))
				EditLink.text("Edit")
			End If
		End If
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
		Dim EmptySpan As Int = DataColumns.Size
		If Editable Then EmptySpan = EmptySpan + 1
		EmptyCell.attr("colspan", "" & EmptySpan)
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
			If KeyNumber = Column.Get("pk") Then Primary.Add(Column.Get("name"))
		Next
	Next
	Return Primary
End Sub

Private Sub FindColumn (Columns As List, ColumnName As String) As Int
	For i = 0 To Columns.Size - 1
		Dim Column As Map = Columns.Get(i)
		If ColumnName = Column.Get("name") Then Return i
	Next
	Return -1
End Sub

Private Sub FindColumnIgnoreCase (Columns As List, ColumnName As String) As Int
	For i = 0 To Columns.Size - 1
		Dim Column As Map = Columns.Get(i)
		Dim Existing As String = SafeString(Column.Get("name"), "")
		If Existing.EqualsIgnoreCase(ColumnName) Then Return i
	Next
	Return -1
End Sub

' Prefer primary-key columns; otherwise use an unshadowed rowid alias. BLOB keys are
' not editable through the form because query-string encoding is text-only.
Private Sub BuildKeyPlan (Columns As List, PrimaryKeys As List) As Map
	If PrimaryKeys.Size > 0 Then
		For Each KeyName As String In PrimaryKeys
			Dim KeyIndex As Int = FindColumn(Columns, KeyName)
			If KeyIndex >= 0 Then
				Dim KeyColumn As Map = Columns.Get(KeyIndex)
				Dim Declared As String = SafeUpper(KeyColumn.Get("type"))
				If Declared.Contains("BLOB") Then Return CreateMap("mode": "", "rowid": "")
			End If
		Next
		Return CreateMap("mode": "pk", "rowid": "")
	End If
	Dim Alias As String = RowidAlias(Columns)
	If Alias = "" Then Return CreateMap("mode": "", "rowid": "")
	Return CreateMap("mode": "rowid", "rowid": Alias)
End Sub

Private Sub RowidAlias (Columns As List) As String
	For Each Candidate As String In Array As String("_rowid_", "rowid", "oid")
		If FindColumnIgnoreCase(Columns, Candidate) = -1 Then Return Candidate
	Next
	Return ""
End Sub

Private Sub ReadRowKeys (Rows As ResultSet, KeyMode As String, PrimaryKeys As List, KeyOffset As Int) As List
	Dim Values As List
	Values.Initialize
	If KeyMode = "rowid" Then
		Dim RowidValue As String = Rows.GetString2(KeyOffset)
		If RowidValue <> Null And RowidValue <> "" Then Values.Add(RowidValue)
		Return Values
	End If
	For i = 0 To PrimaryKeys.Size - 1
		Dim KeyValue As String = Rows.GetString2(KeyOffset + i)
		If KeyValue = Null Then
			Dim Empty As List
			Empty.Initialize
			Return Empty
		End If
		Values.Add(KeyValue)
	Next
	Return Values
End Sub

Private Sub EditUrl (DbName As String, TableName As String, KeyValues As List) As String
	Dim Url As String = AsadiState.BasePath & "/db/" & DbName & "/edit?table=" & EncodeQuery(TableName)
	For i = 0 To KeyValues.Size - 1
		Dim Value As String = KeyValues.Get(i)
		If Value = Null Then
			Url = Url & "&kn" & i & "=1"
		Else
			Url = Url & "&k" & i & "=" & EncodeQuery(Value)
		End If
	Next
	Return Url
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
		SortColumn As String, SortDirection As String, Page As Int, Editable As Boolean, KeyMode As String, RowidExpr As String) As String
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
	' Keys trail the display/type/length projection so the grid loop can read them by offset.
	If Editable Then
		If KeyMode = "rowid" Then
			Query.Append(", ").Append(RowidExpr)
		Else
			For Each PrimaryKey As String In PrimaryKeys
				Query.Append(", ").Append(QuoteIdentifier(PrimaryKey))
			Next
		End If
	End If
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

Private Sub ExportUrl (DbName As String, TableName As String, Format As String) As String
	Return AsadiState.BasePath & "/db/" & DbName & "/export?table=" & EncodeQuery(TableName) & "&format=" & Format
End Sub

Private Sub EncodeQuery (Value As String) As String
	Dim Encoder As JavaObject
	Encoder.InitializeStatic("java.net.URLEncoder")
	Dim Encoded As String = Encoder.RunMethod("encode", Array(Value, "UTF-8"))
	Return Encoded.Replace("+", "%20")
End Sub

Private Sub AddSchemaSection (Parent As MiniHtml, Columns As List, ForeignKeys As List, Indexes As List, Definition As String)
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
		If 1 = Column.Get("notnull") Then Nullable = "NO"
		Dim KeyLabel As String = ""
		If 0 < Column.Get("pk") Then KeyLabel = "PK " & Column.Get("pk")
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
			If 1 = Index.Get("unique") Then UniqueLabel = " · unique"
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
		If ColumnName = Foreign.Get("from") Then
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

' B4J cannot reliably chain a member call directly onto a function result, so the
' upper/lower normalisation lives in its own routine with a local variable.
Private Sub SafeUpper (Value As Object) As String
	Dim Text As String = SafeString(Value, "")
	Return Text.ToUpperCase
End Sub

Private Sub SafeLower (Value As Object) As String
	Dim Text As String = SafeString(Value, "")
	Return Text.ToLowerCase
End Sub

' jServer returns an empty string for an absent request parameter, so presence must be
' checked against the parameter map. Missing fields are skipped instead of blanked.
Private Sub HasParameter (req As ServletRequest, Name As String) As Boolean
	Dim Params As Map = req.ParameterMap
	If Params = Null Then Return False
	Return Params.ContainsKey(Name)
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
			Log(LastException.Message)
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
	PageTitle.text(Title & " · Pakai Asadi")
	Dim Style As MiniHtml = NewTag(Head, "style", "")
	Style.text(GetStyles, True, False)
	Style.text(GetTableStyles, True, False)
	Dim Body As MiniHtml = NewTag(Html, "body", "")
	Dim Sidebar As MiniHtml = NewTag(Body, "aside", "sidebar")
	Dim Brand As MiniHtml = NewTag(Sidebar, "a", "brand")
	Brand.attr("href", AsadiState.BasePath)
	AddText(Brand, "span", "brand-mark", "P")
	AddText(Brand, "span", "", "pakai asadi")
	AddText(Sidebar, "div", "nav-label", "WORKSPACE")
	Dim Nav As MiniHtml = NewTag(Sidebar, "a", "nav-item active")
	Nav.attr("href", AsadiState.BasePath)
	Nav.text("▦  Databases")
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
	Dim ModeBadge As MiniHtml = NewTag(Topbar, "span", "readonly")
	ModeBadge.text("♟  Read and write")
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
		Link.text("▤  " & Name)
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
	Style.text("body{font:16px system-ui;background:#f5f7fb;color:#172033;padding:10vh 8vw}.error-card{max-width:620px;margin:auto;background:white;border:1px solid #e5eaf1;border-radius:18px;padding:40px}.eyebrow{color:#4263eb;font-weight:700;letter-spacing:.12em}.muted{color:#68748a}", True, False)
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
	Tag.text(Value)
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

Private Sub GetStyles As String
	Return ":root{--ink:#182235;--muted:#778398;--line:#e8edf3;--blue:#4263eb;--bg:#f7f9fc;--surface:#fff;--sidebar:#101a2c;--green:#34c98b}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px system-ui,-apple-system,'Segoe UI',sans-serif;min-height:100vh}.sidebar{position:fixed;inset:0 auto 0 0;width:240px;background:var(--sidebar);color:#fff;padding:24px 16px;display:flex;flex-direction:column}.brand{height:42px;display:flex;align-items:center;gap:11px;color:#fff;text-decoration:none;font-weight:700;padding:0 9px}.brand-mark{display:grid;place-items:center;width:28px;height:28px;background:#4263eb;border-radius:9px}.nav-label{font-size:10px;font-weight:700;letter-spacing:.13em;color:#8290a8;margin:34px 10px 10px}.nav-item,.side-db{display:block;text-decoration:none;color:#cbd4e2;border-radius:9px;padding:11px 12px;font-weight:600}.nav-item.active{background:#202e48}.side-db{font-size:13px;font-weight:500;color:#aab6c9;padding:9px 12px}.sidebar-foot{margin-top:auto;border-top:1px solid #263249;padding:17px 10px 0;color:#aab6c9;font-size:11px}.status-dot{display:inline-block;width:7px;height:7px;border-radius:50%;background:var(--green);margin-right:8px}.main{margin-left:240px;min-height:100vh}.topbar{height:64px;background:var(--surface);border-bottom:1px solid var(--line);display:flex;align-items:center;justify-content:space-between;padding:0 36px;color:#778398}.topbar strong{color:var(--ink)}.slash{padding:0 10px;color:#c4ccd7}.readonly{font-size:11px;color:#66758d;background:#f1f4f8;border:1px solid var(--line);border-radius:20px;padding:7px 11px}.content{max-width:1100px;padding:44px 40px;margin:auto}.eyebrow{font-size:10px;font-weight:700;letter-spacing:.15em;color:var(--blue)}h1{font-size:30px;letter-spacing:-.04em;margin:10px 0 6px}.muted{color:var(--muted);line-height:1.6}.db-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:14px;margin-top:28px}.db-card{position:relative;background:var(--surface);border:1px solid var(--line);border-radius:13px;padding:20px;text-decoration:none;color:var(--ink);display:grid;grid-template-columns:34px 1fr;align-items:center}.db-card:hover{border-color:#aabaff}.db-icon{width:32px;height:32px;display:grid;place-items:center;background:#eef1ff;color:var(--blue);border-radius:9px;grid-row:span 2}.db-name{font-weight:700;padding-left:12px}.db-meta{font-size:11px;color:var(--muted);padding:5px 0 0 12px}.card-arrow{position:absolute;right:17px;top:17px;color:#9aa6b8}.empty{margin-top:28px;background:var(--surface);border:1px dashed #d6deea;border-radius:14px;text-align:center;padding:45px 20px}.empty h2{font-size:17px}.empty p{color:var(--muted)}.empty-icon{margin:auto auto 14px;width:44px;height:44px;display:grid;place-items:center;border-radius:13px;background:#eef1ff;color:var(--blue);font-size:23px}.back{display:inline-block;text-decoration:none;color:#5d6c83;font-weight:600;margin:0 0 24px}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:26px 0}.stat{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:16px;display:flex;flex-direction:column}.stat-label,.stat-foot{font-size:11px;color:var(--muted)}.stat strong{font-size:25px;margin:8px 0}.objects{background:var(--surface);border:1px solid var(--line);border-radius:13px;overflow:hidden}.section-head{display:flex;justify-content:space-between;padding:18px 20px;border-bottom:1px solid var(--line)}.section-head h2{font-size:17px;margin:0}.count,.object-type{background:#f0f3f8;border-radius:14px;color:#718098;font-size:11px;padding:4px 9px}.object-row{min-height:49px;display:flex;align-items:center;padding:0 20px;border-bottom:1px solid #f0f2f6;gap:12px}.object-symbol{color:#70819c}.object-title{font-weight:600;flex:1}.object-type{font-size:10px}.content footer{margin-top:60px;padding:15px 0;color:#a2acba;font-size:9px;letter-spacing:.1em;font-weight:700}.note{padding:0 20px 12px}@media(max-width:850px){.sidebar{width:200px}.main{margin-left:200px}.content{padding:34px 24px}.topbar{padding:0 22px}.stats{grid-template-columns:repeat(2,1fr)}}@media(max-width:600px){.sidebar{position:relative;width:auto;height:auto;padding:12px;display:block}.nav-label,.side-db,.sidebar-foot{display:none}.nav-item{margin-top:8px}.main{margin-left:0}.topbar{height:54px;padding:0 14px}.readonly{font-size:0;padding:7px}.content{padding:28px 15px}h1{font-size:25px}.db-grid{grid-template-columns:1fr}.stats{gap:8px}.stat{padding:12px}}@media(prefers-reduced-motion:reduce){*{transition:none!important}}@media(prefers-color-scheme:dark){:root{--ink:#e5eaf3;--muted:#9aa7bb;--line:#293449;--bg:#101827;--surface:#172235}.readonly,.count,.object-type{background:#202d42;color:#a9b8d1}.db-icon,.empty-icon{background:#242f50}.object-row{border-color:#243147}.empty{border-color:#35425a}}"
End Sub

Private Sub GetTableStyles As String
	Return ".table-search{display:flex;gap:8px;margin:20px 0}.search-input{flex:1;min-width:130px;border:1px solid var(--line);border-radius:8px;padding:10px 12px;background:var(--surface);color:var(--ink)}.btn-search,.page-link{border:1px solid var(--line);border-radius:8px;background:var(--surface);color:var(--ink);padding:9px 13px;text-decoration:none;cursor:pointer}.clear-search{padding:10px;color:var(--blue)}.table-scroll{overflow:auto;max-width:100%;background:var(--surface);border:1px solid var(--line);border-radius:12px}.table-workspace>.table-scroll{max-height:68vh}.data-grid,.schema-grid{border-collapse:separate;border-spacing:0;width:100%;white-space:nowrap}.object-title{color:var(--ink);text-decoration:none}.object-title:hover,.object-title:focus{color:var(--blue);text-decoration:underline}.data-grid th,.schema-grid th{position:sticky;top:0;background:#f1f4f8;text-align:left;font-size:11px;color:#62718a;padding:11px 13px;border-bottom:1px solid var(--line);z-index:1}.data-grid td,.schema-grid td{padding:10px 13px;border-bottom:1px solid #edf0f4;white-space:nowrap}.data-grid tr:last-child td,.schema-grid tr:last-child td{border-bottom:0}.sort-link{color:inherit;text-decoration:none}.sort-link:hover,.sort-link:focus,.page-link:hover,.page-link:focus{color:var(--blue);outline:2px solid #aabaff;outline-offset:2px}.sort-state{color:var(--blue);font-size:10px}.null-value,.blob-value{display:inline-block;border-radius:5px;background:#f0f3f8;color:#718098;padding:3px 6px;font-size:10px}.cell-value,.large-value{display:inline-block;max-width:280px;overflow:hidden;text-overflow:ellipsis;vertical-align:bottom}.pagination{display:flex;gap:12px;align-items:center;justify-content:flex-end;margin:14px 0}.page-state,.info-note{font-size:12px;color:var(--muted)}.schema-section{margin:18px 0;background:var(--surface);border:1px solid var(--line);border-radius:12px}.schema-section>summary,.schema-subsection>summary{cursor:pointer;padding:14px 18px;color:var(--ink)}.schema-grid{font-size:12px}.schema-subsection{padding:12px 18px;border-top:1px solid var(--line)}.schema-subsection h3{font-size:13px}.schema-detail{padding:5px 0;color:var(--muted)}.sql-code{white-space:pre-wrap;overflow-wrap:anywhere;background:#f4f6fa;padding:14px;border-radius:8px;color:#34435a}.empty-cell{text-align:center!important;color:var(--muted);padding:30px!important}@media(max-width:600px){.table-search{flex-wrap:wrap}.pagination{justify-content:center}.data-grid td,.data-grid th{padding:8px}.schema-section{overflow:hidden}}@media(prefers-color-scheme:dark){.data-grid th,.schema-grid th,.null-value,.blob-value{background:#202d42;color:#a9b8d1}.data-grid td,.schema-grid td{border-color:#243147}.sql-code{background:#101827;color:#d1d9e6}.search-input,.btn-search,.page-link{background:var(--surface);color:var(--ink)}}.page-actions{display:flex;gap:8px;flex-wrap:wrap;margin:16px 0 0}.action-link{display:inline-block;background:var(--blue);color:#fff;text-decoration:none;font-weight:600;border-radius:8px;padding:9px 14px}.action-link:hover,.action-link:focus{background:#3350d6;outline:2px solid #aabaff;outline-offset:2px}.action-link.secondary{background:transparent;color:var(--blue);border:1px solid #b9c5f8}.action-link.secondary:hover,.action-link.secondary:focus{background:#eef1ff}.crumb{display:flex;align-items:center;gap:8px;font-size:13px;color:var(--muted)}.crumb .slash{color:#c3cddd}.crumb strong{color:var(--ink)}.edit-form{display:flex;flex-direction:column;gap:18px;margin-top:26px;max-width:760px}.edit-field{display:flex;flex-direction:column;gap:6px}.edit-label{font-size:12px;font-weight:700;color:#506079}.edit-input{width:100%;font:inherit;font-size:14px;line-height:1.45;color:var(--ink);background:var(--surface);border:1px solid #d7dfeb;border-radius:9px;padding:10px 12px}.edit-input:focus{outline:2px solid #aabaff;outline-offset:1px;border-color:#8fa6f8}.edit-textarea{resize:vertical;min-height:88px}.edit-readonly{font-size:13px;color:#5d6c85;background:#f4f7fb;border:1px solid var(--line);border-radius:9px;padding:9px 12px}.null-toggle{display:inline-flex;align-items:center;gap:7px;font-size:12px;color:var(--muted);width:max-content}.field-note{margin:0;font-size:12px;color:var(--muted)}.delete-box{margin-top:44px;padding-top:26px;border-top:1px solid var(--line);max-width:760px}.delete-box h2{font-size:18px;margin:0 0 6px}.btn-danger{display:inline-block;font:inherit;font-size:14px;font-weight:600;color:#b42318;background:var(--surface);border:1px solid #f0b8b3;border-radius:8px;padding:10px 16px;text-decoration:none;cursor:pointer}.btn-danger:hover,.btn-danger:focus{background:#fdf2f1;outline:2px solid #f6c9c5;outline-offset:1px}.modal{display:none;position:fixed;inset:0;z-index:30;padding:24px;align-items:center;justify-content:center;background:rgba(15,23,42,.55)}.modal:target{display:flex}.modal-backdrop{position:absolute;inset:0}.modal-panel{position:relative;z-index:1;width:100%;max-width:460px;background:var(--surface);border:1px solid var(--line);border-radius:14px;padding:22px 24px;box-shadow:0 24px 60px rgba(15,23,42,.28)}.modal-panel h2{margin:0 0 8px;font-size:19px}.modal-panel p{margin:0 0 4px;font-size:13px;line-height:1.55}.modal-actions{display:flex;gap:10px;justify-content:flex-end;margin-top:20px}.btn-secondary{display:inline-block;font:inherit;font-size:14px;font-weight:600;color:var(--ink);background:var(--surface);border:1px solid var(--line);border-radius:8px;padding:10px 16px;text-decoration:none;cursor:pointer}.btn-secondary:hover,.btn-secondary:focus{background:#eef1f7;outline:2px solid #aabaff;outline-offset:1px}.edit-link{color:var(--blue);font-weight:600;font-size:12px;text-decoration:none}.edit-link:hover,.edit-link:focus{text-decoration:underline}.sql-form{margin:22px 0}.sql-input{width:100%;min-height:170px;padding:14px 16px;border:1px solid var(--line);border-radius:10px;background:var(--surface);color:var(--ink);font:13px/1.55 ui-monospace,SFMono-Regular,Consolas,monospace;resize:vertical}.sql-actions{display:flex;align-items:center;gap:14px;margin-top:10px;flex-wrap:wrap}.btn-primary{border:0;border-radius:8px;background:var(--blue);color:#fff;padding:10px 16px;font-weight:600;cursor:pointer}.btn-primary:hover,.btn-primary:focus{background:#3350d6;outline:2px solid #aabaff;outline-offset:2px}.sql-hint,.sql-meta{font-size:12px;color:var(--muted)}.sql-meta{display:flex;gap:14px;align-items:center;flex-wrap:wrap;margin:18px 0 8px}.sql-error{margin:18px 0;padding:16px 18px;border:1px solid #e3a3a3;border-left:4px solid #d64545;background:var(--surface);border-radius:10px}.sql-error strong{display:block;margin-bottom:8px;color:#d64545}.sql-error .sql-code{margin:0;white-space:pre-wrap;word-break:break-word}.sql-workspace>.table-scroll{max-height:60vh}"
End Sub
