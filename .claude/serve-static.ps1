param(
    [int]$Port = 8080
)

$root = Split-Path -Parent $PSScriptRoot
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

$mime = @{
    ".html" = "text/html; charset=utf-8"
    ".js"   = "text/javascript; charset=utf-8"
    ".mjs"  = "text/javascript; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".svg"  = "image/svg+xml"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".sql"  = "text/plain; charset=utf-8"
    ".md"   = "text/plain; charset=utf-8"
}

Write-Host "Serving '$root' at http://localhost:$Port/ (default file: team-fe.html)"

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
    } catch {
        continue
    }

    try {
        $request = $context.Request
        $response = $context.Response
        $response.KeepAlive = $false
        $response.Headers.Add("Cache-Control", "no-store, must-revalidate")

        $path = [System.Uri]::UnescapeDataString($request.Url.AbsolutePath)
        if ($path -eq "/") { $path = "/team-fe.html" }

        $filePath = Join-Path $root ($path.TrimStart("/"))
        $fullRoot = [System.IO.Path]::GetFullPath($root)
        $fullFile = [System.IO.Path]::GetFullPath($filePath)

        if ($fullFile.StartsWith($fullRoot) -and (Test-Path $fullFile -PathType Leaf)) {
            $ext = [System.IO.Path]::GetExtension($fullFile)
            $contentType = $mime[$ext]
            if (-not $contentType) { $contentType = "application/octet-stream" }
            $bytes = [System.IO.File]::ReadAllBytes($fullFile)
            $response.ContentType = $contentType
            $response.ContentLength64 = $bytes.LongLength
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $response.StatusCode = 404
            $notFound = [System.Text.Encoding]::UTF8.GetBytes("404 - Not Found: $path")
            $response.ContentLength64 = $notFound.LongLength
            $response.OutputStream.Write($notFound, 0, $notFound.Length)
        }
    } catch {
        Write-Host "Request error: $_"
    } finally {
        try { $context.Response.Close() } catch {}
    }
}
