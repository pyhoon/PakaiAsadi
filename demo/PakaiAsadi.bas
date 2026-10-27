B4J=true
Group=Classes
ModulesStructureVersion=1
Type=Class
Version=10.7
@EndOfDesignText@
' Embedded Pakai Asadi configuration and EndsMeet route integration.
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
	If HostApp.IsInitialized = False Then Return
	mApp = HostApp
	mBasePath = "/asadi"
	mAuthorizationSub = AuthorizationSub.Trim
	If mAuthorizationSub = "" Or SubExists(Main, mAuthorizationSub) = False Then
		Log("PakaiAsadi: missing host authorization sub; routes will not be registered")
		Return
	End If
	Try
		mAllowedDirectory = CanonicalPath(AllowedDirectory)
		Dim DirFile As JavaObject
		DirFile.InitializeNewInstance("java.io.File", Array(mAllowedDirectory))
		If DirFile.RunMethod("isDirectory", Null) = False Then Return
	Catch
		Return
	End Try
	AsadiState.InitializeState(mApp, mBasePath, mAllowedDirectory, mAuthorizationSub)
	AsadiState.Configured = True
	mInitialized = True
End Sub

Public Sub setBasePath (Value As String)
	If mStarted Then Return
	Dim Candidate As String = Value.Trim
	If Candidate.StartsWith("/") = False Then Candidate = "/" & Candidate
	Do While Candidate.Length > 1 And Candidate.EndsWith("/")
		Candidate = Candidate.SubString2(0, Candidate.Length - 1)
	Loop
	If Candidate = "/" Or Regex.IsMatch("^/[A-Za-z0-9/_-]+$", Candidate) = False Or Candidate.Contains("//") Or Candidate.Contains("..") Then
		mConfigurationValid = False
		Return
	End If
	mBasePath = Candidate
	If mInitialized Then AsadiState.SetBasePath(mBasePath)
End Sub

Public Sub getBasePath As String
	Return mBasePath
End Sub

Public Sub AddDatabase (Name As String, DatabasePath As String) As Boolean
	If mInitialized = False Or mStarted Then Return False
	If Regex.IsMatch("^[A-Za-z][A-Za-z0-9_-]{0,63}$", Name) = False Then Return False
	If AsadiState.Databases.ContainsKey(Name) Then Return False
	Try
		Dim Canonical As String = CanonicalPath(DatabasePath)
		If Canonical.Contains("?") Or AsadiState.IsAllowedCanonicalPath(Canonical) = False Then Return False
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
	If SubExists(Main, mAuthorizationSub) = False Or HasRouteCollision Then Return False
	mApp.Get(mBasePath, "AsadiHandler")
	mApp.Get(mBasePath & "/*", "AsadiHandler")
	mStarted = True
	Return True
End Sub

Private Sub HasRouteCollision As Boolean
	For Each Existing As Object In mApp.routes
		Try
			Dim R As JavaObject = Existing
			Dim P As String = R.GetField("Path")
			If P = mBasePath Or P = mBasePath & "/*" Or P.StartsWith(mBasePath & "/") Then Return True
			If P.EndsWith("/*") Then
				Dim Prefix As String = P.SubString2(0, P.Length - 2)
				If mBasePath = Prefix Or mBasePath.StartsWith(Prefix & "/") Then Return True
			End If
		Catch
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
