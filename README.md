# Sentinel — Windows Hardening Monitor

![PowerShell](https://img.shields.io/badge/PowerShell-2f81f7?style=flat) ![Windows Event Log](https://img.shields.io/badge/Windows_Event_Log-2f81f7?style=flat) ![Scheduled Task](https://img.shields.io/badge/Scheduled_Task-2f81f7?style=flat) ![ACL](https://img.shields.io/badge/ACL-2f81f7?style=flat)

> Eksperimen defensive security untuk menerapkan baseline hardening lalu memantau drift konfigurasi.

## Tentang proyek

Eksperimen defensive security untuk menerapkan baseline hardening lalu memantau drift konfigurasi. Dokumentasi ini dibuat sebagai panduan singkat untuk memahami ruang lingkup proyek, menjalankannya secara lokal, dan membaca batasan penggunaannya.

## Fitur utama

- Hardening port dan konfigurasi tertentu
- Audit event 4688 dan ScriptBlockLogging
- Perbandingan baseline berkala
- Logging dan proteksi folder berbasis ACL
- Pemulihan atau pemeriksaan setelah reboot

## Teknologi

- PowerShell
- Windows Event Log
- Scheduled Task
- ACL

## Menjalankan secara lokal

Prasyarat dan konfigurasi dapat berbeda menurut sistem operasi. Contoh langkah utama:

```bash
Jalankan PowerShell sebagai Administrator dan baca instruksi script sebelum menerapkan perubahan sistem.
```

## Struktur dan pengembangan

Mulai dari entry point dan folder konfigurasi proyek. Pisahkan credential lokal dari source code, tambahkan test untuk perubahan penting, dan gunakan environment variable untuk konfigurasi deployment.

## Keamanan

- Jangan commit API key, password, token, session ID, atau data pribadi.
- Gunakan file environment lokal dan contoh konfigurasi tanpa nilai rahasia.
- Uji perubahan pada environment development sebelum deployment.

## Status

Proyek ini merupakan bagian dari portofolio **Hilman Arifin Ilham** dan dapat dikembangkan sesuai kebutuhan penggunaan.

> **Catatan:** Uji di VM atau mesin non-produksi terlebih dahulu. Script hardening dapat mengubah konfigurasi jaringan, policy, dan service Windows.

## Lisensi

Belum ada lisensi open-source yang dinyatakan di repository ini. Hubungi pemilik repository sebelum menggunakan ulang atau mendistribusikan kode.

---

Dibuat oleh [Hilman Arifin Ilham](https://github.com/hilman-devop).
