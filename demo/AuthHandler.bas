B4J=true
Group=Handlers
ModulesStructureVersion=1
Type=Class
Version=10.7
@EndOfDesignText@
' Auth Handler
' Version 0.30
Sub Class_Globals
	Private App As EndsMeet
	Private View As AuthView
	Private Model As AuthModel
	Private Request As ServletRequest
	Private Response As ServletResponse
End Sub

Public Sub Initialize
	App = Main.App
	View.Initialize
	Model.Initialize
End Sub

Sub Handle (req As ServletRequest, resp As ServletResponse)
	Request = req
	Response = resp
	Dim Path As String = Request.RequestURI
	Dim Method As String = Request.Method.ToUpperCase
	Log($"${Method}: ${Path}"$)
	If Path = "/login" Then
		If Method = "GET" Then
			ShowLoginPage("")
		Else
			HandleLogin
		End If
	Else If Path = "/register" Then
		If Method = "GET" Then
			ShowRegisterPage("")
		Else
			HandleRegister
		End If
	Else If Path = "/logout" Then
		HandleLogout
	End If
End Sub

Private Sub ShowLoginPage (Message As String)
	App.WriteHtml2(Response, View.Login(Message).build, App.ctx)
End Sub

Private Sub ShowRegisterPage (Message As String)
	App.WriteHtml2(Response, View.Register(Message).build, App.ctx)
End Sub

Private Sub HandleLogin
	Dim user As String = Request.GetParameter("username")
	Dim pass As String = Request.GetParameter("password")
	
	Dim row As Map = Model.GetRowByUsername(user)
	If Model.Error.IsInitialized Then
		ShowRegisterPage("Error creating user: " & Model.Error.Message)
		'ShowAlert(Model.Error.Message, "danger")
		Return
	End If
	If row.Size > 0 Then
		If row.Get("password") = pass Then ' Simple check for now
			Request.GetSession.SetAttribute("user", user)
			Request.GetSession.SetAttribute("role", row.Get("role"))
			Response.SendRedirect("/")
			Return
		End If
	End If
	
	ShowLoginPage("Invalid username or password")
End Sub

Private Sub HandleRegister
	Dim user As String = Request.GetParameter("username")
	Dim email As String = Request.GetParameter("email")
	Dim pass As String = Request.GetParameter("password")
	
	Dim Found As Boolean = Model.FindRowByUsername(user)
	If Model.Error.IsInitialized Then
		ShowRegisterPage("Error creating user: " & Model.Error.Message)
		'ShowAlert(Model.Error.Message, "danger")
		Return
	End If
	
	If Found Then
		ShowRegisterPage("Username already exists")
		Return
	End If
	
	Model.Create(user, email, pass, "user")
	If Model.Error.IsInitialized Then
		ShowRegisterPage("Error creating user: " & Model.Error.Message)
		Return
	End If
	
	Response.SendRedirect("/login")
End Sub

Private Sub HandleLogout
	Request.GetSession.Invalidate
	Response.SendRedirect("/login")
End Sub

'Private Sub ShowAlert (Message As String, Status As String)
'	Dim info As AlertInfo = Main.CreateAlertInfo(Message, Status)
'	App.WriteHtml(Response, View.Alert(info))
'End Sub
