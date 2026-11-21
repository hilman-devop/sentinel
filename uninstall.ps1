#Requires -RunAsAdministrator
<#
  Sentinel - uninstaller: hapus task, rule firewall, event source, dan folder.
  Tidak menyentuh data lain.
#>
$ErrorActionPreference = 'SilentlyContinue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Unregister-ScheduledTask -TaskName 'SentinelWatch' -Confirm:$false
Write-Host 'task SentinelWatch dihapus'

Get-NetFirewallRule -DisplayName 'Sentinel-BlockIn-*' | Remove-NetFirewallRule
Write-Host 'rule firewall Sentinel dihapus'

# buka lagi blokir hosts (baris setelah penanda)
$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$txt = Get-Content $hostsFile -EA 0
if ($txt -match 'SENTINEL BLOCK') {
    $new = @()
    $skip = $false
    foreach ($l in $txt) {
        if ($l -match 'SENTINEL BLOCK') { $skip = $true; continue }
        if ($skip -and $l -match '^0\.0\.0\.0 ') { continue }
        if ($skip -and $l -notmatch '^0\.0\.0\.0 ') { $skip = $false }
        $new += $l
    }
    Set-Content -Path $hostsFile -Value $new -Encoding ASCII
    Write-Host 'hosts dibersihkan'
}

try { Remove-EventLog -Source 'Sentinel' -EA Stop; Write-Host 'event source dihapus' } catch {}

Write-Host "Selesai. Folder $root sengaja tidak ikut terhapus (hapus manual kalau mau)."
