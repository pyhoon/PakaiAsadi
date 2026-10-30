B4J=true
Group=Views
ModulesStructureVersion=1
Type=Class
Version=10.7
@EndOfDesignText@
' Categories View
' Version 7.00
' Renders the category list with PakaiUI components and the Asadi theme.
Sub Class_Globals
	
End Sub

Public Sub Initialize
	
End Sub

Public Sub Show (Data As List) As String
	Dim main1 As MainView
	main1.Initialize
	main1.LoadPage("Categories", "Organise the product catalogue by category.", "categories")
	main1.LoadContent(ContainerContent(Data))
	main1.LoadModal(MH.ContainerModal)
	main1.LoadToast(MH.ContainerToast)
	Return main1.Render.build
End Sub

Public Sub Modal (Action As String, Data As Map) As String
	Select Action
		Case "Add"
			Return ModalAdd.build
		Case "Edit"
			Return ModalEdit(Data).build
		Case "Delete"
			Return ModalDelete(Data).build
		Case Else
			Return ""
	End Select
End Sub

Public Sub Alert (info As AlertInfo) As String
	Dim options1 As PUIAlertOptions = PUI.NewAlertOptions(info.Message)
	options1.Variant = info.Status
	Return PUI.Alert(options1).build
End Sub

Public Sub Toast (data As List, info As ToastInfo) As String
	Return MH.Toast("categories-container", CategoriesTableFilled(data), info)
End Sub

Public Sub RenderedTable (data As List) As String
	Return CategoriesTableFilled(data).build
End Sub

Private Sub ContainerContent (Data As List) As MiniHtml
	Dim panel1 As MiniHtml = MH.CreateTag("section").cls("pui-asadi-panel")
	Dim head1 As MiniHtml = MH.CreateTag("div").cls("pui-asadi-panel-head")
	head1.up(panel1)
	Dim title1 As MiniHtml = MH.CreateTag("h2")
	title1.up(head1)
	PUI.AddText(title1, "Category list")
	Dim countOptions As PUIBadgeOptions = PUI.NewBadgeOptions(Data.Size & " rows")
	countOptions.Variant = PUI.VariantLight
	countOptions.CssClass = "pui-asadi-count"
	PUI.Badge(countOptions).up(head1)
	UI.ToolbarButton(head1, "Add category", "/hx/categories/add")

	Dim body1 As MiniHtml = MH.CreateTag("div").cls("pui-asadi-panel-body")
	body1.up(panel1)
	Dim container1 As MiniHtml = MH.CreateTag("div")
	container1.attr("id", "categories-container")
	container1.up(body1)
	CategoriesTableFilled(Data).up(container1)
	Return panel1
End Sub

Public Sub CategoriesTableFilled (data As List) As MiniHtml
	Dim tableOptions As PUITableOptions = PUI.NewTableOptions
	Dim idColumn As PUITableColumn = PUI.NewTableColumn("#", "id")
	idColumn.Align = PUI.AlignEnd
	tableOptions.Columns.Add(idColumn)
	tableOptions.Columns.Add(PUI.NewTableColumn("Name", "category_name"))
	Dim actionsColumn As PUITableColumn = PUI.NewTableColumn("Actions", "")
	actionsColumn.Align = PUI.AlignCenter
	tableOptions.Columns.Add(actionsColumn)
	tableOptions.Rows = data
	tableOptions.RowIdField = "id"
	tableOptions.EmptyText = "No categories yet."
	tableOptions.Hover = True
	tableOptions.CssClass = "pui-asadi-table"
	Dim table1 As MiniHtml = PUI.Table(tableOptions)

	If data.Size > 0 Then
		Dim tableEl As MiniHtml = table1.ChildByClass("table")
		Dim tbody1 As MiniHtml = tableEl.ChildByName("tbody")
		For i = 0 To data.Size - 1
			Dim row1 As Map = data.Get(i)
			Dim tr1 As MiniHtml = tbody1.Children.Get(i)
			Dim td1 As MiniHtml = tr1.Children.Get(tr1.Children.Size - 1)
			td1.cls("text-center text-nowrap")
			UI.RowAction(td1, "Edit", "bi bi-pencil", "/hx/categories/edit/" & row1.Get("id"))
			UI.RowAction(td1, "Delete", "bi bi-trash3", "/hx/categories/delete/" & row1.Get("id"))
		Next
	End If
	Return table1
End Sub

Private Sub ModalAdd As MiniHtml
	Return CategoryForm("Add category", "Create", "post", CreateMap())
End Sub

Private Sub ModalEdit (Data As Map) As MiniHtml
	Return CategoryForm("Edit category", "Update", "put", Data)
End Sub

Private Sub CategoryForm (Title As String, SubmitText As String, Verb As String, Data As Map) As MiniHtml
	Dim form1 As MiniHtml = UI.FormHtmx(Verb, "/hx/categories", "#modal-messages")
	UI.ModalHeader(form1, Title)

	Dim body1 As MiniHtml = MH.CreateTag("div").cls("modal-body")
	body1.up(form1)
	UI.MessageSlot(body1)
	If Data.ContainsKey("id") Then UI.HiddenField(body1, "id", "" & Data.Get("id"))

	Dim nameOptions As PUIInputOptions = PUI.NewInputOptions("Name", "name")
	nameOptions.Required = True
	If Data.ContainsKey("category_name") Then nameOptions.Value = "" & Data.Get("category_name")
	PUI.Input(nameOptions).up(body1)

	Dim submitVariant As String = PUI.VariantPrimary
	If Verb = "post" Then submitVariant = PUI.VariantSuccess
	UI.ModalFooter(form1, SubmitText, submitVariant)
	Return form1
End Sub

Private Sub ModalDelete (Data As Map) As MiniHtml
	Dim form1 As MiniHtml = UI.FormHtmx("delete", "/hx/categories?id=" & Data.Get("id"), "#modal-messages")
	UI.ModalHeader(form1, "Delete category")

	Dim body1 As MiniHtml = MH.CreateTag("div").cls("modal-body")
	body1.up(form1)
	UI.MessageSlot(body1)
	UI.HiddenField(body1, "id", "" & Data.Get("id"))
	Dim text1 As MiniHtml = MH.CreateTag("p")
	text1.up(body1)
	PUI.AddText(text1, "Delete " & Data.Get("category_name") & "?")
	UI.ModalFooter(form1, "Delete", PUI.VariantDanger)
	Return form1
End Sub
