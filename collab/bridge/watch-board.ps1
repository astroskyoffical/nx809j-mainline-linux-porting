<#
Event-driven Claude worker for collab/CLAUDE_TASKS.md.

- Watches the board file. When it changes and has an unclaimed task under "## Open",
  starts one headless Claude run (claude -p) using the instructions in
  ~/.claude/scheduled-tasks/redmagic-codex-board/SKILL.md. Loops while tasks remain.
- Every 2 min: delivers queued Codex messages (collab/bridge/pending.txt) via
  notify-codex.ps1. Every 10 min: re-checks the board in case a file event was missed.
- Checks are plain PowerShell, so an idle board costs no AI tokens.
- Single instance (named mutex). Log: collab/bridge/watch-log.md.

Run:  powershell -NoProfile -ExecutionPolicy Bypass -File watch-board.ps1
Test: add -Once to do a single check/dispatch and exit.
#>
param([switch]$Once, [string]$ParseOnly)

$ErrorActionPreference = 'Stop'
$here    = $PSScriptRoot
$project = (Resolve-Path (Join-Path $here '..\..')).Path
$board   = if ($ParseOnly) { $ParseOnly } else { Join-Path $project 'collab\CLAUDE_TASKS.md' }
$notify  = Join-Path $here 'notify-codex.ps1'
$pending = Join-Path $here 'pending.txt'
$logMd   = Join-Path $here 'watch-log.md'
$logDir  = Join-Path $here 'logs'
$runPid  = Join-Path $here 'claude-run.pid'
$skill   = "$env:USERPROFILE\.claude\scheduled-tasks\redmagic-codex-board\SKILL.md"
$claude  = "$env:USERPROFILE\.local\bin\claude.exe"
New-Item -ItemType Directory -Force $logDir | Out-Null

function Write-Log([string]$line) {
    Add-Content -Path $logMd -Encoding utf8 -Value "- $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $line"
}

Set-Location $project
$mutex = New-Object Threading.Mutex($false, 'Local\RedMagicClaudeBoardWatcher')
if (-not $mutex.WaitOne(0)) { "Another watcher is already running"; exit 0 }

function Get-UnclaimedTasks {
    if (-not (Test-Path $board)) { return @() }
    $text = Get-Content $board -Raw -Encoding utf8
    $m = [regex]::Match($text, '(?ms)^## Open\s*$(.*?)(?=^## Done\s*$|\z)')
    if (-not $m.Success) { return @() }
    $found = @()
    foreach ($block in ($m.Groups[1].Value -split '(?m)^(?=### )')) {
        if ($block -notmatch '^### (T-\d+)') { continue }
        $id = $Matches[1]
        if ($block -match '(?m)^- Status:\s*(.*)$') {
            if ($Matches[1].Trim() -match '^OPEN\b') { $found += $id }
        } else { $found += $id }
    }
    return $found
}

function Invoke-Flush {
    if ((Test-Path $pending) -and (Get-Content $pending -Raw).Trim()) {
        try { & $notify | Out-Null } catch { Write-Log "flush error: $_" }
    }
}

function Invoke-Dispatch([string]$why) {
    $round = 0
    while ($round -lt 10) {
        $tasks = @(Get-UnclaimedTasks)
        if ($tasks.Count -eq 0) { return }
        $round++
        # A run started by an earlier watcher instance may still be alive (e.g. after a restart).
        if (Test-Path $runPid) {
            $old = Get-Process -Id ([int](Get-Content $runPid -Raw)) -ErrorAction SilentlyContinue
            if ($old -and $old.ProcessName -eq 'claude') { Write-Log "skip ($why): claude run pid $($old.Id) still active"; return }
        }
        $stray = Get-CimInstance Win32_Process -Filter "Name='claude.exe'" |
            Where-Object { $_.CommandLine -match '-p --permission-mode bypassPermissions --output-format text' }
        if ($stray) { Write-Log "skip ($why): headless claude pid $(@($stray)[0].ProcessId) still active"; return }
        $prompt = ((Get-Content $skill -Raw -Encoding utf8) -replace '(?s)^---.*?---\s*', '')
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $in  = Join-Path $logDir "$stamp-prompt.txt"
        $out = Join-Path $logDir "$stamp-claude.txt"
        Set-Content -Path $in -Value $prompt -Encoding utf8
        $p = Start-Process -FilePath $claude -ArgumentList '-p', '--permission-mode', 'bypassPermissions', '--output-format', 'text' `
            -WorkingDirectory $project -RedirectStandardInput $in -RedirectStandardOutput $out `
            -RedirectStandardError "$out.err" -WindowStyle Hidden -PassThru
        $null = $p.Handle   # keep a handle so ExitCode is readable after exit
        Set-Content -Path $runPid -Value $p.Id
        Write-Log "DISPATCH ($why): unclaimed $($tasks -join ', '); claude pid $($p.Id), log logs\$stamp-claude.txt"
        $p.WaitForExit()
        $code = $p.ExitCode
        Remove-Item $runPid -ErrorAction SilentlyContinue
        Write-Log "claude run finished, exit $code"
        if ($code -ne 0) { return }   # don't hot-loop on a failing run
        $after = @(Get-UnclaimedTasks)
        if ($after.Count -gt 0 -and $after[0] -eq $tasks[0]) {
            Write-Log "WARNING: $($tasks[0]) still unclaimed after a run; stopping until next change"
            return
        }
    }
}

if ($ParseOnly) { "unclaimed: [$((Get-UnclaimedTasks) -join ', ')]"; exit 0 }

Write-Log "watcher started (pid $PID)"
Invoke-Flush
Invoke-Dispatch 'startup'
if ($Once) { $mutex.ReleaseMutex(); exit 0 }

$fsw = New-Object IO.FileSystemWatcher (Split-Path $board), (Split-Path $board -Leaf)
$fsw.NotifyFilter = [IO.NotifyFilters]'LastWrite, FileName, Size'
$fsw.EnableRaisingEvents = $true
foreach ($ev in 'Changed', 'Created', 'Renamed') {
    Register-ObjectEvent $fsw $ev -SourceIdentifier "board-$ev" | Out-Null
}

$lastFlush = Get-Date; $lastSweep = Get-Date
while ($true) {
    $e = Wait-Event -Timeout 30
    if ($e) {
        # Debounce: let editors/OneDrive finish writing, drop the burst of duplicate events.
        Start-Sleep -Seconds 8
        Get-Event | Remove-Event
        Invoke-Dispatch 'board changed'
        Get-Event | Remove-Event   # ignore our own edits made during the run
    }
    if (((Get-Date) - $lastFlush).TotalMinutes -ge 2) { Invoke-Flush; $lastFlush = Get-Date }
    if (((Get-Date) - $lastSweep).TotalMinutes -ge 10) { Invoke-Dispatch 'sweep'; $lastSweep = Get-Date }
}
