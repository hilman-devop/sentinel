#Requires -RunAsAdministrator
# CROSS-CHECK KESELAMATAN PENUH - 9 Nov 2026
$ErrorActionPreference = 'SilentlyContinue'
$out = @()
function P($s) { $script:out += $s }

P '########## CROSS-CHECK KESELAMATAN PENUH ##########'
P "waktu: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# ---- 1. Proses yang jalan 90 menit terakhir (4688) - sumber jendela misterius ----
P ''
P '=== 1. PROSES 90 MENIT TERAKHIR (Security 4688 + cmdline) ==='
$ev = @(Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4688; StartTime=(Get-Date).AddMinutes(-90)} -EA 0)
P "  total event: $($ev.Count)"
foreach ($e in $ev) {
    $m = $e.Message
    $proc = ([regex]::Match($m, 'New Process Name:\s+(.+)')).Groups[1].Value.Trim()
    $cmd = ([regex]::Match($m, '(?:Process )?Command Line:\s+(.+)')).Groups[1].Value.Trim()
    $p2 = [IO.Path]::GetFileName($proc)
    # tampilkan semua non-svchost/dllhost biasa
    if ($p2 -notmatch '^(svchost|csrss|smss|wininit|lsass|fontdrvhost|dwm|sihost|SearchHost|RuntimeBroker|explorer|System|Registry|Memory|idle)\.exe$') {
        P ("  [{0}] {1}" -f $e.TimeCreated.ToString('HH:mm:ss'), $proc)
        if ($cmd) { P ("         {0}" -f $cmd.Substring(0, [Math]::Min(260, $cmd.Length))) }
    }
}

# ---- 2. Pemasangan service/task baru 24 jam ----
P ''
P '=== 2. SERVICE/TASK BARU 24 JAM (7045 / 4698) ==='
$s7045 = @(Get-WinEvent -FilterHashtable @{LogName='System'; Id=7045; StartTime=(Get-Date).AddDays(-1)} -EA 0)
if ($s7045.Count) { foreach ($e in $s7045) { P "  [$($e.TimeCreated)] SERVICE: $((([regex]::Match($e.Message,'Service Name:\s+(.+)')).Groups[1].Value))" } } else { P '  nol service baru terpasang' }
$t4698 = @(Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4698; StartTime=(Get-Date).AddDays(-1)} -EA 0)
if ($t4698.Count) { foreach ($e in $t4698) { $n = ([regex]::Match($e.Message,'Task Name:\s+(.+)')).Groups[1].Value; P "  [$($e.TimeCreated)] TASK: $n" } } else { P '  nol task baru 24 jam (atau tidak terbaca)' }

# ---- 3. Log dibersihkan? ----
P ''
P '=== 3. EVENT 1102 (log dibersihkan) 24 JAM ==='
$c = @(Get-WinEvent -FilterHashtable @{LogName='Security'; Id=1102; StartTime=(Get-Date).AddDays(-1)} -EA 0)
if ($c.Count) { foreach ($e in $c) { P "  [!!!] $($e.TimeCreated) oleh $($e.MachineName)" } } else { P '  nol - tidak ada yang membersihkan log' }

# ---- 4. Login masuk 24 jam ----
P ''
P '=== 4. LOGIN 24 JAM (4624) - ringkasan per tipe ==='
$lg = @(Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624; StartTime=(Get-Date).AddDays(-1)} -EA 0)
$byType = @{}
foreach ($e in $lg) { $t = ([regex]::Match($e.Message, 'Logon Type:\s+(\d+)')).Groups[1].Value; if ($t) { $byType[$t] = 1 + [int]$byType[$t] } }
$names = @{ '2'='INTERACTIVE'; '3'='NETWORK (LAN/internet)'; '5'='SERVICE'; '7'='UNLOCK'; '10'='RDP (REMOTE)' ; '11'='CACHED' }
foreach ($k in ($byType.Keys | Sort-Object)) { P "  type $k $($names[$k]): $($byType[$k])x" }
$net = @($lg | Where-Object { ([regex]::Match($_.Message, 'Logon Type:\s+(\d+)')).Groups[1].Value -in '3','10' })
foreach ($e in ($net | Select-Object -First 10)) {
    $ip = ([regex]::Match($e.Message, 'Source Network Address:\s+([\d\.]+)')).Groups[1].Value
    $u = ([regex]::Match($e.Message, 'Account Name:\s+(\S+)')).Groups[1].Value
    if ($ip -and $ip -ne '127.0.0.1' -and $ip -ne '-') { P "  NET-LOGIN: $($e.TimeCreated) user=$u ip=$ip" }
}

