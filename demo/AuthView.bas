B4J=true
Group=Views
ModulesStructureVersion=1
Type=Class
Version=10.7
@EndOfDesignText@
' Auth View
' Version 7.00
' Login and registration pages built with PakaiUI components and the shared
' Asadi authentication layout from pakaiui-asadi.css.
Sub Class_Globals
	Private Const BootstrapVersion As String = "5.3.8"
	Private Const IconsVersion As String = "1.13.1"
End Sub

Public Sub Initialize
	
End Sub

Public Sub Login (Message As String) As MiniHtml
	Return AuthPage("Login", "Sign in to the Pakai Asadi workspace.", "WELCOME BACK", Message, _
		LoginForm, "Don't have an account?", "Register here", "/register")
End Sub

Public Sub Register (Message As String) As MiniHtml
	Return AuthPage("Create account", "Start managing your SQLite workspace.", "GET STARTED", Message, _
		RegisterForm, "Already have an account?", "Login here", "/login")
End Sub

Private Sub AuthPage (Title As String, Subtitle As String, Eyebrow As String, Message As String, _
	Content As MiniHtml, FootPrompt As String, FootLinkText As String, FootHref As String) As MiniHtml

	Dim pageOptions As PUIPageOptions = PUI.NewPageOptions("$APP_TITLE$ - " & Title)
	pageOptions.Description = "Pakai Asadi SQLite workspace"
	pageOptions.BodyCssClass = "pui-asadi"
	Dim page1 As MiniHtml = PUI.Document(pageOptions)

	Dim head1 As MiniHtml = PUI.Head(page1)
	PUI.StyleSheet(head1, "/assets/css/bootstrap.min.css?v=" & BootstrapVersion)
	PUI.StyleSheet(head1, "/assets/css/bootstrap-icons.min.css?v=" & IconsVersion)
	PUI.StyleSheet(head1, "/assets/css/pakaiui.css?v=" & PUI.VERSION)
	PUI.StyleSheet(head1, "/assets/css/pakaiui-asadi.css?v=" & PUI.VERSION)
	Dim icon1 As MiniHtml = MH.CreateTag("link")
	icon1.attr("rel", "icon")
	icon1.attr("type", "image/png")
	icon1.attr("href", "/assets/img/favicon.png")
	icon1.up(head1)

	Dim body1 As MiniHtml = PUI.Body(page1)
	Dim wrap1 As MiniHtml = MH.CreateTag("div").cls("pui-asadi-auth")
	wrap1.up(body1)
	Dim card1 As MiniHtml = MH.CreateTag("div").cls("pui-asadi-auth-card")
	card1.up(wrap1)

	Dim brand1 As MiniHtml = MH.CreateTag("div").cls("pui-asadi-auth-brand")
	brand1.up(card1)
	Dim mark1 As MiniHtml = MH.CreateTag("span").cls("pui-asadi-auth-mark")
	mark1.text("P")
	mark1.up(brand1)
	Dim appName1 As MiniHtml = MH.CreateTag("span")
	appName1.text("$APP_TITLE$")
	appName1.up(brand1)

	Dim eyebrow1 As MiniHtml = MH.CreateTag("div").cls("pui-asadi-auth-eyebrow")
	eyebrow1.text(Eyebrow)
	eyebrow1.up(card1)

	Dim title1 As MiniHtml = MH.CreateTag("h1").cls("pui-asadi-auth-title")
	title1.text(Title)
	title1.up(card1)

	Dim sub1 As MiniHtml = MH.CreateTag("p").cls("pui-asadi-auth-sub")
	sub1.text(Subtitle)
	sub1.up(card1)

	If Message <> "" Then
		Dim alertOptions As PUIAlertOptions = PUI.NewAlertOptions(Message)
		alertOptions.Variant = PUI.VariantDanger
		PUI.Alert(alertOptions).up(card1)
	End If

	Content.up(card1)

	Dim foot1 As MiniHtml = MH.CreateTag("div").cls("pui-asadi-auth-foot")
	foot1.up(card1)
	PUI.AddText(foot1, FootPrompt & " ")
	Dim link1 As MiniHtml = MH.CreateTag("a")
	link1.attr("href", FootHref)
	link1.text(FootLinkText)
	link1.up(foot1)

	Dim meta1 As MiniHtml = MH.CreateTag("div").cls("pui-asadi-auth-meta")
	meta1.up(card1)
	PUI.AddText(meta1, "Pakai Asadi " & Main.APP_VERSION & " - PakaiUI " & PUI.VERSION)
	Return page1
End Sub

Private Sub LoginForm As MiniHtml
	Dim form1 As MiniHtml = Form("/login")
	Dim userOptions As PUIInputOptions = PUI.NewInputOptions("Username", "username")
	userOptions.Required = True
	userOptions.Placeholder = "your username"
	PUI.Input(userOptions).up(form1)

	Dim passOptions As PUIInputOptions = PUI.NewInputOptions("Password", "password")
	passOptions.InputType = "password"
	passOptions.Required = True
	passOptions.Placeholder = "your password"
	PUI.Input(passOptions).up(form1)

	PUI.Button(SubmitButton("Sign in")).up(form1)
	Return form1
End Sub

Private Sub RegisterForm As MiniHtml
	Dim form1 As MiniHtml = Form("/register")
	Dim userOptions As PUIInputOptions = PUI.NewInputOptions("Username", "username")
	userOptions.Required = True
	userOptions.Placeholder = "choose a username"
	PUI.Input(userOptions).up(form1)

	Dim emailOptions As PUIInputOptions = PUI.NewInputOptions("Email", "email")
	emailOptions.InputType = "email"
	emailOptions.Required = True
	emailOptions.Placeholder = "you@example.com"
	PUI.Input(emailOptions).up(form1)

	Dim passOptions As PUIInputOptions = PUI.NewInputOptions("Password", "password")
	passOptions.InputType = "password"
	passOptions.Required = True
	passOptions.Placeholder = "choose a password"
	PUI.Input(passOptions).up(form1)

	PUI.Button(SubmitButton("Create account")).up(form1)
	Return form1
End Sub

Private Sub Form (Action As String) As MiniHtml
	Dim form1 As MiniHtml = MH.CreateTag("form")
	form1.attr("method", "post")
	form1.attr("action", Action)
	Return form1
End Sub

Private Sub SubmitButton (Text As String) As PUIButtonOptions
	Dim options1 As PUIButtonOptions = PUI.NewButtonOptions(Text)
	options1.ButtonType = "submit"
	options1.Variant = PUI.VariantPrimary
	options1.CssClass = "w-100 mt-2"
	Return options1
End Sub
