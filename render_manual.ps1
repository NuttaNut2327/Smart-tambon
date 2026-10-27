$ErrorActionPreference = 'Stop'
$inputPath = (Resolve-Path 'F:\ESM_work\smart-tambon\คู่มือการใช้งาน Smart Tambon ฉบับละเอียด.docx').Path
$renderDir = 'F:\ESM_work\smart-tambon\.manual_render'
New-Item -ItemType Directory -Force -Path $renderDir | Out-Null
$outputPath = Join-Path $renderDir 'manual.pdf'
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
  $doc = $word.Documents.Open($inputPath, $false, $true)
  $doc.ExportAsFixedFormat($outputPath, 17)
  $doc.Close($false)
} finally {
  $word.Quit()
}
Write-Output $outputPath
