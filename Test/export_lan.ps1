param(
    [Parameter(Mandatory=$true)][string]$GodotPath,
    [Parameter(Mandatory=$true)][string]$VerificationDirectory,
    [string]$TemplatePath = '.git/lan-build/templates/windows_release_x86_64.exe'
)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
Push-Location $project
try {
    $engine = (Resolve-Path -LiteralPath $GodotPath).Path
    $template = (Resolve-Path -LiteralPath $TemplatePath).Path
    $evidence = (Resolve-Path -LiteralPath $VerificationDirectory).Path
    [array]$results = Get-Content -LiteralPath (Join-Path $evidence 'results.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($results.Count -ne 8 -or @($results | Where-Object {-not $_.passed}).Count -ne 0) { throw 'All seven original suites and import must pass before packaging.' }
    $manifest = Get-Content -LiteralPath (Join-Path $evidence 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($item in $manifest.files) {
        if ($item.path -notmatch '^(Scripts/|Scenes/|project.godot$)') { continue }
        if (-not (Test-Path -LiteralPath $item.path) -or (Get-FileHash -LiteralPath $item.path -Algorithm SHA256).Hash -ne $item.sha256) { throw "Verified source changed: $($item.path)" }
    }
    $expected = @($manifest.files | Where-Object {$_.path -match '^(Scripts/|Scenes/)'} | ForEach-Object {$_.path} | Sort-Object)
    $actual = @(Get-ChildItem -LiteralPath 'Scripts','Scenes' -File -Recurse | ForEach-Object {$_.FullName.Substring($project.Length+1).Replace('\','/')} | Sort-Object)
    if (@(Compare-Object $expected $actual).Count -ne 0) { throw 'Runtime source file set differs from verified snapshot.' }
    $id = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
    $build = Join-Path $project "builds/lan-$id"
    $snapshot = Join-Path $build 'project'
    $bundle = Join-Path $build 'CampusSha-LAN'
    New-Item -ItemType Directory -Path $snapshot,$bundle -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $project 'builds/.gdignore'), '')
    # Strict runtime whitelist: no tests, user files, PDFs, .git, export credentials.
    foreach ($folder in @('Scripts','Scenes')) { Copy-Item -LiteralPath (Join-Path $project $folder) -Destination $snapshot -Recurse }
    Copy-Item -LiteralPath 'project.godot' -Destination $snapshot
    $preset = [IO.File]::ReadAllText((Join-Path $project 'export_presets.cfg'))
    $preset = $preset.Replace('res://.git/lan-build/templates/windows_release_x86_64.exe', $template.Replace('\','/'))
    [IO.File]::WriteAllText((Join-Path $snapshot 'export_presets.cfg'), $preset, [Text.UTF8Encoding]::new($false))
    function Run-Checked([string]$Name, [string]$Executable, [string]$Arguments, [string]$WorkingDirectory = $project) {
        $info = [Diagnostics.ProcessStartInfo]::new()
        $info.FileName = $Executable
        $info.Arguments = $Arguments
        $info.WorkingDirectory = $WorkingDirectory
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $proc = [Diagnostics.Process]::Start($info)
        $out = $proc.StandardOutput.ReadToEndAsync()
        $err = $proc.StandardError.ReadToEndAsync()
        $timeout = -not $proc.WaitForExit(120000)
        if ($timeout) { $proc.Kill(); $proc.WaitForExit() }
        $out.Result | Set-Content -LiteralPath (Join-Path $build "$Name.stdout.log") -Encoding UTF8
        $err.Result | Set-Content -LiteralPath (Join-Path $build "$Name.stderr.log") -Encoding UTF8
        if ($timeout -or $proc.ExitCode -ne 0 -or ($out.Result + $err.Result) -match 'SCRIPT ERROR|ERROR:|Parse Error') { throw "$Name failed; see $build" }
        Write-Host "$Name exit=$($proc.ExitCode) passed"
    }
    $exe = Join-Path $bundle 'CampusSha-LAN.exe'
    Run-Checked 'import' $engine ('--headless --editor --import --quit --path "' + $snapshot + '"')
    Run-Checked 'export' $engine ('--headless --path "' + $snapshot + '" --export-release "Windows LAN" "' + $exe + '"')
    Run-Checked 'startup' $exe '--headless --quit-after 8'
    Run-Checked 'lan-startup' $exe '--headless --quit-after 20 -- --lan'
    if ([IO.File]::ReadAllText((Join-Path $build 'lan-startup.stdout.log')) -notmatch '\[LAN\] room ready') { throw 'Packaged LAN scene did not reach ready.' }
    Copy-Item -LiteralPath 'Docs/HumanAgent/局域网试玩说明.md' -Destination (Join-Path $bundle '试玩说明.txt')
    foreach ($license in @('LICENSE.txt','COPYRIGHT.txt')) {
        $source = Join-Path $project ".git/lan-build/templates/$license"
        if (-not (Test-Path -LiteralPath $source)) { throw "Missing Godot license $source" }
        Copy-Item -LiteralPath $source -Destination (Join-Path $bundle "Godot-$license")
    }
    $sourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $snapshot 'Scripts'),(Join-Path $snapshot 'Scenes') -File -Recurse) + @(Get-Item -LiteralPath (Join-Path $snapshot 'project.godot'))
    $info = [pscustomobject]@{
        base_commit=(& git rev-parse HEAD).Trim(); branch=(& git branch --show-current).Trim()
        protocol='campus-lan-5'; built_at=(Get-Date).ToString('o'); engine_sha256=(Get-FileHash -LiteralPath $engine).Hash
        template_sha256=(Get-FileHash -LiteralPath $template).Hash; exe_sha256=(Get-FileHash -LiteralPath $exe).Hash
        verification='Seven rule suites passed; see repository LAN verification report.'
        source=@($sourceFiles | ForEach-Object { [pscustomobject]@{path=$_.FullName.Substring($snapshot.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName).Hash} })
    }
    $info | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $bundle 'build-info.json') -Encoding UTF8
    $zip = Join-Path $build 'CampusSha-LAN-Windows-x64.zip'
    Compress-Archive -LiteralPath $bundle -DestinationPath $zip
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entries = @($archive.Entries | Where-Object {-not $_.FullName.EndsWith('/')} | ForEach-Object {$_.FullName.Replace('\','/')} | Sort-Object)
        $allowed = @('CampusSha-LAN/CampusSha-LAN.exe', 'CampusSha-LAN/试玩说明.txt', 'CampusSha-LAN/Godot-LICENSE.txt', 'CampusSha-LAN/Godot-COPYRIGHT.txt', 'CampusSha-LAN/build-info.json') | Sort-Object
        if (@(Compare-Object $allowed $entries).Count -ne 0) { throw 'Unexpected release ZIP file set.' }
    } finally { $archive.Dispose() }
    $unpack = Join-Path $build 'clean-unpack'
    Expand-Archive -LiteralPath $zip -DestinationPath $unpack
    $cleanBundle = Join-Path $unpack 'CampusSha-LAN'
    $cleanExe = Join-Path $cleanBundle 'CampusSha-LAN.exe'
    if ((Get-FileHash -LiteralPath $cleanExe).Hash -ne $info.exe_sha256) { throw 'Unpacked executable hash mismatch.' }
    Run-Checked 'clean-lan-startup' $cleanExe '--headless --quit-after 20 -- --lan' $cleanBundle
    if ([IO.File]::ReadAllText((Join-Path $build 'clean-lan-startup.stdout.log')) -notmatch '\[LAN\] room ready') { throw 'Unpacked LAN scene did not reach ready.' }
    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    [pscustomobject]@{passed=$true; zip_sha256=$hash; zip_bytes=(Get-Item -LiteralPath $zip).Length; exe_sha256=$info.exe_sha256; base_commit=$info.base_commit; files=$entries; working_directory=$cleanBundle} | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $build 'clean-package-check.json') -Encoding UTF8
    "$hash  CampusSha-LAN-Windows-x64.zip" | Set-Content -LiteralPath (Join-Path $build 'SHA256.txt') -Encoding ASCII
    Write-Host "PACKAGE=$zip"
    Write-Host "SHA256=$hash"
} finally { Pop-Location }
