B4J=true
Group=Views
ModulesStructureVersion=1
Type=Class
Version=10.7
@EndOfDesignText@
' Products View
' Version 7.00
' Renders the product catalogue with PakaiUI components and the Asadi theme.
Sub Class_Globals
	
End Sub

Public Sub Initialize
	
End Sub

Public Sub Show (Data As List) As String
	Dim main1 As MainView
	main1.Initialize
	main1.LoadPage("Products", "Browse, search and maintain the product catalogue.", "products")
	main1.LoadContent(ContainerContent(Data))
	main1.LoadModal(MH.ContainerModal)
	main1.LoadToast(MH.ContainerToast)
	Return main1.Render.build
End Sub

Public Sub Modal (Action As String, CategoryList As List, Data As Map) As String
	Select Action
		Case "Add"
			Return ModalAdd(CategoryList).build
		Case "Edit"
			Return ModalEdit(CategoryList, Data).build
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
	Return MH.Toast("products-container", ProductsTableFilled(data), info)
End Sub

Public Sub RenderedTable (data As List) As String
	Return ProductsTableFilled(data).build
End Sub

Private Sub ContainerContent (Data As List) As MiniHtml
	Dim panel1 As MiniHtml = Tag("section").cls("pui-asadi-panel")
	Dim head1 As MiniHtml = Tag("div").cls("pui-asadi-panel-head")
	head1.up(panel1)
	Dim title1 As MiniHtml = Tag("h2")
	title1.up(head1)
	PUI.AddText(title1, "Product catalogue")
	Dim countOptions As PUIBadgeOptions = PUI.NewBadgeOptions(Data.Size & " rows")
	countOptions.Variant = PUI.VariantLight
	countOptions.CssClass = "pui-asadi-count"
	PUI.Badge(countOptions).up(head1)
	AddProductButton(head1)

	Dim body1 As MiniHtml = Tag("div").cls("pui-asadi-panel-body")
	body1.up(panel1)
	AddFilter(body1)

	Dim container1 As MiniHtml = Tag("div")
	container1.attr("id", "products-container")
	container1.up(body1)
	ProductsTableFilled(Data).up(container1)
	Return panel1
End Sub

Private Sub AddFilter (Parent As MiniHtml)
	Dim filterOptions As PUIFilterBarOptions = PUI.NewFilterBarOptions
	filterOptions.Action = "/hx/products/table"
	filterOptions.Method = "post"
	filterOptions.AriaLabel = "Search products"
	filterOptions.CssClass = "pui-asadi-filters"
	Dim form1 As MiniHtml = PUI.FilterBar(filterOptions)
	form1.up(Parent)
	Dim htmx1 As PUIHtmxOptions = PUI.NewHtmxOptions("/hx/products/table")
	htmx1.Method = "post"
	htmx1.Target = "#products-container"
	htmx1.Swap = "innerHTML"
	PUI.Htmx(form1, htmx1)

	Dim searchOptions As PUIInputOptions = PUI.NewInputOptions("Search", "keyword")
	searchOptions.Placeholder = "Code, name or category"
	searchOptions.CssClass = "col-auto mb-0"
	PUI.Input(searchOptions).up(form1)

	Dim submitOptions As PUIButtonOptions = PUI.NewButtonOptions("Search")
	submitOptions.ButtonType = "submit"
	submitOptions.Variant = PUI.VariantPrimary
	submitOptions.Size = PUI.SizeSmall
	PUI.Button(submitOptions).up(form1)
End Sub

Private Sub AddProductButton (Parent As MiniHtml)
	Dim addOptions As PUIButtonOptions = PUI.NewButtonOptions("Add product")
	addOptions.Variant = PUI.VariantPrimary
	addOptions.Size = PUI.SizeSmall
	Dim add1 As MiniHtml = PUI.Button(addOptions)
	Dim htmx1 As PUIHtmxOptions = PUI.NewHtmxOptions("/hx/products/add")
	htmx1.Target = "#modal-content"
	htmx1.Trigger = "click"
	htmx1.Swap = "innerHTML"
	PUI.Htmx(add1, htmx1)
	add1.attr("data-bs-toggle", "modal")
	add1.attr("data-bs-target", "#modal-container")
	add1.up(Parent)
End Sub