# ---- 5. Koneksi keluar sekarang ----
P ''
P '=== 5. SEMUA KONEKSI ESTABLISHED KELUAR ==='
$est = @(Get-NetTCPConnection -State Established -EA 0 | Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1)' })
foreach ($c2 in $est) {
    $pn = (Get-Process -Id $c2.OwningProcess -EA 0).ProcessName
    $flag = ''
    if ($c2.RemoteAddress -match '^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.') { $flag = ' <<<< MESH 100.x (penyerang)!' }
    P "  $($c2.RemoteAddress):$($c2.RemotePort) via $pn (pid $($c2.OwningProcess))$flag"
}
$badDns = @()
foreach ($d in 'd.kuku.lu','filenowsv.com') {
    $r = @($est | Where-Object { $_.RemoteAddress -in @('172.67.73.194','104.26.10.77','104.26.11.77','104.21.18.43','172.67.180.95') })
    if ($r) { $badDns += $d }
}
if ($badDns.Count) { P "  [!!!] KONEKSI KE IP DOMAIN PENYERANG: $($badDns -join ', ')" } else { P '  nol koneksi ke IP domain penyerang' }

# ---- 6. Sweep Monarch ----
P ''
P '=== 6. SWEEP MONARCH ==='
@('C:\Program Files\Monarch','C:\ProgramData\Monarch','C:\ProgramData\ssh','C:\Windows\System32\OpenSSH','C:\Windows\System32\drivers\MxsGuard.sys') | ForEach-Object { P "  $_ => $(if (Test-Path $_) {'MASIH ADA!!!'} else {'hapus'})" }
$svc = @(Get-CimInstance Win32_Service | Where-Object { $_.Name -match 'Mxs|Monarch|^sshd' })
P "  service Mxs/Monarch/sshd: $(if ($svc.Count) {'MASIH ADA!!!'} else {'nol'})"
$drv = @(Get-CimInstance Win32_SystemDriver | Where-Object { $_.Name -match 'Mxs|Monarch' })
P "  driver Mxs/Monarch: $(if ($drv.Count) {'MASIH ADA!!!'} else {'nol'})"
$tk = @(Get-ScheduledTask | Where-Object { "$($_.TaskPath)$($_.TaskName)" -match 'Mxs|Monarch' })
P "  task Mxs/Monarch: $(if ($tk.Count) {'MASIH ADA!!!'} else {'nol'})"
$pr = @(Get-Process | Where-Object { $_.ProcessName -match 'Mxs|monarch' })
P "  proses Mxs/Monarch: $(if ($pr.Count) {'MASIH ADA!!!'} else {'nol'})"

# ---- 7. Titik hijack boot ----
P ''
P '=== 7. HIJACK POINT ==='
P "  Winlogon Shell      : $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -EA 0).Shell)"
P "  AppInit_DLLs        : '$((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -EA 0).AppInit_DLLs)'"
P "  IFEO entries        : $((Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -EA 0).Count)"
$wmi = @(Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -EA 0)
P "  WMI subscription    : $(($wmi.Name -join ', '))"
P "  Firewall profile mati: $(@(Get-NetFirewallProfile | Where-Object { $_.Enabled -eq $false }).Count) (harus 0)"
P "  hosts block         : $(if ((Get-Content "$env:SystemRoot\System32\drivers\etc\hosts") -match 'd.kuku.lu') {'ada'} else {'HILANG!!!'})"

# ---- 8. Sentinel sehat ----
P ''
P '=== 8. SENTINEL ==='
foreach ($n in 'SentinelWatch','SentinelNotify') {
    try { $t = Get-ScheduledTask -TaskName $n -EA Stop; $i = Get-ScheduledTaskInfo -TaskName $n -EA SilentlyContinue
        P "  $n : state=$($t.State) last=$($i.LastRunTime) next=$($i.NextRunTime) result=$($i.LastTaskResult)" }
    catch { P "  $n : TIDAK DITEMUKAN!!!" }
}

# ---- 9. Scan final ----
P ''
P '=== 9. SCAN FINAL (dengan whitelist GoogleUpdater) ==='
$before = @(Get-Content 'C:\TheGame\Sentinel\sentinel.log').Count
& powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\TheGame\Sentinel\monitor.ps1' -Run | Out-Null
$after = Get-Content 'C:\TheGame\Sentinel\sentinel.log' | Select-Object -Last 3
foreach ($l in $after) { P "  $l" }

P ''
P '########## SELESAI ##########'
$out | Out-File "$env:TEMP\xcheck.out" -Encoding utf8
