' InnVin: runs backup-msk.ps1 (same folder) with no window, for Windows Task Scheduler. ASCII only.
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File """ & dir & "\backup-msk.ps1"""
WScript.Quit CreateObject("WScript.Shell").Run(cmd, 0, True)