Public Sub ProductsTableFilled (data As List) As MiniHtml
	Dim tableOptions As PUITableOptions = PUI.NewTableOptions
	Dim idColumn As PUITableColumn = PUI.NewTableColumn("#", "id")
	idColumn.Align = PUI.AlignEnd
	tableOptions.Columns.Add(idColumn)
	tableOptions.Columns.Add(PUI.NewTableColumn("Code", "product_code"))
	tableOptions.Columns.Add(PUI.NewTableColumn("Name", "product_name"))
	tableOptions.Columns.Add(PUI.NewTableColumn("Category", "category_name"))
	Dim priceColumn As PUITableColumn = PUI.NewTableColumn("Price", "price_display")
	priceColumn.Align = PUI.AlignEnd
	tableOptions.Columns.Add(priceColumn)
	Dim actionsColumn As PUITableColumn = PUI.NewTableColumn("Actions", "")
	actionsColumn.Align = PUI.AlignCenter
	tableOptions.Columns.Add(actionsColumn)
	tableOptions.Rows = DisplayRows(data)
	tableOptions.RowIdField = "id"
	tableOptions.EmptyText = "No products match this search."
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
			AddRowAction(td1, "Edit", "bi bi-pencil", "/hx/products/edit/" & row1.Get("id"))
			AddRowAction(td1, "Delete", "bi bi-trash3", "/hx/products/delete/" & row1.Get("id"))
		Next
	End If
	Return table1
End Sub

Private Sub DisplayRows (data As List) As List
	Dim rows1 As List
	rows1.Initialize
	For Each row1 As Map In data
		Dim display1 As Map = CreateMap()
		For Each key As String In row1.Keys
			display1.Put(key, row1.Get(key))
		Next
		display1.Put("price_display", NumberFormat2(row1.Get("product_price"), 1, 2, 2, True))
		rows1.Add(display1)
	Next
	Return rows1
End Sub

Private Sub AddRowAction (Parent As MiniHtml, Title As String, IconClass As String, Url As String)
	Dim buttonOptions As PUIButtonOptions = PUI.NewButtonOptions("")
	buttonOptions.ButtonType = "button"
	buttonOptions.Variant = PUI.VariantLink
	buttonOptions.Size = PUI.SizeSmall
	buttonOptions.CssClass = "p-0 mx-2"
	Dim link1 As MiniHtml = PUI.Button(buttonOptions)
	link1.attr("title", Title)
	link1.attr("aria-label", Title)
	Dim htmx1 As PUIHtmxOptions = PUI.NewHtmxOptions(Url)
	htmx1.Target = "#modal-content"
	htmx1.Trigger = "click"
	htmx1.Swap = "innerHTML"
	PUI.Htmx(link1, htmx1)
	link1.attr("data-bs-toggle", "modal")
	link1.attr("data-bs-target", "#modal-container")
	Dim icon1 As MiniHtml = Tag("i")
	icon1.cls(IconClass)
	icon1.up(link1)
	link1.up(Parent)
End Sub

Private Sub ModalAdd (CategoryList As List) As MiniHtml
	Return ProductForm("Add product", "Create", "post", "", CategoryList, CreateMap())
End Sub

Private Sub ModalEdit (CategoryList As List, Data As Map) As MiniHtml
	Return ProductForm("Edit product", "Update", "put", "" & Data.Get("id"), CategoryList, Data)
End Sub

Private Sub ProductForm (Title As String, SubmitText As String, Verb As String, Id As String, CategoryList As List, Data As Map) As MiniHtml
	Dim form1 As MiniHtml = HtmxForm(Verb, "/hx/products", "#modal-messages")
	AddModalHeader(form1, Title)

	Dim body1 As MiniHtml = Tag("div").cls("modal-body")
	body1.up(form1)
	AddMessageSlot(body1)
	If Id <> "" Then AddHidden(body1, "id", Id)

	Dim selectedCategory As String = ""
	If Data.ContainsKey("category_id") Then selectedCategory = "" & Data.Get("category_id")
	AddCategorySelect(body1, selectedCategory, CategoryList)

	Dim codeOptions As PUIInputOptions = PUI.NewInputOptions("Code", "code")
	codeOptions.Required = True
	If Data.ContainsKey("product_code") Then codeOptions.Value = "" & Data.Get("product_code")
	PUI.Input(codeOptions).up(body1)

	Dim nameOptions As PUIInputOptions = PUI.NewInputOptions("Name", "name")
	nameOptions.Required = True
	If Data.ContainsKey("product_name") Then nameOptions.Value = "" & Data.Get("product_name")
	PUI.Input(nameOptions).up(body1)

	Dim priceOptions As PUIInputOptions = PUI.NewInputOptions("Price", "price")
	priceOptions.Required = True
	If Data.ContainsKey("product_price") Then priceOptions.Value = NumberFormat2(Data.Get("product_price"), 1, 2, 2, False)
	PUI.Input(priceOptions).up(body1)

	Dim submitVariant As String = PUI.VariantPrimary
	If Verb = "post" Then submitVariant = PUI.VariantSuccess
	AddModalFooter(form1, SubmitText, submitVariant)
	Return form1
