B4J=true
Group=Handlers
ModulesStructureVersion=1
Type=Class
Version=10.7
@EndOfDesignText@
Sub Class_Globals
End Sub

Public Sub Initialize
End Sub

Sub Handle (req As ServletRequest, resp As ServletResponse)
	resp.ContentType = "text/html; charset=utf-8"
	resp.Write("<!doctype html><html lang='en'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Pakai Asadi demo host</title><style>body{font:16px system-ui;background:#f5f7fb;color:#182235;margin:0;padding:10vh 8vw}main{max-width:650px;margin:auto;background:#fff;border:1px solid #e5eaf1;border-radius:18px;padding:38px}small{color:#4263eb;letter-spacing:.15em;font-weight:700}h1{font-size:30px;letter-spacing:-.04em}p{color:#68748a;line-height:1.6}a{display:inline-block;background:#4263eb;color:#fff;text-decoration:none;padding:11px 16px;border-radius:9px;font-weight:600}</style><main><small>EMBEDDED B4J DEMO</small><h1>Pakai Asadi</h1><p>This page is served by the demo host. Asadi registers its routes with this same EndsMeet server and does not start another listener.</p><a href='/asadi'>Open database workspace →</a><p><strong>Local-only demo gate:</strong> the workspace is restricted to loopback requests. Replace this with a host authorization policy before deployment.</p></main></html>")
End Sub
