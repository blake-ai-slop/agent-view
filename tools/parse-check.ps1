# Parse mọi *.ps1 trong repo (bỏ thư mục ẩn/tạm của công cụ) bằng parser của PowerShell đang chạy (dùng powershell.exe 5.1).
# Cũng báo file có ký tự ngoài ASCII mà thiếu BOM UTF-8: PS 5.1 sẽ đọc nhầm thành ANSI.
# In lỗi, exit 1 nếu có lỗi.
$root = Split-Path -Parent $PSScriptRoot
$failed = 0
$files = @(Get-ChildItem -Path $root -Recurse -File -Filter '*.ps1' |
  Where-Object { $_.FullName.Substring($root.Length) -notmatch '(^|[\\/])\.[^\\/]+([\\/]|$)' })
foreach ($f in $files) {
  $rel = $f.FullName.Substring($root.Length + 1)
  $tokens = $null; $errors = $null
  $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
  foreach ($e in @($errors)) {
    $failed++
    Write-Output ("{0}:{1}:{2}: {3}" -f $rel, $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message)
  }
  $bytes = [IO.File]::ReadAllBytes($f.FullName)
  $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  if (-not $bom) {
    foreach ($b in $bytes) { if ($b -gt 0x7F) { $failed++; Write-Output "${rel}: có ký tự ngoài ASCII nhưng thiếu BOM UTF-8"; break } }
  }
}
Write-Output ("parse-check: {0} file, {1} lỗi" -f $files.Count, $failed)
if ($failed -gt 0) { exit 1 }
exit 0
