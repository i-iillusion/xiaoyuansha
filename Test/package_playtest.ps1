param([string]$Revision = 'HEAD')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $repo
try {
    $sha = (git rev-parse --verify "$Revision^{commit}").Trim()
    if ($LASTEXITCODE -ne 0 -or $sha -notmatch '^[0-9a-f]{40}$') { throw 'Invalid committed revision' }
    $gitDir = (git rev-parse --absolute-git-dir).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve repository metadata directory' }
    $outputDir = Join-Path $gitDir ('playtest/' + $sha)
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    $archive = Join-Path $outputDir ('xiaoyuansha-playtest-' + $sha.Substring(0, 8) + '.zip')
    # Unique temporary output: never overwrite an existing published artifact.
    $temporary = Join-Path $outputDir ([guid]::NewGuid().ToString() + '.zip')
    $paths = @('Scripts', 'Scenes', 'Docs', 'project.godot', 'README.md')
    & git archive --format=zip "--output=$temporary" $sha -- @paths
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($temporary)
    try {
        $entries = @($zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | ForEach-Object { $_.FullName })
        $expected = @(& git -c core.quotepath=false ls-tree -r --name-only $sha -- @paths)
        if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate source files' }
        if (@(Compare-Object $entries $expected).Count -ne 0) { throw 'Archive entries differ from committed source' }
        foreach ($entry in $entries) {
            if ($entry.StartsWith('/') -or $entry.Contains('\') -or $entry.Split('/') -contains '..') {
                throw 'Unsafe archive path'
            }
        }
    } finally { $zip.Dispose() }
    $hash = (Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash
    if (Test-Path -LiteralPath $archive) {
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $hash) { throw 'Existing artifact has different content; refusing overwrite' }
        # Keep duplicate generated archive as evidence; no deletion of user paths.
    } else {
        Move-Item -LiteralPath $temporary -Destination $archive
    }
    $metadata = [ordered]@{ commit = $sha; sha256 = $hash; archive = $archive; files = $entries.Count; engine = 'Godot 4.7.2 standard'; kind = 'source-only' }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outputDir 'source.json') -Encoding UTF8
    $metadata | ConvertTo-Json
} finally { Pop-Location }
