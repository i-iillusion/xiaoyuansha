param(
    [Parameter(Mandatory=$true)][string]$GodotPath,
    [string]$Script = 'Test/test_lan.gd',
    [ValidateRange(2,10)][int]$Players = 2,
    [ValidateSet('','classic_identity','ambitious_identity','free_for_all')][string]$Mode = '',
    [switch]$DropCase,
    [switch]$SpaceCase,
    [switch]$UnitCase,
    [switch]$MedicineCase,
    [switch]$SummonCase,
    [switch]$RoarCase,
    [switch]$DragonTurnCase,
    [switch]$DragonLifecycleCase,
    [switch]$DragonGiftCase,
    [switch]$DragonGiftDropCase,
    [switch]$PublicDragonCase,
    [switch]$PublicMountainCase,
    [switch]$HostController
)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path $PSScriptRoot -Parent
$executable = (Resolve-Path -LiteralPath $GodotPath).Path
$logDir = Join-Path $projectPath ('.git/lan-tests/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$info = [Diagnostics.ProcessStartInfo]::new()
$info.FileName = $executable
$info.Arguments = '--headless --disable-render-loop --path "' + $projectPath + '" --script "' + $Script + '" -- --players=' + $Players
if ($Mode -ne '') { $info.Arguments += ' --mode=' + $Mode }
if ($DropCase) { $info.Arguments += ' --drop-case' }
if ($SpaceCase) { $info.Arguments += ' --space-case' }
if ($UnitCase) { $info.Arguments += ' --unit-case' }
if ($MedicineCase) { $info.Arguments += ' --medicine-case' }
if ($SummonCase) { $info.Arguments += ' --summon-case' }
if ($RoarCase) { $info.Arguments += ' --roar-case' }
if ($DragonTurnCase) { $info.Arguments += ' --dragon-turn-case' }
if ($DragonLifecycleCase) { $info.Arguments += ' --dragon-lifecycle-case' }
if ($DragonGiftCase) { $info.Arguments += ' --dragon-gift-case' }
if ($DragonGiftDropCase) { $info.Arguments += ' --dragon-gift-drop-case' }
if ($PublicDragonCase) { $info.Arguments += ' --public-dragon-case' }
if ($PublicMountainCase) { $info.Arguments += ' --public-mountain-case' }
if ($HostController) { $info.Arguments += ' --host-controller' }
$info.UseShellExecute = $false
$info.CreateNoWindow = $true
$info.RedirectStandardOutput = $true
$info.RedirectStandardError = $true
$process = [Diagnostics.Process]::Start($info)
$stdout = $process.StandardOutput.ReadToEndAsync()
$stderr = $process.StandardError.ReadToEndAsync()
$timedOut = -not $process.WaitForExit(60000)
if ($timedOut) { $process.Kill(); $process.WaitForExit() }
$stdout.Result | Set-Content -LiteralPath (Join-Path $logDir 'stdout.log') -Encoding UTF8
$stderr.Result | Set-Content -LiteralPath (Join-Path $logDir 'stderr.log') -Encoding UTF8
$lines = ($stdout.Result + "`n" + $stderr.Result) -split "`n"
$errors = @($lines | Where-Object { $_ -match 'SCRIPT ERROR|ERROR:|Parse Error|\bFAIL\b' })
$results = @($lines | Where-Object { $_ -match '^RESULT:' })
$passed = -not $timedOut -and $process.ExitCode -eq 0 -and $errors.Count -eq 0 -and $results.Count -eq 1 -and $results[0] -match '^RESULT: [1-9][0-9]* asserts, 0 failures\s*$'
[pscustomobject]@{exit_code=$process.ExitCode; timeout=$timedOut; passed=$passed; result=$results; errors=$errors; executable=$executable; script=$Script} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $logDir 'result.json') -Encoding UTF8
Write-Host "Logs: $logDir"
$results
$errors
if (-not $passed) { exit 1 }
