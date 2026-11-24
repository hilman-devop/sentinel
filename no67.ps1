#Requires -RunAsAdministrator
<#
  Sentinel - no 6 & 7:
  6. Hapus sisa OpenSSH: C:\ProgramData\ssh + C:\Windows\System32\OpenSSH
  7. UNINSTALL.bat Monarch + hapus C:\ProgramData\Monarch
     (seluruh isi dipindah dulu ke Sentinel\evidence-monarch sebagai bukti)
#>
$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot
$fLog = Join-Path $root 'no67.log'
function L($sev, $msg) {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $sev, $msg
    Add-Content -Path $fLog -Value $line -Encoding UTF8
    Write-Host $line
}
L 'INFO' '===== NO 6 & 7 DIMULAI ====='

# ---------- 0. simpan hash (catatan laporan AV) ----------
$hashFile = Join-Path $root 'monarch-hashes.txt'
if (-not (Test-Path $hashFile)) {
    $lines = @('# SHA256 binari & bukti Monarch - dicatat sebelum penghapusan ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    Get-ChildItem 'C:\Program Files\Monarch' -Force -EA 0 | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
        $lines += "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256 -EA 0).Hash, $_.Name
    }
    Get-ChildItem 'C:\ProgramData\Monarch' -Force -File -EA 0 | ForEach-Object {
        $lines += "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256 -EA 0).Hash, $_.Name
    }
    $lines | Set-Content $hashFile -Encoding UTF8
    L 'OK' "hash disimpan ke $hashFile"
}

# ---------- 7a. pindahkan SEMUA isi ProgramData\Monarch ke evidence ----------
$evDir = Join-Path $root 'evidence-monarch'
if (Test-Path 'C:\ProgramData\Monarch') {
    New-Item -ItemType Directory -Path $evDir -Force | Out-Null
    cmd /c "attrib -r -h -s /s /d ""C:\ProgramData\Monarch\*"" >nul 2>&1"
    $items = Get-ChildItem 'C:\ProgramData\Monarch' -Force -EA 0
    foreach ($i in $items) {
        try {
            Move-Item -Path $i.FullName -Destination $evDir -Force -EA Stop
            L 'OK' "bukti dipindah: $($i.Name)"
        } catch { L 'CRIT' "gagal pindah $($i.Name): $($_.Exception.Message)" }
    }
    $left = @(Get-ChildItem 'C:\ProgramData\Monarch' -Force -EA 0)
    if ($left.Count -eq 0) {
        Remove-Item 'C:\ProgramData\Monarch' -Recurse -Force -EA 0
        if (Test-Path 'C:\ProgramData\Monarch') { L 'WARN' 'ProgramData\Monarch masih tersisa (mungkin terkunci)' }
        else { L 'OK' 'C:\ProgramData\Monarch DIHAPUS (isi sudah dipindah ke evidence-monarch)' }
    } else {
        L 'WARN' "masih ada $($left.Count) item tidak bisa dipindah: $($left.Name -join ', ')"
    }
} else { L 'OK' 'ProgramData\Monarch sudah tidak ada' }

# ---------- 7b. jalankan UNINSTALL.bat ----------
$bat = 'C:\Program Files\Monarch\UNINSTALL.bat'
if (Test-Path $bat) {
    L 'INFO' 'menjalankan UNINSTALL.bat ...'
    $out = cmd /c "`"$bat`"" 2>&1 | Out-String
    ($out -split "`r?`n") | Where-Object { $_ -ne '' } | ForEach-Object { L 'INFO' "bat: $_" }
} else { L 'OK' 'UNINSTALL.bat sudah tidak ada' }

# verifikasi + paksa kalau masih tersisa
if (Test-Path 'C:\Program Files\Monarch') {
    L 'WARN' 'Program Files\Monarch masih ada - paksa hapus'
    cmd /c "attrib -r -h -s /s /d ""C:\Program Files\Monarch\*"" >nul 2>&1"
    Remove-Item 'C:\Program Files\Monarch' -Recurse -Force -EA 0
}
if (Test-Path 'C:\Program Files\Monarch') { L 'CRIT' 'GAGAL hapus Program Files\Monarch' }
else { L 'OK' 'C:\Program Files\Monarch DIHAPUS' }

# ---------- 6a. hapus C:\ProgramData\ssh ----------
if (Test-Path 'C:\ProgramData\ssh') {
    cmd /c "attrib -r -h -s /s /d ""C:\ProgramData\ssh\*"" >nul 2>&1"
    Remove-Item 'C:\ProgramData\ssh' -Recurse -Force -EA 0
    if (Test-Path 'C:\ProgramData\ssh') { L 'CRIT' 'GAGAL hapus ProgramData\ssh' }
    else { L 'OK' 'C:\ProgramData\ssh DIHAPUS (host key + sshd.pid)' }
} else { L 'OK' 'ProgramData\ssh sudah tidak ada' }

# ---------- 6b. hapus C:\Windows\System32\OpenSSH (milik TrustedInstaller) ----------
$ossh = 'C:\Windows\System32\OpenSSH'
if (Test-Path $ossh) {
    L 'INFO' 'OpenSSH: takeown + icacls ...'
    cmd /c "takeown /f `"$ossh`" /r /d y >nul 2>&1"
    cmd /c "icacls `"$ossh`" /grant *S-1-5-32-544:F /t /c /q >nul 2>&1"
    cmd /c "attrib -r -h -s /s /d ""$ossh\*"" >nul 2>&1"
    Remove-Item $ossh -Recurse -Force -EA 0
    if (Test-Path $ossh) { L 'CRIT' 'GAGAL hapus System32\OpenSSH' }
    else { L 'OK' 'C:\Windows\System32\OpenSSH DIHAPUS (termasuk sshd.exe)' }
} else { L 'OK' 'System32\OpenSSH sudah tidak ada' }

# ---------- verifikasi akhir ----------
$svcLeft = @(Get-CimInstance Win32_Service -EA 0 | Where-Object { $_.Name -match '^Mxs|^Monarch|^sshd' })
if ($svcLeft.Count) { L 'CRIT' "service masih ada: $($svcLeft.Name -join ', ')" }
else { L 'OK' 'tidak ada service Mxs/Monarch/sshd lagi' }
$l22 = @(Get-NetTCPConnection -State Listen -LocalPort 22 -EA 0)
if ($l22.Count) { L 'CRIT' 'port 22 masih LISTEN' } else { L 'OK' 'port 22 tertutup' }
$mxsTask = @(Get-ScheduledTask -EA 0 | Where-Object { "$($_.TaskPath)$($_.TaskName)" -match 'Mxs|Monarch' })
if ($mxsTask.Count) { L 'WARN' "task Monarch tersisa: $($mxsTask.TaskName -join ', ')" }
else { L 'OK' 'tidak ada task Mxs/Monarch' }

# ---------- re-baseline + scan ----------
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\monitor.ps1" -Baseline
& powershell -NoProfile -ExecutionPolicy Bypass -File "$root\monitor.ps1" -Run
L 'INFO' '===== NO 6 & 7 SELESAI ====='
