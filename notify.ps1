# Sentinel - notifikasi desktop (dijalankan task "SentinelNotify" tiap 5 menit, session user)
# Kalau ada baris BARU di sentinel-alert.log -> muncul popup + bunyi di layar Anda.
$ErrorActionPreference = 'SilentlyContinue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$fAlert = Join-Path $root 'sentinel-alert.log'
$fState = Join-Path $root '.notify-state'

if (-not (Test-Path $fAlert)) { exit 0 }
$lines = @(Get-Content $fAlert -EA 0)
$count = $lines.Count

# state belum ada = inisialisasi senyap (jangan popup untuk alert lama)
if (-not (Test-Path $fState)) { Set-Content -Path $fState -Value $count -Encoding ASCII; exit 0 }
$prev = 0
try { $prev = [int]((Get-Content $fState -Raw).Trim()) } catch {}

if ($count -gt $prev) {
    $new = @($lines | Select-Object -Skip $prev)
    Set-Content -Path $fState -Value $count -Encoding ASCII
    $tail = @($new | Select-Object -Last 6) -join "`n"
    $msg = "Ada perubahan terdeteksi di sistem Anda:`n`n$tail`n`nDetail lengkap:`n$fAlert`n(Event Viewer -> Windows Logs -> Application -> source 'Sentinel')`n`nKalau tidak yakin, kirim ini ke analisis Anda."
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $mb = [System.Windows.Forms.MessageBox]::Show($msg, 'SENTINEL ALERT', 'OK', 'Warning')
        [System.Media.SystemSounds]::Exclamation.Play()
    } catch {
        # fallback kalau Forms gagal
        msg * /TIME:60 "SENTINEL ALERT: $tail" | Out-Null
    }
}
exit 0
