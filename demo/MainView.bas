B4J=true
Group=Views
ModulesStructureVersion=1
Type=Class
Version=10.7
@EndOfDesignText@
' Main View
' Version 7.00
' Builds the Pakai Asadi application shell with PakaiUI components and the
' optional pakaiui-asadi.css theme layer.
Sub Class_Globals
	Private mModal As MiniHtml
	Private mToast As MiniHtml
	Private mContent As MiniHtml
	Private mPageTitle As String
	Private mPageSubtitle As String
	Private mActiveKey As String
	Private App As EndsMeet
	Private Const BootstrapVersion As String = "5.3.8"
	Private Const IconsVersion As String = "1.13.1"
End Sub

Public Sub Initialize
	App = Main.App
End Sub

' Sets the page heading and the sidebar item that should be highlighted.
Public Sub LoadPage (Title As String, Subtitle As String, ActiveKey As String)
	mPageTitle = Title
	mPageSubtitle = Subtitle
	mActiveKey = ActiveKey
End Sub

Public Sub LoadContent (Tag1 As MiniHtml)
	mContent = Tag1
End Sub

Public Sub LoadModal (Tag1 As MiniHtml)
	mModal = Tag1
End Sub

Public Sub LoadToast (Tag1 As MiniHtml)
	mToast = Tag1
End Sub

Public Sub Render As MiniHtml
	Dim pageOptions As PUIPageOptions = PUI.NewPageOptions("$APP_TITLE$")
	pageOptions.Description = "Pakai Asadi SQLite workspace"
	pageOptions.BodyCssClass = "pui-asadi"
	Dim page1 As MiniHtml = PUI.Document(pageOptions)

	Dim head1 As MiniHtml = PUI.Head(page1)
	PUI.StyleSheet(head1, "/assets/css/bootstrap.min.css?v=" & BootstrapVersion)
	PUI.StyleSheet(head1, "/assets/css/bootstrap-icons.min.css?v=" & IconsVersion)
	PUI.StyleSheet(head1, "/assets/css/pakaiui.css?v=" & PUI.VERSION)
	PUI.StyleSheet(head1, "/assets/css/pakaiui-asadi.css?v=" & PUI.VERSION)
	Dim icon1 As MiniHtml = Tag("link")
	icon1.attr("rel", "icon")
	icon1.attr("type", "image/png")
	icon1.attr("href", "/assets/img/favicon.png")
	icon1.up(head1)

	Dim body1 As MiniHtml = PUI.Body(page1)
	AddSidebar(body1)

	Dim main1 As MiniHtml = Tag("div").cls("pui-asadi-main")
	main1.up(body1)
	AddTopbar(main1)

	Dim content1 As MiniHtml = Tag("div").cls("pui-asadi-content")
	content1.up(main1)
	AddHeader(content1)
	If Initialized(mContent) Then mContent.up(content1)
	AddFooter(content1)

	If Initialized(mToast) Then mToast.up(body1)
	If Initialized(mModal) Then mModal.up(body1)
	AddScripts(body1)
	Return page1
End Sub

Private Sub AddScripts (Parent As MiniHtml)
	PUI.Script(Parent, "/assets/js/bootstrap.min.js", False)
	PUI.Script(Parent, "/assets/js/htmx.min.js", False)
	PUI.Script(Parent, "/assets/js/app.js", False)
End Sub

Private Sub AddSidebar (Parent As MiniHtml)
	Dim sideOptions As PUISidebarOptions = PUI.NewSidebarOptions("$APP_TITLE$")
	sideOptions.Href = "/"
	sideOptions.Title = "WORKSPACE"
	sideOptions.Border = False
	sideOptions.CssClass = "pui-asadi-sidebar"
	sideOptions.Items.Add(MakeNavItem("Products", "/", "products"))
	sideOptions.Items.Add(MakeNavItem("Categories", "/categories", "categories"))
	sideOptions.Items.Add(MakeNavItem("SQL admin", "/asadi", "asadi"))
	If App.api.EnableHelp Then sideOptions.Items.Add(MakeNavItem("API reference", "/help", "api"))
	Dim side1 As MiniHtml = PUI.Sidebar(sideOptions)
	side1.up(Parent)

	Dim foot1 As MiniHtml = Tag("div").cls("pui-asadi-sidefoot")
	foot1.up(side1)
	Tag("span").cls("status-dot").up(foot1)
	PUI.AddText(foot1, " SQLite workspace")
End Sub

Private Sub AddTopbar (Parent As MiniHtml)
	Dim bar1 As MiniHtml = Tag("header").cls("pui-asadi-topbar")
	bar1.up(Parent)

	Dim crumbOptions As PUIBreadcrumbOptions = PUI.NewBreadcrumbOptions
	crumbOptions.CssClass = "pui-asadi-crumb"
	crumbOptions.Items.Add(PUI.NewBreadcrumbItem("Workspace", "/"))
	Dim currentCrumb As PUIBreadcrumbItem = PUI.NewBreadcrumbItem(mPageTitle, "")
	currentCrumb.Active = True
	crumbOptions.Items.Add(currentCrumb)
	PUI.Breadcrumb(crumbOptions).up(bar1)

	Dim actions1 As MiniHtml = Tag("div").cls("pui-asadi-topbar-actions")
	actions1.up(bar1)
	Dim badgeOptions As PUIBadgeOptions = PUI.NewBadgeOptions("Demo")
	badgeOptions.Variant = PUI.VariantLight
	badgeOptions.CssClass = "pui-asadi-readonly"
	PUI.Badge(badgeOptions).up(actions1)

	Dim logoutOptions As PUIButtonOptions = PUI.NewButtonOptions("Log out")
	logoutOptions.Href = "/logout"
	logoutOptions.Variant = PUI.VariantOutlineSecondary
	logoutOptions.Size = PUI.SizeSmall
	PUI.Button(logoutOptions).up(actions1)
End Sub

Private Sub AddHeader (Parent As MiniHtml)
	If mPageTitle = "" Then Return
	Dim eyebrow1 As MiniHtml = Tag("div").cls("pui-asadi-eyebrow")
	eyebrow1.up(Parent)
	PUI.AddText(eyebrow1, "PAKAI ASADI")

	Dim headerOptions As PUIPageHeaderOptions = PUI.NewPageHeaderOptions(mPageTitle)
	headerOptions.Subtitle = mPageSubtitle
	headerOptions.CssClass = "pui-asadi-pageheader"
	PUI.PageHeader(headerOptions).up(Parent)
End Sub

Private Sub AddFooter (Parent As MiniHtml)
	Dim footer1 As MiniHtml = Tag("footer").cls("pui-asadi-footer")
	footer1.up(Parent)
	PUI.AddText(footer1, "Pakai Asadi " & Main.APP_VERSION & " - PakaiUI " & PUI.VERSION & " - Bootstrap " & BootstrapVersion)
End Sub

Private Sub MakeNavItem (Text As String, Href As String, Key As String) As PUINavItemOptions
	Dim item1 As PUINavItemOptions = PUI.NewNavItemOptions(Text, Href)
	If Key = mActiveKey Then item1.Active = True
	Return item1
End Sub

Private Sub Tag (Name As String) As MiniHtml
	Dim tag1 As MiniHtml
	tag1.Initialize(Name)
	Return tag1
End Sub
