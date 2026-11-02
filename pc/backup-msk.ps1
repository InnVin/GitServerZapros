# InnVin: ежедневная копия данных с сервера Москва на ПК — в Яндекс.Диск.
# Запускает Планировщик Windows (задание «InnVin — копия Москвы», 13:00) через run-hidden.vbs; установка — install-task.ps1.
# ssh msk innvin-backup → временный файл → проверка архива (tar -tzf) → innvin-ГГГГ-ММ-ДД.tar.gz. Хранятся 30 последних.
# При ошибке старые копии не трогаются. Журнал — backup.log в той же папке. Файл в UTF-8 с BOM (иначе PowerShell 5.1 портит кириллицу).
$ErrorActionPreference = 'Stop'
$Dir  = 'D:\YandexDisk\Yandex.Disk\Бэкапы\Сервер-Москва'
$Keep = 30
$Ssh  = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
$Tar  = Join-Path $env:WINDIR 'System32\tar.exe'
$Log  = Join-Path $Dir 'backup.log'

function Write-Log([string]$msg) {
  Add-Content -Path $Log -Value ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), $msg) -Encoding UTF8
}

# Запуск программы: stdout — двоичным потоком в файл (или в никуда), stderr — текстом. Без cmd и без порчи данных.
function Invoke-Native([string]$file, [string]$arguments, [string]$outFile) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $file; $psi.Arguments = $arguments
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $err = $p.StandardError.ReadToEndAsync()
  if ($outFile) { $fs = [System.IO.File]::Create($outFile) } else { $fs = [System.IO.Stream]::Null }
  try { $p.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Dispose() }
  $p.WaitForExit()
  return @{ Code = $p.ExitCode; Err = $err.Result }
}

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$name  = 'innvin-{0}.tar.gz' -f (Get-Date -Format 'yyyy-MM-dd')
$final = Join-Path $Dir $name
$tmp   = Join-Path $env:TEMP 'innvin-backup.tar.gz.part'   # вне Яндекс.Диска: недописанный файл не уходит в облако
try {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  $r = Invoke-Native $Ssh '-o BatchMode=yes -o ConnectTimeout=30 -o ServerAliveInterval=30 msk innvin-backup' $tmp
  if ($r.Code -ne 0) {
    $why = (($r.Err -split "`n") | Where-Object { $_ -and $_ -notmatch 'post-quantum|store now|openssh.com/pq' } | Select-Object -Last 2) -join ' '
    throw ('ssh: код {0}. {1}' -f $r.Code, $why.Trim())
  }
  $size = (Get-Item -LiteralPath $tmp).Length
  if ($size -lt 1024) { throw "архив слишком маленький ($size байт)" }
  $t = Invoke-Native $Tar ('-tzf "{0}"' -f $tmp) $null
  if ($t.Code -ne 0) { throw 'архив повреждён (tar -tzf не прочитал его)' }
  Move-Item -LiteralPath $tmp -Destination $final -Force
  # хранить $Keep последних копий
  Get-ChildItem -LiteralPath $Dir -Filter 'innvin-*.tar.gz' | Sort-Object Name -Descending |
    Select-Object -Skip $Keep | Remove-Item -Force
  Write-Log ('OK      {0}  {1:N1} МБ' -f $name, ($size / 1MB))
  exit 0
} catch {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  Write-Log ('ОШИБКА  ' + $_.Exception.Message)
  exit 1
}
