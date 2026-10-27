B4J=true
Group=Classes
ModulesStructureVersion=1
Type=Class
Version=10.7
@EndOfDesignText@
' Pakai Asadi public integration class.
' Start registers GET handlers only; it never starts the host server.
Sub Class_Globals
	Private mApp As EndsMeet
	Private mBasePath As String
	Private mAllowedDirectory As String
	Private mAuthorizationSub As String
	Private mInitialized As Boolean
	Private mStarted As Boolean
	Private mConfigurationValid As Boolean
End Sub

Public Sub Initialize (HostApp As EndsMeet, AllowedDirectory As String, AuthorizationSub As String)
	If mInitialized Or AsadiState.Configured Then
		Log("PakaiAsadi: only one configured instance is supported per host process")
		Return
	End If
	mInitialized = False
	mStarted = False
	mConfigurationValid = True
	If HostApp.IsInitialized = False Then
		Log("PakaiAsadi: EndsMeet host app is not initialized")
		Return
	End If
	mApp = HostApp
	mBasePath = "/asadi"
	mAuthorizationSub = AuthorizationSub.Trim
	If mAuthorizationSub = "" Or SubExists(Main, mAuthorizationSub) = False Then
		Log("PakaiAsadi: missing host authorization sub; Asadi routes will not be registered")
		Return
	End If
	Try
		mAllowedDirectory = CanonicalPath(AllowedDirectory)
		Dim DirFile As JavaObject
		DirFile.InitializeNewInstance("java.io.File", Array(mAllowedDirectory))
		If DirFile.RunMethod("isDirectory", Null) = False Then
			Log("PakaiAsadi: configured database directory is invalid")
			Return
		End If
	Catch
		Log("PakaiAsadi: unable to validate configured database directory")
		Return
	End Try
	AsadiState.InitializeState(mApp, mBasePath, mAllowedDirectory, mAuthorizationSub)
	AsadiState.Configured = True
	mInitialized = True
End Sub

' Configure a URL prefix before Start. Must be an absolute path without query/fragment.
Public Sub setBasePath (Value As String)
	If mStarted Then
		Log("PakaiAsadi: BasePath cannot change after Start")
		Return
	End If
	Dim Candidate As String = Value.Trim
	If Candidate.StartsWith("/") = False Then Candidate = "/" & Candidate
	Do While Candidate.Length > 1 And Candidate.EndsWith("/")
		Candidate = Candidate.SubString2(0, Candidate.Length - 1)
	Loop
	If Candidate = "/" Or Regex.IsMatch("^/[A-Za-z0-9/_-]+$", Candidate) = False Or Candidate.Contains("//") Or Candidate.Contains("..") Then
		Log("PakaiAsadi: invalid BasePath")
		mConfigurationValid = False
		Return
	End If
	mBasePath = Candidate
	If mInitialized Then AsadiState.SetBasePath(mBasePath)
End Sub

Public Sub getBasePath As String
	Return mBasePath
End Sub

' Register an existing SQLite file by logical name. The path must resolve under AllowedDirectory.
Public Sub AddDatabase (Name As String, DatabasePath As String) As Boolean
	If mInitialized = False Or mStarted Then Return False
	If Regex.IsMatch("^[A-Za-z][A-Za-z0-9_-]{0,63}$", Name) = False Then Return False
	If AsadiState.Databases.ContainsKey(Name) Then Return False
	Try
		Dim Canonical As String = CanonicalPath(DatabasePath)
		If Canonical.Contains("?") Then Return False
		If AsadiState.IsAllowedCanonicalPath(Canonical) = False Then Return False
		Dim DbFile As JavaObject
		DbFile.InitializeNewInstance("java.io.File", Array(Canonical))
		If DbFile.RunMethod("isFile", Null) = False Or DbFile.RunMethod("canRead", Null) = False Then Return False
		AsadiState.Databases.Put(Name, Canonical)
		Return True
	Catch
		Log("PakaiAsadi: database registration rejected")
		Return False
	End Try
End Sub

Public Sub Start As Boolean
	If mInitialized = False Or mStarted Or mConfigurationValid = False Then Return False
	If SubExists(Main, mAuthorizationSub) = False Then Return False
	If HasRouteCollision Then
		Log("PakaiAsadi: configured BasePath overlaps an existing EndsMeet route")
		Return False
	End If
	' Register only after configuration and database allowlist are complete.
	mApp.Get(mBasePath, "AsadiHandler")
	mApp.Get(mBasePath & "/*", "AsadiHandler")
	mStarted = True
	Return True
End Sub

Private Sub HasRouteCollision As Boolean
	For Each Existing As Object In mApp.routes
		Try
			Dim RouteObject As JavaObject = Existing
			Dim ExistingPath As String = RouteObject.GetField("Path")
			If ExistingPath = mBasePath Or ExistingPath = mBasePath & "/*" Then Return True
			If ExistingPath.StartsWith(mBasePath & "/") Then Return True
			If ExistingPath.EndsWith("/*") Then
				Dim ExistingPrefix As String = ExistingPath.SubString2(0, ExistingPath.Length - 2)
				If mBasePath = ExistingPrefix Or mBasePath.StartsWith(ExistingPrefix & "/") Then Return True
			End If
		Catch
			' Fail closed rather than register if the route list cannot be inspected.
			Return True
		End Try
	Next
	Return False
End Sub

Private Sub CanonicalPath (Path As String) As String
	Dim F As JavaObject
	F.InitializeNewInstance("java.io.File", Array(Path))
	Return F.RunMethod("getCanonicalPath", Null)
End Sub
