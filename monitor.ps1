<#
  SENTINEL - Sistem proteksi buatan sendiri (monitor)
  Jalankan manual : powershell -EP Bypass -File monitor.ps1 -Run
  Buat baseline   : powershell -EP Bypass -File monitor.ps1 -Baseline
  Mode task       : powershell -EP Bypass -File monitor.ps1 -Task   (dipanggil scheduled task tiap 10 menit)

  Yang dipantau:
   A. Kebangkitan Monarch/Mxs (file, service, task, registry, driver)
   B. Service / scheduled task / WMI subscription (filter+consumer+binding) / Run key BARU vs baseline
   H. Akses jarak jauh (RDP / WinRM / Remote Assistance / RemoteRegistry / RemoteAccess / portproxy) harus MATI
   C. Port listening BARU vs baseline
   D. Koneksi keluar ke domain terlarang (blocklist.txt) + IP mesh tailscale 100.x
   E. Firewall mati / SSH hidup lagi / hosts dibobol / audit log dibersihkan
   F. File sistem kritis berubah (hosts, hosts-file sentuhan sistem)
  Peringatan -> sentinel.log + Event Log aplikasi (source: Sentinel) + sentinel-alert.log
#>
param(
    [switch]$Baseline,
    [switch]$Run,
    [switch]$Task
)
$ErrorActionPreference = 'SilentlyContinue'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$fBase    = Join-Path $root 'baseline.json'
$fLog     = Join-Path $root 'sentinel.log'
$fAlert   = Join-Path $root 'sentinel-alert.log'
$fBlock   = Join-Path $root 'blocklist.txt'
$fBlockIP = Join-Path $root 'blocklist-ip.txt'

# Prefix SID lokal untuk deteksi ACE asing; tersedia juga saat task berjalan sebagai SYSTEM.
$machineSid = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -EA 0 |
    Where-Object { $_.PSChildName -match '^S-1-5-21-' } |
    Select-Object -First 1 -ExpandProperty PSChildName
$machineSid = $machineSid -replace '-\d+$',''

