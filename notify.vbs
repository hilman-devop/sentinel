' Sentinel: luncurkan notify.ps1 TANPA jendela konsol (dipanggil task SentinelNotify tiap 5 menit).
' wscript.exe tak punya jendela; Run(...,0,False) => powershell dibuat sudah tersembunyi (tidak kedip).
CreateObject("WScript.Shell").Run _
  "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""C:\TheGame\Sentinel\notify.ps1""", 0, False
