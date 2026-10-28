B4J=true
Group=Modules
ModulesStructureVersion=1
Type=Code
Version=10.7
@EndOfDesignText@
' Shared configuration for request-scoped EndsMeet handler instances.
Sub Process_Globals
	Public Host As EndsMeet
	Public BasePath As String
	Public AllowedDirectory As String
	Public AuthorizationSub As String
	Public Databases As Map
	Public Configured As Boolean
	' Random per-process key used to sign CSRF tokens. A restart invalidates outstanding tokens.
	Public CsrfSecret As String
End Sub

Public Sub InitializeState (HostApp As EndsMeet, Prefix As String, AllowedDir As String, AuthSub As String)
	Host = HostApp
	BasePath = Prefix
	AllowedDirectory = AllowedDir
	AuthorizationSub = AuthSub
	Databases.Initialize
	CsrfSecret = RandomBase64Url(32)
End Sub

Private Sub RandomBase64Url (ByteCount As Int) As String
	Dim Generator As JavaObject
	Generator.InitializeNewInstance("java.security.SecureRandom", Null)
	Dim Buffer(ByteCount) As Byte
	Generator.RunMethod("nextBytes", Array(Buffer))
	Dim Base64 As JavaObject
	Base64.InitializeStatic("java.util.Base64")
	Dim Encoder As JavaObject = Base64.RunMethodJO("getUrlEncoder", Null)
	Encoder = Encoder.RunMethodJO("withoutPadding", Null)
	Return Encoder.RunMethod("encodeToString", Array(Buffer))
End Sub

Public Sub SetBasePath (Prefix As String)
	BasePath = Prefix
End Sub

Public Sub IsAllowedCanonicalPath (Path As String) As Boolean
	Dim RootPrefix As String = AllowedDirectory
	Dim Sep As String = FileSeparator
	If RootPrefix.EndsWith(Sep) = False Then RootPrefix = RootPrefix & Sep
	Dim Os As JavaObject
	Os.InitializeStatic("java.lang.System")
	Dim OsName As String = Os.RunMethod("getProperty", Array("os.name"))
	If OsName.ToLowerCase.StartsWith("windows") Then
		Return Path.ToLowerCase.StartsWith(RootPrefix.ToLowerCase)
	End If
	Return Path.StartsWith(RootPrefix)
End Sub

Private Sub FileSeparator As String
	Dim F As JavaObject
	F.InitializeStatic("java.io.File")
	Return F.GetField("separator")
End Sub
