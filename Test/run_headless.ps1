# Windows local equivalent of the seven CI suites. Never starts an interactive game.
param([Parameter(Mandatory = $true)][string]$GodotPath)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectPath = Split-Path $PSScriptRoot -Parent
$godotExecutable = (Resolve-Path -LiteralPath $GodotPath).Path
Push-Location $projectPath
try {
    $gitDir = (& git rev-parse --absolute-git-dir).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve repository metadata directory.' }
    $baseCommit = (& git rev-parse HEAD).Trim()
    $runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $logDir = Join-Path $gitDir "local-ci\$runId"
    $snapshot = Join-Path $logDir 'project'
    New-Item -ItemType Directory -Path $snapshot | Out-Null

    # Copy current source, including uncommitted/untracked test drafts, not .godot caches
    # or personal documents. Missing resources fail import rather than silently passing.
    if (Test-Path -LiteralPath (Join-Path $projectPath 'override.cfg')) {
        throw 'Working project has override.cfg; review its settings before using this isolated runner.'
    }
    $paths = @(& git -c core.quotepath=false ls-files --cached --others --exclude-standard -- Scripts Scenes Test project.godot)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate current project source.' }
    $manifest = foreach ($relative in ($paths | Sort-Object -Unique)) {
        $source = Join-Path $projectPath $relative
        # Respect tracked deletions in the current working tree.
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
        $destination = Join-Path $snapshot $relative
        New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination
        [pscustomobject]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash }
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'headless_override.cfg') -Destination (Join-Path $snapshot 'override.cfg')
    [pscustomobject]@{
        base_commit = $baseCommit
        worktree_status = @(& git -c core.quotepath=false status --short)
        godot_executable = $godotExecutable
        godot_sha256 = (Get-FileHash -LiteralPath $godotExecutable -Algorithm SHA256).Hash
        snapshot = $snapshot
        files = @($manifest)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $logDir 'manifest.json') -Encoding UTF8

    function Invoke-CheckedGodot([string]$Name, [string[]]$ExtraArgs, [int]$LimitSeconds) {
        $stdout = Join-Path $logDir "$Name.stdout.log"
        $stderr = Join-Path $logDir "$Name.stderr.log"
        # Godot's Windows logger flushes every print when stdout is a disk handle.
        # Drain both anonymous pipes as bytes, asynchronously, into buffered log files.
        # Do not use PowerShell's per-line pipeline or filter any engine output.
        foreach ($value in @($godotExecutable, $snapshot, $stdout, $stderr)) {
            if ($value -match '[%"\r\n]') { throw "Unsupported command path: $value" }
        }
        $arguments = @('--headless', '--path', ('"' + $snapshot + '"')) + $ExtraArgs
        $startInfo = New-Object Diagnostics.ProcessStartInfo
        $startInfo.FileName = $godotExecutable
        $startInfo.Arguments = $arguments -join ' '
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $startInfo
        $stdoutFile = [IO.File]::Create($stdout)
        $stderrFile = [IO.File]::Create($stderr)
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $started = $false
        $timedOut = $false
        try {
            $started = $process.Start()
            $stdoutCopy = $process.StandardOutput.BaseStream.CopyToAsync($stdoutFile)
            $stderrCopy = $process.StandardError.BaseStream.CopyToAsync($stderrFile)
            if (-not $process.WaitForExit($LimitSeconds * 1000)) {
                $timedOut = $true
                if (-not $process.HasExited) {
                    & taskkill.exe /PID $process.Id /T /F | Out-Null
                }
                $process.WaitForExit()
            }
            $process.WaitForExit()
            if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutCopy, $stderrCopy), 5000)) {
                throw "Output capture did not finish for $Name."
            }
            $stdoutFile.Dispose()
            $stderrFile.Dispose()
            $timer.Stop()
            # Capture/drain time is part of the same fixed budget.
            $timedOut = $timedOut -or $timer.Elapsed.TotalSeconds -gt $LimitSeconds
            $lines = @((@(Get-Content -LiteralPath $stdout -Encoding UTF8) + @(Get-Content -LiteralPath $stderr -Encoding UTF8)) | ForEach-Object { $_.ToString() })
            $errors = @($lines | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:|Parse Error|\bFAIL\b' })
            $resultLines = @($lines | Where-Object { $_ -match '^RESULT:' })
            $validResult = $resultLines.Count -eq 1 -and $resultLines[0] -match '^RESULT: [1-9][0-9]* asserts, 0 failures\s*$'
            $passed = -not $timedOut -and $process.ExitCode -eq 0 -and $errors.Count -eq 0 -and ($Name -eq 'import' -or $validResult)
            $outcome = [pscustomobject]@{
                name = $Name; limit_seconds = $LimitSeconds; elapsed_seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
                exit_code = $process.ExitCode; timeout = $timedOut; passed = $passed
                result = $resultLines; errors = $errors
            }
            Write-Host "$Name exit=$($outcome.exit_code) timeout=$timedOut passed=$passed seconds=$($outcome.elapsed_seconds) $resultLines"
            return $outcome
        } finally {
            if ($started -and -not $process.HasExited) { & taskkill.exe /PID $process.Id /T /F | Out-Null }
            $stdoutFile.Dispose()
            $stderrFile.Dispose()
            $process.Dispose()
        }
    }

    Write-Host "Source: $baseCommit plus working-tree changes; logs: $logDir"
    $outcomes = @(Invoke-CheckedGodot 'import' @('--editor', '--import', '--quit') 120)
    $outcomes | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $logDir 'results.json') -Encoding UTF8
    if ($outcomes[0].passed) {
        $tests = @('test_rule_settlement', 'test_confirmed_rules', 'test_bill', 'test_hand_payment', 'test_card_transfer', 'test_identity_victory', 'test_free_for_all_victory')
        foreach ($test in $tests) {
            $outcomes += Invoke-CheckedGodot $test @('--script', "Test/$test.gd") 60
            $outcomes | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $logDir 'results.json') -Encoding UTF8
        }
    }
    if ($outcomes.Count -ne 8 -or @($outcomes | Where-Object { -not $_.passed }).Count -ne 0) { exit 1 }
} finally {
    Pop-Location
}
