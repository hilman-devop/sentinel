#Requires -RunAsAdministrator
# Verifikasi SentinelWatch (trigger boot + 10 menit) + daftarkan SentinelNotify (popup desktop)
$ErrorActionPreference = 'Continue'
$out = "$env:TEMP\sentinel-verify.out"
$lines = @()
try {
    $t = Get-ScheduledTask -TaskName 'SentinelWatch' -EA Stop
    $i = Get-ScheduledTaskInfo -TaskName 'SentinelWatch'
    $lines += "SentinelWatch: state=$($t.State) last=$($i.LastRunTime) next=$($i.NextRunTime) result=$($i.LastTaskResult)"
    foreach ($tr in $t.Triggers) {
        $rep = $tr.Repetition.Interval
        $lines += "  trigger: $($tr.CimClass.CimClassName) enabled=$($tr.Enabled) repetition=$rep"
    }
    $lines += "  principal: $($t.Principal.UserId) runlevel=$($t.Principal.RunLevel)"
    # arsip XML ke hiks sebagai bukti trigger boot
    $t | Export-ScheduledTask | Set-Content 'C:\TheGame\Sentinel\hiks\SentinelWatch-task.xml' -Encoding UTF8
    $lines += "  XML diarsipkan ke hiks\SentinelWatch-task.xml"
} catch { $lines += "SentinelWatch GAGAL: $($_.Exception.Message)" }

# SentinelNotify - popup desktop utk Elz, tiap 5 menit
try {
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\TheGame\Sentinel\notify.ps1"'
    $trig = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
    $set = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 3) -MultipleInstances IgnoreNew
    $prin = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\Elz" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName 'SentinelNotify' -Action $action -Trigger $trig -Settings $set -Principal $prin -Force | Out-Null
    $n = Get-ScheduledTask -TaskName 'SentinelNotify' -EA Stop
    $lines += "SentinelNotify: TERDAFTAR state=$($n.State) (popup tiap 5 menit selama Elz login)"
} catch { $lines += "SentinelNotify GAGAL: $($_.Exception.Message)" }

$lines | Out-File $out -Encoding utf8
