#Requires -RunAsAdministrator
<#
  Sentinel - pemasang komponen (elevated)
   1. Jalankan hardening.ps1
   2. Buat baseline monitor
   3. Daftarkan scheduled task: cek tiap 10 menit + saat boot
   4. Jalankan scan pertama
#>
$ErrorActionPreference = 'SilentlyContinue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$fLog = Join-Path $root 'install.log'
function ILog($sev, $msg) {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $sev, $msg
    Add-Content -Path $fLog -Value $line -Encoding UTF8
    Write-Host $line
}

ILog 'INFO' '===== INSTALL SENTINEL ====='

# 1. hardening
& (Join-Path $root 'hardening.ps1')

# 2. baseline (task & service Monarch yang masih disabled ikut tercatat normal,
#    karena kondisi awal = disabled/mati; yang dipantau adalah PERUBAHAN)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'monitor.ps1') -Baseline
ILog 'OK' 'baseline dibuat'

# 3. scheduled task - 2 trigger: boot + tiap 10 menit
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$root\monitor.ps1`" -Task"
$triggerBoot = New-ScheduledTaskTrigger -AtStartup
$triggerLoop = New-ScheduledTaskTrigger -Once -At (Get-Date).Date.AddHours(12) -RepetitionInterval (New-TimeSpan -Minutes 10)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName 'SentinelWatch' -Action $action -Trigger $triggerBoot,$triggerLoop `
    -Settings $settings -Principal $principal -Force | Out-Null
if (Get-ScheduledTask -TaskName 'SentinelWatch' -EA 0) { ILog 'OK' 'scheduled task "SentinelWatch" terdaftar (boot + tiap 10 menit)' }
else { ILog 'CRIT' 'gagal daftar scheduled task' }

# 4. scan pertama
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'monitor.ps1') -Run
ILog 'INFO' '===== INSTALL SELESAI ====='
ILog 'INFO' "log : $fLog ; alert : $(Join-Path $root 'sentinel-alert.log')"