End Sub

Private Sub ModalDelete (Data As Map) As MiniHtml
	Dim form1 As MiniHtml = HtmxForm("delete", "/hx/products?id=" & Data.Get("id"), "#modal-messages")
	AddModalHeader(form1, "Delete product")

	Dim body1 As MiniHtml = Tag("div").cls("modal-body")
	body1.up(form1)
	AddMessageSlot(body1)
	AddHidden(body1, "id", "" & Data.Get("id"))
	Dim text1 As MiniHtml = Tag("p")
	text1.up(body1)
	PUI.AddText(text1, "Delete " & Data.Get("product_name") & " (" & Data.Get("product_code") & ")?")
	AddModalFooter(form1, "Delete", PUI.VariantDanger)
	Return form1
End Sub

Private Sub AddCategorySelect (Parent As MiniHtml, Selected As String, CategoryList As List)
	Dim selectOptions As PUISelectOptions = PUI.NewSelectOptions("Category", "category")
	selectOptions.Placeholder = "Select category"
	selectOptions.Required = True
	If Selected <> "" Then selectOptions.SelectedValue = Selected
	For Each row1 As Map In CategoryList
		selectOptions.Items.Add(PUI.NewSelectItem("" & row1.Get("category_name"), "" & row1.Get("id")))
	Next
	PUI.SelectField(selectOptions).up(Parent)
End Sub

Private Sub HtmxForm (Verb As String, Href As String, Target As String) As MiniHtml
	Dim form1 As MiniHtml = Tag("form")
	form1.attr("action", Href)
	Dim htmx1 As PUIHtmxOptions = PUI.NewHtmxOptions(Href)
	htmx1.Method = Verb
	htmx1.Target = Target
	htmx1.Swap = "innerHTML"
	PUI.Htmx(form1, htmx1)
	Return form1
End Sub

Private Sub AddModalHeader (Parent As MiniHtml, Title As String)
	Dim header1 As MiniHtml = Tag("div").cls("modal-header")
	header1.up(Parent)
	Dim title1 As MiniHtml = Tag("h2").cls("modal-title fs-5")
	title1.text(Title)
	title1.up(header1)
	Dim close1 As MiniHtml = Tag("button")
	close1.attr("type", "button")
	close1.cls("btn-close")
	close1.attr("data-bs-dismiss", "modal")
	close1.attr("aria-label", "Close")
	close1.up(header1)
End Sub

Private Sub AddMessageSlot (Parent As MiniHtml)
	Dim messages1 As MiniHtml = Tag("div")
	messages1.attr("id", "modal-messages")
	messages1.up(Parent)
End Sub

Private Sub AddHidden (Parent As MiniHtml, Name As String, Value As String)
	Dim hidden1 As MiniHtml = Tag("input")
	hidden1.attr("type", "hidden")
	hidden1.attr("id", Name)
	hidden1.attr("name", Name)
	hidden1.attr("value", Value)
	hidden1.up(Parent)
End Sub

Private Sub AddModalFooter (Parent As MiniHtml, SubmitText As String, SubmitVariant As String)
	Dim footer1 As MiniHtml = Tag("div").cls("modal-footer")
	footer1.up(Parent)

	Dim submitOptions As PUIButtonOptions = PUI.NewButtonOptions(SubmitText)
	submitOptions.ButtonType = "submit"
	submitOptions.Variant = SubmitVariant
	submitOptions.CssClass = "px-3"
	PUI.Button(submitOptions).up(footer1)

	Dim cancelOptions As PUIButtonOptions = PUI.NewButtonOptions("Cancel")
	cancelOptions.ButtonType = "button"
	cancelOptions.Variant = PUI.VariantSecondary
	cancelOptions.CssClass = "px-3"
	Dim cancel1 As MiniHtml = PUI.Button(cancelOptions)
	cancel1.attr("data-bs-dismiss", "modal")
	cancel1.up(footer1)
End Sub

Private Sub Tag (Name As String) As MiniHtml
	Dim tag1 As MiniHtml
	tag1.Initialize(Name)
	Return tag1
End Sub
