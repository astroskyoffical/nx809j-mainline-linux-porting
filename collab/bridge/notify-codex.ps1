<#
Sends a short message from Claude into the Codex "Plan RedMagic Linux port" thread.

- Only sends while that thread is idle (last turn event is task_complete/turn_aborted).
  If Codex is mid-turn, the message is queued in pending.txt and sent on the next call.
- Every attempt is logged to notify-log.md; Codex's reply goes to logs\.

Usage:
  .\notify-codex.ps1 -Message "T-002 done: see collab/results/T-002-....md"
  .\notify-codex.ps1            # just flush anything queued in pending.txt
  .\notify-codex.ps1 -Check     # report idle/busy only, send nothing
Exit codes: 0 sent (or nothing to send), 2 busy (queued), 1 error.
#>
param(
    [string]$Message,
    [switch]$Check,
    [string]$ThreadId = '01a1554c-b6f9-7181-a54d-3a7a1b486dc7',
    [int]$TimeoutSec = 900
)

$ErrorActionPreference = 'Stop'
$here    = $PSScriptRoot
$project = (Resolve-Path (Join-Path $here '..\..')).Path
$pending = Join-Path $here 'pending.txt'
$logMd   = Join-Path $here 'notify-log.md'
$logDir  = Join-Path $here 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null

function Write-Log([string]$line) {
    Add-Content -Path $logMd -Encoding utf8 -Value "- $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $line"
}

function Get-ThreadState {
    $rollout = Get-ChildItem "$env:USERPROFILE\.codex\sessions" -Recurse -Filter "rollout-*$ThreadId.jsonl" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $rollout) { throw "Rollout for thread $ThreadId not found" }
    $last = $null
    foreach ($line in (Get-Content $rollout.FullName -Tail 400 -Encoding utf8)) {
        if ($line -match '"type":"event_msg"' -and
            $line -match '"payload":\{"type":"(task_started|task_complete|turn_aborted)"') {
            $last = $Matches[1]
        }
    }
    if ($last -eq 'task_started') { 'busy' } else { 'idle' }
}

# Queue the new message first so nothing is lost if we are busy or fail.
if ($Message) {
    Add-Content -Path $pending -Encoding utf8 -Value ($Message.Trim() + "`n---")
}

# Only one sender at a time; a second caller leaves its message queued.
$sendLock = New-Object Threading.Mutex($false, 'Local\RedMagicCodexNotify')
if (-not $Check -and -not $sendLock.WaitOne(0)) { "Another send is in progress; queued"; exit 2 }

$state = Get-ThreadState
if ($Check) { "Codex thread is $state"; exit 0 }

if (-not (Test-Path $pending) -or -not (Get-Content $pending -Raw).Trim()) { "Nothing to send"; exit 0 }

if ($state -ne 'idle') {
    Write-Log "BUSY: Codex mid-turn; message kept in pending.txt"
    "Codex is busy; queued"; exit 2
}

$queued = (Get-Content $pending -Raw -Encoding utf8).Trim()
$body = @"
[Message from Claude (Claude Code), your helper on this project, sent automatically by collab/bridge/notify-codex.ps1]

$queued

Board: collab/CLAUDE_TASKS.md. Pull results in as useful and queue further independent tasks there; I pick them up automatically. No reply to me is needed.
"@

$codex = Get-ChildItem "$env:LOCALAPPDATA\OpenAI\Codex\bin\*\codex.exe" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $codex) { Write-Log "ERROR: codex.exe not found"; throw 'codex.exe not found' }

$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$msgFile = Join-Path $logDir "$stamp-message.txt"
$outFile = Join-Path $logDir "$stamp-reply.txt"
$errFile = Join-Path $logDir "$stamp-stderr.txt"
Set-Content -Path $msgFile -Value $body -Encoding utf8

# Hand the message over on stdin ("-") so quoting/newlines are safe.
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $codex.FullName
$psi.Arguments = "exec resume $ThreadId - -o `"$outFile`""
$psi.WorkingDirectory = $project
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.StandardOutputEncoding = [Text.Encoding]::UTF8
$psi.StandardErrorEncoding = [Text.Encoding]::UTF8
$proc = [Diagnostics.Process]::Start($psi)
$stdin = New-Object IO.StreamWriter($proc.StandardInput.BaseStream, (New-Object Text.UTF8Encoding($false)))
$stdin.Write($body); $stdin.Close()
$outTask = $proc.StandardOutput.ReadToEndAsync()
$errTask = $proc.StandardError.ReadToEndAsync()
if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
    $proc.Kill()
    Write-Log "ERROR: codex exec timed out after $TimeoutSec s (log $stamp); message kept in pending.txt"
    exit 1
}
Set-Content -Path $errFile -Value ($errTask.Result + $outTask.Result) -Encoding utf8

if ($proc.ExitCode -eq 0) {
    Remove-Item $pending
    Write-Log "SENT (log $stamp): $(($queued -split "`n")[0])"
    "Sent. Codex reply: $outFile"; exit 0
} else {
    Write-Log "ERROR: codex exit $($proc.ExitCode) (see logs\$stamp-stderr.txt); message kept in pending.txt"
    "codex failed with exit $($proc.ExitCode); see $errFile"; exit 1
}
