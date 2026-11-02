# InnVin: установка ежедневной копии Москвы на ПК (один раз, от своего пользователя, без прав администратора):
#   powershell -ExecutionPolicy Bypass -File pc\install-task.ps1
# Копирует backup-msk.ps1 и run-hidden.vbs в %USERPROFILE%\InnVin (не в AppData: у приложений из Microsoft Store
# AppData виртуальная — Планировщик её не видит) и создаёт задание Планировщика
# «InnVin — копия Москвы»: каждый день в 13:00, если ПК был выключен — при первой возможности, без окна.
# Нужно: в %USERPROFILE%\.ssh\config запись Host msk (root@195.133.10.220 по ключу). Файл в UTF-8 с BOM.
$ErrorActionPreference = 'Stop'
$dst = Join-Path $env:USERPROFILE 'InnVin'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Copy-Item -Force -Path (Join-Path $PSScriptRoot 'backup-msk.ps1'), (Join-Path $PSScriptRoot 'run-hidden.vbs') -Destination $dst

$action    = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\wscript.exe') -Argument ('"{0}"' -f (Join-Path $dst 'run-hidden.vbs'))
$trigger   = New-ScheduledTaskTrigger -Daily -At '13:00'
$settings  = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
               -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
$principal = New-ScheduledTaskPrincipal -UserId ('{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName 'InnVin — копия Москвы' -Description 'Копия данных проектов с сервера Москва (195.133.10.220) в Яндекс.Диск: D:\YandexDisk\Yandex.Disk\Бэкапы\Сервер-Москва. Скрипт: %USERPROFILE%\InnVin\backup-msk.ps1' `
  -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Write-Output "Задание создано. Скрипты: $dst"
