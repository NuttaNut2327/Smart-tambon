param(
  [Parameter(Mandatory = $true)][string]$InputDocx,
  [Parameter(Mandatory = $true)][string]$OutputPdf
)

$wordApp = $null
$wordDoc = $null
try {
  $wordApp = New-Object -ComObject Word.Application
  $wordApp.Visible = $false
  $wordApp.DisplayAlerts = 0
  $resolvedInput = (Resolve-Path -LiteralPath $InputDocx).Path
  $resolvedOutput = [System.IO.Path]::GetFullPath($OutputPdf)
  $wordDoc = $wordApp.Documents.Open($resolvedInput, $false, $true)
  $wordDoc.ExportAsFixedFormat($resolvedOutput, 17)
}
finally {
  if ($null -ne $wordDoc) { $wordDoc.Close($false) }
  if ($null -ne $wordApp) { $wordApp.Quit() }
  [System.GC]::Collect()
  [System.GC]::WaitForPendingFinalizers()
}