# Tulis 1 baris ke sentinel-alert.log.
# AUTO-HEAL: file ini pernah terkunci proses lain (mode baca-saja: rename diizinkan,
# tulis ditolak) -> Add-Content gagal SENYAP dan alert hilang dari file notifikasi
# (kasus 13 Nov 2026: 411 alert hanya ada di sentinel.log/Event Log, nol di file ini).
# Kalau tulis gagal: pindahkan file terkunci (rename), buat baru berisi isi lama + baris ini,
# sehingga jumlah baris tetap naik dan notify.ps1 tidak kehilangan hitungan.
function Write-AlertLine($line) {
    try { Add-Content -Path $fAlert -Value $line -Encoding UTF8 -ErrorAction Stop; return } catch {}
    # KUNCI TERDETEKSI -> siapa pelakunya? Tangkap basah pakai handle.exe (Sysinternals,
    # tanda tangan CN=Microsoft Corporation) SEBELUM file dipindah. Jalur error saja,
    # tidak pernah dijalankan saat normal. Output -> sentinel.log.
    $fHandle = Join-Path $root 'handle.exe'
    if (Test-Path $fHandle) {
        try {
            $who = & $fHandle -accepteula -nobanner -a 'sentinel-alert.log' 2>&1 | Out-String
            $hits = @($who -split "`r?`n" | Where-Object { $_ -match 'pid:\s*\d+' -and $_ -match 'sentinel-alert' })
            if ($hits.Count) {
                foreach ($h in $hits) { Add-Content -Path $fLog -Value ("{0} [CRIT] PEMEGANG FILE: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $h.Trim()) -Encoding UTF8 }
            } else {
                Add-Content -Path $fLog -Value ("{0} [INFO] handle.exe: tidak ada pemegang terdeteksi (butuh elevasi utk melihat proses lain / pelaku sudah lepas)" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
            }
        } catch {
            Add-Content -Path $fLog -Value ("{0} [INFO] handle.exe gagal dijalankan: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) -Encoding UTF8
        }
    }
    try {
        $old  = @(Get-Content -Path $fAlert -ErrorAction Stop)
        $held = Join-Path $root ("sentinel-alert.locked-{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
        Move-Item -Path $fAlert -Destination $held -Force -ErrorAction Stop
        Set-Content -Path $fAlert -Value $old -Encoding UTF8 -ErrorAction Stop
        Add-Content -Path $fAlert -Value $line -Encoding UTF8 -ErrorAction Stop
        Add-Content -Path $fLog -Value ("{0} [INFO] auto-heal: sentinel-alert.log terkunci proses lain - isi lama ({1} baris) dipindah ke {2}, alert tetap tersimpan" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $old.Count, $held) -Encoding UTF8
    } catch {
        # kegagalan total: baris TETAP tercatat di sentinel.log + Event Log (lihat SLog)
        Add-Content -Path $fLog -Value ("{0} [CRIT] auto-heal GAGAL: alert hilang dari file notifikasi - {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $_.Exception.Message) -Encoding UTF8
    }
}

function SLog($sev, $msg) {
    $line = "{0} [{1}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $sev, $msg
    Add-Content -Path $fLog -Value $line -Encoding UTF8
    if ($sev -eq 'ALERT' -or $sev -eq 'CRIT') {
        Write-AlertLine $line
        try { Write-EventLog -LogName Application -Source 'Sentinel' -EventId 9001 -EntryType Warning -Message $line } catch {}
    }
    if (-not $Task) { Write-Host $line }
}

# ---------- pengumpul state ----------
function Get-State {
    $st = [ordered]@{}

    # A. jejak Monarch yang harus tetap mati
    $st.monarchFiles = @(
        'C:\Program Files\Monarch', 'C:\ProgramData\Monarch'
    ) | Where-Object { Test-Path $_ }
    $st.monarchSvc = (Get-Service -EA 0 | Where-Object { $_.Name -match '^Mxs' } |
        ForEach-Object { "$($_.Name)=$($_.Status)/$($_.StartType)" })
    $st.sshd = (Get-Service sshd -EA 0 | ForEach-Object { "$($_.Status)/$($_.StartType)" })
    $st.monarchProc = (Get-Process -EA 0 | Where-Object { $_.ProcessName -match 'Mxs|monarch' } |
        ForEach-Object { $_.ProcessName })

    # B. service non-Microsoft auto/running (whitelist: GoogleUpdater resmi - jangan masuk baseline)
    $st.services = (Get-CimInstance Win32_Service -EA 0 | Where-Object {
        $_.StartMode -eq 'Auto' -and $_.State -eq 'Running' -and $_.PathName -notmatch '\\Windows\\' -and $_.Name -notmatch 'GoogleUpdater'
    } | ForEach-Object { "$($_.Name)|$($_.PathName)" } | Sort-Object)

    # scheduled task (nama + path)
    $st.tasks = (Get-ScheduledTask -EA 0 | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" } | Sort-Object)

    # WMI subscription permanen: FILTER + CONSUMER + BINDING sekaligus.
    # (persistensi fileless klasik; filter tanpa consumer tak berbahaya, tapi binding baru = red flag)
    $st.wmi = @()
    foreach ($f in (Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -EA 0)) {
        $st.wmi += "FILTER|$($f.Name)|$($f.Query)"
    }
    foreach ($c in (Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer -EA 0)) {
        $st.wmi += "CONSUMER|$($c.Name)|$($c.CimClass.CimClassName)"
    }
    foreach ($b in (Get-CimInstance -Namespace root\subscription -ClassName __FilterToConsumerBinding -EA 0)) {
        $st.wmi += "BINDING|$($b.Filter)|$($b.Consumer)"
    }
    $st.wmi = @($st.wmi | Sort-Object)

    # Run/RunOnce keys (HKLM + semua hive user nyata S-1-5-21-*)
    # Catatan: HKCU bergantung konteks (SYSTEM saat task jalan vs pengguna saat manual) -> dulu
    # menimbulkan false "hilang [runkey]" tiap scan. Pakai HKEY_USERS\<SID user> agar
    # baseline konsisten dari konteks mana pun. (hive user belum dimuat saat boot sebelum
    # login -> hanya INFO sekali, bukan ALERT)
    $rk = @()
    foreach ($p in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                   'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
                   'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run') {
        $it = Get-Item $p -EA 0
        if ($it) { foreach ($n in $it.GetValueNames()) { if ($n) { $rk += "$p|$n=$($it.GetValue($n))" } } }
    }
    foreach ($hk in (Get-ChildItem 'Registry::HKEY_USERS' -EA 0 | Where-Object { $_.PSChildName -match '^S-1-5-21-\d+-\d+-\d+-\d+$' })) {
        foreach ($rel in 'Software\Microsoft\Windows\CurrentVersion\Run',
                         'Software\Microsoft\Windows\CurrentVersion\RunOnce') {
            $p = "Registry::HKEY_USERS\$($hk.PSChildName)\$rel"
            $it = Get-Item $p -EA 0
            if ($it) { foreach ($n in $it.GetValueNames()) { if ($n) { $rk += "$($hk.PSChildName)\$rel|$n=$($it.GetValue($n))" } } }
        }
    }
    $st.runKeys = ($rk | Sort-Object)

    # boot/logon hijack points
    $st.winlogon = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -EA 0).Shell
    $st.appinit  = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows' -EA 0).AppInit_DLLs
    $st.ifEO = (Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -EA 0 |
        ForEach-Object { $_.PSChildName } | Sort-Object)

    # C. port listening non-loopback
    #    Kunci = "alamat:port|nama proses" TANPA PID.
    #    PID berubah tiap reboot (proses Windows start ulang) -> kalau ikut dibandingkan,
    #    tiap reboot selalu memicu ~15 alert palsu. Nama proses tetap dipakai supaya
    #    port yang dialihkan ke proses beda tetap terdeteksi.
    $st.listeners = (Get-NetTCPConnection -State Listen -EA 0 |
        Where-Object { $_.LocalAddress -ne '127.0.0.1' -and $_.LocalAddress -ne '::1' } |
        ForEach-Object {
            $pn = (Get-Process -Id $_.OwningProcess -EA 0).ProcessName
            "$($_.LocalAddress):$($_.LocalPort)|$pn"
        } | Sort-Object)

    # E. pertahanan inti (filter null: tanpa ini, hasil kosong jadi @($null) -> false positive)
    $st.firewallOff = @((Get-NetFirewallProfile -EA 0 | Where-Object { $_.Enabled -eq $false }).Name | Where-Object { $_ })
    $st.hostsHasBlock = $false
    $hostsContent = Get-Content "$env:SystemRoot\System32\drivers\etc\hosts" -EA 0
    $domains = Get-Content $fBlock -EA 0 | Where-Object { $_ -and $_ -notmatch '^\s*#' }
    $missing = @($domains | Where-Object { $d = $_; -not ($hostsContent | Where-Object { $_ -match "(^|\s)$([regex]::Escape($d))(\s|$)" }) })
    if ($missing.Count -eq 0) { $st.hostsHasBlock = $true }
    $st.missingHosts = $missing

    # G. ACE "asing" pada folder user (SID bukan akun mesin ini / akun sudah dihapus).
    #    Dulu Codex sandbox menempel puluhan SID acak ke folder user; sekarang dipantau.
    $st.foreignAcl = @()
    $watch = @($root, $env:USERPROFILE)
    $watch += @(Get-ChildItem $root -Directory -Force -EA 0 | ForEach-Object { $_.FullName })
    foreach ($w in ($watch | Sort-Object -Unique)) {
        $acl = Get-Acl $w -EA 0
        if (-not $acl) { continue }
        foreach ($ace in $acl.Access) {
            $id = $ace.IdentityReference.Value
            if ($id -match '^S-1-5-21-' -and $id -notlike "$machineSid-*") {
                $st.foreignAcl += "$w|$id|$($ace.FileSystemRights)"
            }
        }
    }
    $st.foreignAcl = @($st.foreignAcl | Sort-Object -Unique)

    # H. akses jarak jauh - semuanya HARUS mati. Nilai mentah disimpan utk cek eksplisit.
    $st.rdpDeny      = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -EA 0).fDenyTSConnections
    $ra              = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -EA 0
    $st.raHelp       = $ra.fAllowToGetHelp
    $st.raFull       = $ra.fAllowFullControl
    $st.winrm        = "$((Get-Service WinRM -EA 0).Status)/$((Get-Service WinRM -EA 0).StartType)"
    $st.remotereg    = "$((Get-Service RemoteRegistry -EA 0).Status)/$((Get-Service RemoteRegistry -EA 0).StartType)"
    $st.remoteaccess = "$((Get-Service RemoteAccess -EA 0).Status)/$((Get-Service RemoteAccess -EA 0).StartType)"
    $st.portproxy    = ((netsh interface portproxy show all 2>$null) -join ';').Trim()

    return $st
}

# ---------- D. koneksi keluar berbahaya ----------
function Test-Egress {
    $bad = @()
    $domains = Get-Content $fBlock -EA 0 | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }
    $ips = @()
    foreach ($d in $domains) { $ips += ,@($d, (Resolve-DnsName $d -Type A -EA 0 | ForEach-Object { $_.IPAddress })) }
    $ips += ,@('TAILSCALE-MESH', @())
    $conns = Get-NetTCPConnection -State Established -EA 0 | Where-Object { $_.RemoteAddress -ne '127.0.0.1' }
    foreach ($c in $conns) {
        foreach ($e in $ips) {
            if ($e[1] -contains $c.RemoteAddress) {
                $pn = (Get-Process -Id $c.OwningProcess -EA 0).ProcessName
                $bad += "konek ke $($e[0]) ($($c.RemoteAddress):$($c.RemotePort)) via $pn"
            }
        }
        # mesh tailscale / CGNAT 100.64-127 = khas jaringan peer-to-peer attacker
        if ($c.RemoteAddress -match '^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.') {
            $pn = (Get-Process -Id $c.OwningProcess -EA 0).ProcessName
            $bad += "koneksi CGNAT/mesh 100.x ke $($c.RemoteAddress):$($c.RemotePort) via $pn"
        }
    }
    return $bad
}

# ---------- perbandingan ----------
function Compare-List($name, $base, $now) {
    $b = @($base); $n = @($now)
    $added   = @($n | Where-Object { $b -notcontains $_ })
    $removed = @($b | Where-Object { $n -notcontains $_ })
    foreach ($a in $added)   { SLog 'ALERT' "BARU [$name]: $a" }
    foreach ($r in $removed) { SLog 'INFO' "hilang [$name]: $r" }
    return $added.Count
}

# ================= MAIN =================
if (-not $Baseline -and -not $Run -and -not $Task) { $Run = $true }
$cur = Get-State

if ($Baseline) {
    $cur | ConvertTo-Json -Depth 6 | Set-Content $fBase -Encoding UTF8
    SLog 'OK' "BASELINE disimpan: $($cur.tasks.Count) task, $($cur.services.Count) service, $($cur.listeners.Count) listener"
    exit 0
}

if (-not (Test-Path $fBase)) {
    SLog 'CRIT' 'baseline.json belum ada - jalankan: monitor.ps1 -Baseline'
    exit 1
}
$base = Get-Content $fBase -Raw | ConvertFrom-Json
$alerts = 0

# A. kebangkitan Monarch - hanya PERUBAHAN vs baseline yang dianggap serangan.
#    File yang sudah ada di baseline = sisa yang belum dihapus user (bukan intrusion).
foreach ($f in @($cur.monarchFiles) | Where-Object { $_ }) {
    if (@($base.monarchFiles) -notcontains $f) { SLog 'ALERT' "MONARCH FILE MUNCUL (tidak ada saat baseline): $f"; $alerts++ }
}
foreach ($s in @($cur.monarchSvc) | Where-Object { $_ }) {
    if ($s -match 'Running|Auto') { SLog 'ALERT' "MONARCH SERVICE HIDUP: $s"; $alerts++ }
}
foreach ($p in @($cur.monarchProc) | Where-Object { $_ }) { SLog 'ALERT' "MONARCH PROSES HIDUP: $p"; $alerts++ }
foreach ($g in @($base.monarchFiles)) {
    if (@($cur.monarchFiles) -notcontains $g) { SLog 'OK' "folder Monarch sudah dihapus: $g" }
}
if ($cur.sshd -match 'Running|Auto') { SLog 'ALERT' "sshd hidup lagi: $($cur.sshd)"; $alerts++ }

# B. diff massal
# whitelist service resmi yang muncul-hilang sesaat (terverifikasi signature CN=Google LLC)
$svcWhite = 'GoogleUpdater'
$baseSvc = @($base.services  | Where-Object { $_ -notmatch $svcWhite })
$curSvc  = @($cur.services   | Where-Object { $_ -notmatch $svcWhite })
$alerts += Compare-List 'service'  $baseSvc  $curSvc
# task compare hanya saat admin/SYSTEM: non-admin hanya melihat ~177 task (bukan 243) ->
# menimbulkan puluhan baris INFO "hilang" palsu. Scan resmi tetap jalan via SentinelWatch (SYSTEM).
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) { $alerts += Compare-List 'task' $base.tasks $cur.tasks }
else { SLog 'INFO' "scan non-admin: view task terbatas ($(@($cur.tasks).Count) vs baseline $(@($base.tasks).Count)) - perbandingan task dilewati (scan resmi: SentinelWatch/SYSTEM)" }
$alerts += Compare-List 'wmi'      $base.wmi       $cur.wmi
$alerts += Compare-List 'runkey'   $base.runKeys    $cur.runKeys
$alerts += Compare-List 'ifEO'     $base.ifEO       $cur.ifEO

# boot hijack
if ($cur.winlogon -ne $base.winlogon) { SLog 'ALERT' "Winlogon Shell berubah: '$($base.winlogon)' -> '$($cur.winlogon)'"; $alerts++ }
if ($cur.appinit -ne $base.appinit)   { SLog 'ALERT' "AppInit_DLLs berubah: '$($base.appinit)' -> '$($cur.appinit)'"; $alerts++ }

# H. akses jarak jauh harus tetap MATI
if ($cur.rdpDeny -ne 1) { SLog 'CRIT' "RDP AKTIF (fDenyTSConnections=$($cur.rdpDeny))"; $alerts++ }
if ($cur.raHelp -ne 0 -or $cur.raFull -ne 0) { SLog 'CRIT' "Remote Assistance AKTIF (help=$($cur.raHelp), full=$($cur.raFull))"; $alerts++ }
if ($cur.winrm -notmatch '^Stopped/')        { SLog 'CRIT'  "WinRM AKTIF: $($cur.winrm)"; $alerts++ }
if ($cur.remotereg -notmatch '^Stopped/')    { SLog 'ALERT' "RemoteRegistry AKTIF: $($cur.remotereg)"; $alerts++ }
if ($cur.remoteaccess -notmatch '^Stopped/') { SLog 'ALERT' "RemoteAccess(ICS/RRAS) AKTIF: $($cur.remoteaccess)"; $alerts++ }
if ($cur.portproxy) { SLog 'CRIT' "PORT PROXY muncul: $($cur.portproxy)"; $alerts++ }

# C. port baru
$alerts += Compare-List 'listener' $base.listeners $cur.listeners

# G. ACE asing pada folder user (perubahan izin yg mencurigakan)
$alerts += Compare-List 'acl-asing' $base.foreignAcl $cur.foreignAcl

# E. pertahanan inti
foreach ($p in $cur.firewallOff) { SLog 'CRIT' "FIREWALL PROFIL MATI: $p"; $alerts++ }
if (-not $cur.hostsHasBlock) { SLog 'CRIT' "hosts file kehilangan blokir: $($cur.missingHosts -join ', ')"; $alerts++ }

# audit log dibersihkan (event 1102) dalam 12 jam terakhir
$clr = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=1102; StartTime=(Get-Date).AddHours(-12)} -MaxEvents 3 -EA 0
foreach ($e in @($clr)) { SLog 'ALERT' "AUDIT LOG DIBERSIHKAN $($e.TimeCreated) oleh $($e.MachineName)"; $alerts++ }

# D. egress
foreach ($b in (Test-Egress)) { SLog 'CRIT' "EGRESS: $b"; $alerts++ }

if ($alerts -eq 0) { SLog 'OK' "scan bersih ($(@($cur.tasks).Count) task, $(@($cur.listeners).Count) port)" }
else { SLog 'CRIT' "TOTAL $alerts temuan - lihat baris ALERT/CRIT di atas" }

# -Task: selalu exit code 0 supaya Task Scheduler tidak error-retry
exit 0
