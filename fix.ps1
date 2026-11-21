#Requires -RunAsAdministrator
$ErrorActionPreference = 'Continue'
$root = 'C:\TheGame\Sentinel'
$fLog = Join-Path $root 'fix.log'
function FLog($sev, $msg) {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $sev, $msg
    Add-Content -Path $fLog -Value $line -Encoding UTF8
    Write-Host $line
}
FLog 'INFO' '===== FIX RUN ====='

# 1. Task: verifikasi & daftar ulang dengan trigger yang benar
#    (trigger lama: Once jam 12:00 - artinya loop 10 menit baru mulai siang!)
$ex = $null
try { $ex = Get-ScheduledTask -TaskName 'SentinelWatch' -EA Stop } catch {}
if ($ex) { FLog 'OK' "task lama ada: state=$($ex.State)" } else { FLog 'WARN' 'task TIDAK ditemukan - daftar ulang' }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$root\monitor.ps1`" -Task"
$triggerBoot = New-ScheduledTaskTrigger -AtStartup
$triggerLoop = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 10)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'SentinelWatch' -Action $action -Trigger $triggerBoot,$triggerLoop `
    -Settings $settings -Principal $principal -Force | Out-Null
try {
    $chk = Get-ScheduledTask -TaskName 'SentinelWatch' -EA Stop
    FLog 'OK' "task terdaftar: state=$($chk.State)"
} catch { FLog 'CRIT' "task GAGAL: $($_.Exception.Message)" }

# 2. OpenSSH: capability removal gagal 0x800f0831 (payload WU tidak ada) -> hapus service manual
$svc = Get-Service sshd -EA 0
if ($svc) {
    Stop-Service sshd -Force -EA 0
    sc.exe delete sshd | Out-Null
    if (Get-Service sshd -EA 0) { FLog 'WARN' 'sshd service masih ada setelah sc delete' }
    else { FLog 'OK' 'sshd service DIHAPUS (sc delete)' }
} else { FLog 'OK' 'sshd service sudah tidak ada' }

# 3. Baseline BARU (semua komponen sudah terpasang - termasuk task SentinelWatch sendiri)
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\monitor.ps1" -Baseline

# 4. Scan verifikasi - harus 0 alert
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\monitor.ps1" -Run

FLog 'INFO' '===== FIX SELESAI ====='
