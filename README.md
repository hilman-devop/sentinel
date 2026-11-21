# Sentinel — Hardening & Monitor Windows

> Sistem proteksi Windows buatan sendiri: hardening awal lalu pemantauan berkelanjutan dengan membandingkan state terhadap baseline.

## ✨ Fitur

- Hardening: blokir port, matikan LLMNR/RDP
- Audit event 4688 + ScriptBlockLogging
- Diff baseline.json setiap 10 menit
- Log 1GB tahan-hilang
- Kunci folder via ACL
- Lapis cadangan pasca-reboot

## 🛠 Tech Stack

"PowerShell" "Windows Scheduled Task" "Event Log" "ACL"

## 🚀 Menjalankan

```
# jalankan dengan hak admin
.\hardening.ps1
.\monitor.ps1
```

## 📌 Catatan

Proyek ini merupakan bagian dari portofolio pribadi. Kode disusun untuk kebutuhan nyata,
bukan sekadar demo, sehingga sebagian konfigurasi spesifik lingkungan mungkin perlu
disesuaikan sebelum dijalankan.
