#Requires -RunAsAdministrator
<#
  Sentinel - purge MxsWatchdog (pemicu self-healing Monarch yang masih hidup)
  1. Dump detail task ke file (bukti) sebelum dihapus
  2. Hapus task MxsWatchdog + task Monarch lain yang terdeteksi
  3. Verifikasi driver MxsGuard benar-benar mati
  4. Re-baseline + scan bersih
#>
$ErrorActionPreference = 'Continue'
$root = 'C:\TheGame\Sentinel'
$fLog = Join-Path $root 'purge.log'
function PLog($sev, $msg) {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $sev, $msg
    Add-Content -Path $fLog -Value $line -Encoding UTF8
    Write-Host $line
}
PLog 'INFO' '===== PURGE MxsWatchdog ====='

# ---------- 1. dump bukti task sebelum hapus ----------
$dump = Join-Path $root 'evidence-mxswatchdog.xml'
try {
    $t = Get-ScheduledTask -TaskName 'MxsWatchdog' -EA Stop
    $info = Get-ScheduledTaskInfo -TaskName 'MxsWatchdog' -EA SilentlyContinue
    $t | Export-ScheduledTask | Set-Content $dump -Encoding UTF8
    PLog 'OK' "task ditemukan: state=$($t.State)"
    if ($info) { PLog 'INFO' "last run=$($info.LastRunTime) result=$($info.LastTaskResult) next run=$($info.NextRunTime)" }
    PLog 'INFO' "trigger: $(($t.Triggers | ForEach-Object { $_.CimClass.CimClassName + ':' + $_.Repetition.Interval }) -join ' | ')"
    PLog 'INFO' "action: $((($t | Get-ScheduledTaskAction) | ForEach-Object { $_.Execute + ' ' + $_.Arguments }) -join ' | ')"
    PLog 'OK' "XML task disimpan ke $dump (bukti)"
} catch {
    PLog 'WARN' "task MxsWatchdog tidak ditemukan: $($_.Exception.Message)"
}

# ---------- 2. semua task sisa Monarch/Mxs ----------
$mxs = Get-ScheduledTask -EA 0 | Where-Object { "$($_.TaskPath)$($_.TaskName)" -match 'Mxs|Monarch|watchdog' -and $_.TaskName -ne 'SentinelWatch' }
foreach ($m in $mxs) {
    $full = "$($m.TaskPath)$($m.TaskName)"
    PLog 'INFO' "mematikan task: $full (state=$($m.State))"
    try { $m | Disable-ScheduledTask -EA Stop | Out-Null; PLog 'OK' "disabled: $full" } catch { PLog 'WARN' "disable gagal: $full - $($_.Exception.Message)" }
    try {
        $xml = $m | Export-ScheduledTask
        $evFile = Join-Path $root ("evidence-task-{0}.xml" -f ($m.TaskName -replace '[^\w\-]','_'))
        if (-not (Test-Path $evFile)) { $xml | Set-Content $evFile -Encoding UTF8; PLog 'INFO' "XML disimpan: $evFile" }
        Unregister-ScheduledTask -TaskName $m.TaskName -TaskPath $m.TaskPath -Confirm:$false -EA Stop
        PLog 'OK' "DIHAPUS: $full"
    } catch { PLog 'WARN' "hapus gagal: $full - $($_.Exception.Message)" }
}
if (-not $mxs) { PLog 'OK' 'tidak ada task Mxs/Monarch lain selain SentinelWatch' }

# ---------- 3. verifikasi driver & service ----------
$d = sc.exe query MxsGuard 2>&1 | Out-String
if ($d -match '1060|does not exist') { PLog 'OK' 'service driver MxsGuard: tidak terdaftar (mati)' }
else { PLog 'CRIT' "service driver MxsGuard MASIH ADA:`n$d"; }
$drvFile = Test-Path 'C:\Windows\System32\drivers\MxsGuard.sys'
if ($drvFile) {
    PLog 'CRIT' 'MxsGuard.sys masih ada di disk - mencoba hapus'
    try { sc.exe delete MxsGuard | Out-Null } catch {}
    Remove-Item 'C:\Windows\System32\drivers\MxsGuard.sys' -Force -EA 0
    if (Test-Path 'C:\Windows\System32\drivers\MxsGuard.sys') { PLog 'CRIT' 'GAGAL hapus MxsGuard.sys' }
    else { PLog 'OK' 'MxsGuard.sys dihapus' }
} else { PLog 'OK' 'MxsGuard.sys tidak ada di disk' }

# service Mxs tetap harus Disabled/Stopped
foreach ($s in 'MxsCore','MxsGate','MxsBackup','MxsWatcher') {
    $svc = Get-CimInstance Win32_Service -Filter "Name='$s'" -EA 0
    if ($svc) {
        if ($svc.State -eq 'Running' -or $svc.StartMode -eq 'Auto') { PLog 'CRIT' "service $s hidup lagi ($($svc.State)/$($svc.StartMode))" }
        else { PLog 'OK' "service $s tetap mati ($($svc.State)/$($svc.StartMode))" }
    } else { PLog 'OK' "service $s tidak ada" }
}

# ---------- 4. re-baseline + scan ----------
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\monitor.ps1" -Baseline
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\monitor.ps1" -Run
PLog 'INFO' '===== PURGE SELESAI ====='
