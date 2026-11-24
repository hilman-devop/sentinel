# Sentinel - kunci folder: hanya pengguna saat ini, SYSTEM, dan Administrators yang bisa akses.
# JALANKAN ELEVATED (butuh takeown). Idempotent - aman diulang.
#
# Batas jujur: proses yang berjalan sebagai SYSTEM/Administrator SELALU bisa
# take-ownership (sifat mutlak Windows). ACL ini menutup akun lain & proses
# non-privileged; ia TIDAK bisa menahan penyerang yang sudah jadi admin/SYSTEM.
$ErrorActionPreference = 'Continue'
$path = Split-Path -Parent $MyInvocation.MyCommand.Path
$me = "$env:USERDOMAIN\$env:USERNAME"
$sys = 'NT AUTHORITY\SYSTEM'
$adm = 'BUILTIN\Administrators'

# 1. ambil kepemilikan seluruh pohon (owner selalu punya hak ubah-izin)
& takeown /F $path /R /D Y *> $null

# 2. cabut pewarisan rekursif
& icacls $path /inheritance:r /T /C /Q | Out-Null

# 3. folder dapat (OI)(CI)F ; file dapat F
#    (flag warisan OI/CI TIDAK valid untuk file -> file akan ber-DACL kosong)
foreach ($d in @(Get-Item $path) + @(Get-ChildItem $path -Recurse -Force -Directory)) {
    & icacls $d.FullName /grant:r "$me`:(OI)(CI)F" "$sys`:(OI)(CI)F" "$adm`:(OI)(CI)F" /Q | Out-Null
}
foreach ($f in @(Get-ChildItem $path -Recurse -Force -File)) {
    & icacls $f.FullName /grant:r "$me`:F" "$sys`:F" "$adm`:F" /Q | Out-Null
}

# 4. owner akhir = pengguna saat ini
& icacls $path /setowner $me /T /C /Q | Out-Null

'lockdown selesai'
