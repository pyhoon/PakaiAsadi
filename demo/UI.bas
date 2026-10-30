B4J=true
Group=App
ModulesStructureVersion=1
Type=StaticCode
Version=10.7
@EndOfDesignText@
' View helpers for the Pakai Asadi demo, built on PakaiUI.
' MiniHTML 4.05 escapes text values by default, so these helpers pass raw
' strings to text and never call EscapeHtml themselves.
Sub Process_Globals

End Sub

Public Sub FormHtmx (Verb As String, Href As String, Target As String) As MiniHtml
	Dim form1 As MiniHtml = MH.CreateTag("form")
	form1.attr("action", Href)
	Dim htmx1 As PUIHtmxOptions = PUI.NewHtmxOptions(Href)
	htmx1.Method = Verb
	htmx1.Target = Target
	htmx1.Swap = "innerHTML"
	PUI.Htmx(form1, htmx1)
	Return form1
End Sub

Public Sub ModalHeader (Parent As MiniHtml, Title As String)
	Dim header1 As MiniHtml = MH.Div.cls("modal-header")
	header1.up(Parent)
	Dim title1 As MiniHtml = MH.H2.cls("modal-title fs-5")
	title1.text(Title)
	title1.up(header1)
	Dim close1 As MiniHtml = MH.Button.attr("type", "button").cls("btn-close").attr("data-bs-dismiss", "modal").attr("aria-label", "Close")
	close1.up(header1)
End Sub

Public Sub MessageSlot (Parent As MiniHtml)
	MH.Div.attr("id", "modal-messages").up(Parent)
End Sub

Public Sub HiddenField (Parent As MiniHtml, Name As String, Value As String)
	MH.Input.attr("type", "hidden").attr("id", Name).attr("name", Name).attr("value", Value).up(Parent)
End Sub

Public Sub ModalFooter (Parent As MiniHtml, SubmitText As String, SubmitVariant As String)
	Dim footer1 As MiniHtml = MH.Div.cls("modal-footer")
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

Public Sub RowAction (Parent As MiniHtml, Title As String, IconClass As String, Url As String)
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
	Dim icon1 As MiniHtml = MH.CreateTag("i")
	icon1.cls(IconClass)
	icon1.up(link1)
	link1.up(Parent)
End Sub

Public Sub ToolbarButton (Parent As MiniHtml, Text As String, Url As String)
	Dim addOptions As PUIButtonOptions = PUI.NewButtonOptions(Text)
	addOptions.Variant = PUI.VariantPrimary
	addOptions.Size = PUI.SizeSmall
	Dim add1 As MiniHtml = PUI.Button(addOptions)
	Dim htmx1 As PUIHtmxOptions = PUI.NewHtmxOptions(Url)
	htmx1.Target = "#modal-content"
	htmx1.Trigger = "click"
	PUI.Htmx(add1, htmx1)
	add1.attr("data-bs-toggle", "modal")
	add1.attr("data-bs-target", "#modal-container")
	add1.up(Parent)
End Sub
