#Requires -RunAsAdministrator
<#
  Sentinel - Hardening (sekali jalan, elevated)
  Menutup semua pintu masuk jaringan + mengaktifkan logging yang cukup
  supaya kejadian seperti Monarch tidak bisa terulang tanpa jejak.
#>
$ErrorActionPreference = 'SilentlyContinue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$fLog = Join-Path $root 'hardening.log'
$fBlock = Join-Path $root 'blocklist.txt'

function HLog($sev, $msg) {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $sev, $msg
    Add-Content -Path $fLog -Value $line -Encoding UTF8
    Write-Host $line
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    HLog 'ERROR' 'Tidak berjalan sebagai admin - batal'
    exit 1
}
HLog 'INFO' '===== HARDENING DIMULAI ====='

# ---------- 1. Event source Sentinel ----------
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists('Sentinel')) {
        New-EventLog -LogName Application -Source 'Sentinel'
    }
    HLog 'OK' 'Event log source "Sentinel" siap'
} catch { HLog 'WARN' "Event source gagal: $($_.Exception.Message)" }

# ---------- 2. Blokir domain penyerang di hosts ----------
$domains = Get-Content $fBlock -EA 0 | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
try {
    $cur = Get-Content $hostsFile -EA 0
    $add = @()
    foreach ($d in $domains) {
        if (-not ($cur | Where-Object { $_ -match "(^|\s)$([regex]::Escape($d))(\s|$)" })) { $add += "0.0.0.0 $d" }
    }
    if ($add.Count -gt 0) {
        Add-Content -Path $hostsFile -Value ("`r`n# === SENTINEL BLOCK ===" + "`r`n" + ($add -join "`r`n")) -Encoding ASCII
    }
    HLog 'OK' "hosts: $(($domains | Measure-Object).Count) domain diblokir ($($add.Count) baru ditambahkan)"
} catch { HLog 'WARN' "hosts gagal: $($_.Exception.Message)" }

# ---------- 3. Firewall: blokir inbound pintu masuk jarak jauh ----------
$blockPorts = 22, 139, 3389, 5985, 5986
foreach ($p in $blockPorts) {
    $n = "Sentinel-BlockIn-$p"
    $ex = Get-NetFirewallRule -DisplayName $n -EA 0
    if (-not $ex) {
        try {
            New-NetFirewallRule -DisplayName $n -Direction Inbound -Protocol TCP -LocalPort $p -Action Block -Enabled True -Profile Any | Out-Null
            HLog 'OK' "firewall: blokir inbound TCP $p"
        } catch { HLog 'WARN' "firewall $p gagal: $($_.Exception.Message)" }
    } else { HLog 'OK' "firewall: rule $n sudah ada" }
}

# Verifikasi SMB(445) tidak punya rule allow inbound
$smbAllow = Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow |
    Where-Object { (Get-NetFirewallPortFilter -ErrorAction SilentlyContinue -InputObject $_).LocalPort -contains 445 }
if ($smbAllow) { HLog 'WARN' "445 punya rule allow: $($smbAllow.DisplayName -join ', ')" }
else { HLog 'OK' 'SMB/445: TIDAK ada rule allow inbound (tertutup)' }

# Matikan rule Network Discovery inbound (pemblokiran poisoning LLMNR/NBNS dari sesama LAN)
$nd = Get-NetFirewallRule -DisplayGroup 'Network Discovery' -Direction Inbound -ErrorAction SilentlyContinue
$ndOff = 0
foreach ($r in $nd) { if ($r.Enabled -eq 'True') { $r | Set-NetFirewallRule -Enabled False; $ndOff++ } }
HLog 'OK' "Network Discovery inbound: $ndOff rule dimatikan (anti-poisoning LAN)"

# ---------- 4. Perbesar log (janji bukti tidak hilang lagi) ----------
$wantSec = [int64]1GB
$wantSys = [int64]256MB
foreach ($l in @(@('Security', $wantSec), @('System', $wantSys), @('Windows PowerShell', $wantSys), @('Microsoft-Windows-PowerShell/Operational', $wantSys))) {
    $lg = Get-WinEvent -ListLog $l[0] -EA 0
    if ($lg -and $lg.MaximumSizeInBytes -lt $l[1]) {
        wevtutil sl $l[0] "/ms:$($l[1])"
        $lg2 = Get-WinEvent -ListLog $l[0] -EA 0
        HLog 'OK' "log $($l[0]) -> $([math]::Round($lg2.MaximumSizeInBytes/1MB)) MB"
    } elseif ($lg) { HLog 'OK' "log $($l[0]) sudah $([math]::Round($lg.MaximumSizeInBytes/1MB)) MB" }
}

# ---------- 5. Audit: rekam cmdline setiap proses + PowerShell ScriptBlock ----------
try {
    $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name 'ProcessCreationIncludeCmdLine_Enabled' -Value 1 -Type DWord
    auditpol /set /subcategory:'{0CCE922B-69AE-11D9-BED3-505054503030}' /success:enable /failure:enable | Out-Null
    HLog 'OK' 'audit: Process Creation + cmdline diaktifkan (event 4688)'
} catch { HLog 'WARN' "audit gagal: $($_.Exception.Message)" }
try {
    $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging'
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name 'EnableScriptBlockLogging' -Value 1 -Type DWord
    HLog 'OK' 'PowerShell ScriptBlockLogging diaktifkan'
} catch { HLog 'WARN' "scriptblock gagal: $($_.Exception.Message)" }

# ---------- 6. Anti-poisoning LLMNR ----------
try {
    $k = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'
    if (-not (Test-Path $k)) { New-Item $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name 'EnableMulticast' -Value 0 -Type DWord
    HLog 'OK' 'LLMNR dimatikan (anti name-resolution poisoning di LAN)'
} catch { HLog 'WARN' "LLMNR gagal: $($_.Exception.Message)" }

# ---------- 7. RDP tetap tolak ----------
try {
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 1 -Type DWord
    HLog 'OK' 'RDP: fDenyTSConnections=1 (ditolak)'
} catch { HLog 'WARN' "RDP gagal: $($_.Exception.Message)" }

# ---------- 8. Hapus OpenSSH Server (pintu SSH permanen tertutup) ----------
try {
    $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
    if ($cap -and $cap.State -eq 'Installed') {
        Stop-Service sshd -Force -EA 0
        Set-Service sshd -StartupType Disabled -EA 0
        $cap | Remove-WindowsCapability -Online | Out-Null
        HLog 'OK' 'OpenSSH.Server DIHAPUS dari Windows'
    } elseif ($cap) { HLog 'OK' "OpenSSH.Server sudah tidak terpasang ($($cap.State))" }
    # sisa konfigurasi/kunci host
    if (Test-Path 'C:\ProgramData\ssh') {
        Remove-Item 'C:\ProgramData\ssh' -Recurse -Force
        HLog 'OK' 'Folder sisa C:\ProgramData\ssh dihapus'
    }
} catch { HLog 'WARN' "OpenSSH gagal: $($_.Exception.Message)" }

HLog 'INFO' '===== HARDENING SELESAI ====='
HLog 'INFO' 'Revert: lihat README.md (daftar perubahan + cara membatalkan)'
