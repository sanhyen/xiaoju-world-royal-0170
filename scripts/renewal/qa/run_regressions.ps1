param(
  [Parameter(Mandatory=$true)][string]$Stage,
  [string]$Runtime = '',
  [string]$Preview = '',
  [string]$EvidenceRoot = ''
)
$ErrorActionPreference = 'Stop'
$workspace = 'D:\xiaojuWorld'
$evidence = Join-Path $workspace 'renewal\work\session_20261105'
if ($EvidenceRoot) { $evidence = $EvidenceRoot }
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$jobs = @()
foreach ($mode in @('islandwalk','wheel')) {
  $profile = Join-Path $evidence ($Stage + '_' + $mode + '_profile')
  $stdout = Join-Path $evidence ($Stage + '_' + $mode + '.log')
  $stderr = Join-Path $evidence ($Stage + '_' + $mode + '.stderr.log')
  $arguments = @('renewal/tools/probe.sh','--headless',"--renewal-probe=$mode",("--probe-profile=" + $profile.Replace('\','/')))
  if ($Runtime) { $arguments += ('--probe-runtime="' + $Runtime.Replace('\','/') + '"') }
  if ($Preview) { $arguments += ('--island-rebuild=' + $Preview) }
  $process = Start-Process -FilePath 'C:\Program Files\Git\bin\bash.exe' -ArgumentList $arguments -WorkingDirectory $workspace -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
  $jobs += @{ mode=$mode; process=$process; profile=$profile }
}
$results = @{}
foreach ($job in $jobs) {
  if (!$job.process.WaitForExit(240000)) { throw ('Probe timeout: ' + $job.mode) }
  $leaf = if ($job.mode -eq 'islandwalk') { 'island_walk.txt' } else { 'wheel_test.txt' }
  $source = Join-Path $job.profile ('Godot\app_userdata\小鞠世界 · 海风与星光\' + $leaf)
  $destination = Join-Path $evidence ($Stage + '_' + $job.mode + '.txt')
  Copy-Item -LiteralPath $source -Destination $destination
  $content = Get-Content -LiteralPath $destination -Raw
  $pass = if ($job.mode -eq 'islandwalk') {
    $content -match 'VERDICT bridge_and_stairs=PASS'
  } else {
    $content -match 'walk_to_deck reached=true' -and $content -match 'seated riding=true' -and $content -match 'save_written=true' -and $content -match 'player_follow_err=0.00m'
  }
  $results[$job.mode] = @{ pass=$pass; evidence=$destination }
}
$json = $results | ConvertTo-Json -Depth 4
$json | Set-Content -LiteralPath (Join-Path $evidence ($Stage + '_regressions.json')) -Encoding utf8
Write-Output $json
if (@($results.Values | Where-Object { !$_.pass }).Count -gt 0) { exit 1 }
