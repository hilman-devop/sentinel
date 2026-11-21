# Sentinel Guard - LAPIS CADANGAN.
# Tugas: memastikan SentinelWatch & SentinelNotify selalu ada, aktif, dan jalan.
# Dijalankan oleh task 'SentinelGuard' (SYSTEM, saat boot + tiap 15 menit).
# Kalau task utama dihapus/di-disable (mis. oleh pembersih/malware), di sini dipulihkan.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$log  = Join-Path $root 'guard.log'
function G($m){ Add-Content -Path $log -Value ("{0} [GUARD] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }

function Ensure($name, $xmlPath) {
    $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if (-not $t) {
        if (Test-Path $xmlPath) {
            try {
                Register-ScheduledTask -TaskName $name -Xml (Get-Content $xmlPath -Raw) -Force -ErrorAction Stop | Out-Null
                G "PULIH: task '$name' HILANG -> dibuat ulang dari XML"
                Start-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
            } catch { G "GAGAL pulihkan '$name': $($_.Exception.Message)" }
        } else { G "task '$name' hilang, tapi XML cadangan tak ada: $xmlPath" }
        return
    }
    if ($t.State -eq 'Disabled') {
        Enable-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue | Out-Null
        G "AKTIFKAN: task '$name' tadinya Disabled -> di-enable"
        Start-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    }
}

Ensure 'SentinelWatch'  (Join-Path $root 'hiks\SentinelWatch-task.xml')
Ensure 'SentinelNotify' (Join-Path $root 'hiks\SentinelNotify-task.xml')

# cek kesehatan: SentinelWatch harus jalan dalam 20 menit terakhir
$i = Get-ScheduledTaskInfo -TaskName 'SentinelWatch' -ErrorAction SilentlyContinue
if ($i -and $i.LastRunTime -and ((Get-Date) - $i.LastRunTime).TotalMinutes -gt 20) {
    G "TERLAMBAT: SentinelWatch terakhir $($i.LastRunTime) (>20 mnt) -> start ulang"
    Start-ScheduledTask -TaskName 'SentinelWatch' -ErrorAction SilentlyContinue
}
