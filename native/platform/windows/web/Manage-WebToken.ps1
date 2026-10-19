# SPDX-License-Identifier: BSD-3-Clause
# Prototype setup only. Default is read-only; never changes an official binding.
[CmdletBinding()]
param([ValidateSet('Plan','Install','Remove')][string]$Action='Plan')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$packageRoot=$PSScriptRoot
if (-not [Environment]::Is64BitProcess) { throw 'Use a 64-bit PowerShell process.' }
$target=Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'CIE ID Flutter Prototype\WebToken'
$helper=Join-Path $packageRoot 'cie_web_registration.exe'
$dll=Join-Path $packageRoot 'cie_prototype_minidriver.dll'
if ($Action -eq 'Plan') {
  $signature=Get-AuthenticodeSignature -LiteralPath $dll
  Write-Output ('Authenticode: '+$signature.Status)
  & $helper --plan
  if ($LASTEXITCODE -ne 0) { throw 'Plan incomplete; no system changes.' }
  return
}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this explicit setup action in an administrator PowerShell window.'
}
if ($Action -eq 'Install') {
  if (Test-Path -LiteralPath $target) { throw 'Prototype installation already exists. Review/remove it explicitly before installing another build.' }
  $manifest=Get-Content -LiteralPath (Join-Path $packageRoot 'web-package-manifest.json') -Raw | ConvertFrom-Json
  foreach ($entry in $manifest.files.PSObject.Properties) {
    if ($entry.Name -match '(^[\\/]|\.\.|:)' ) { throw 'Unsafe package path.' }
    $source=Join-Path $packageRoot $entry.Name
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) { throw ('Package hash mismatch: '+$entry.Name) }
  }
  # Require CIE identity discovery first, without VERIFY; protected certificate
  # discovery may return code 8, but an unrecognized card must never register.
  $env:PATH=(Join-Path $packageRoot 'backend')+';'+$env:PATH
  $probe=& (Join-Path $packageRoot 'backend\tests\cie_web_probe.exe')
  $probeCode=$LASTEXITCODE
  if ($probeCode -notin @(0,8) -or ($probe | ConvertFrom-Json).status -ne 'discovery_complete') { throw 'CIE discovery failed; no registration.' }
  New-Item -ItemType Directory -Path $target | Out-Null
  try {
    Copy-Item -LiteralPath $dll -Destination $target
    Copy-Item -LiteralPath $helper -Destination $target
    Copy-Item -LiteralPath (Join-Path $packageRoot 'backend') -Destination $target -Recurse
    # System-loaded code must not remain writable by a normal user.
    & icacls.exe $target /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' /T /Q
    if ($LASTEXITCODE -ne 0) { throw 'Cannot secure prototype directory.' }
    & icacls.exe $target /setowner '*S-1-5-32-544' /T /Q
    if ($LASTEXITCODE -ne 0) { throw 'Cannot set administrator ownership.' }
    & (Join-Path $target 'cie_web_registration.exe') --install (Join-Path $target 'cie_prototype_minidriver.dll')
    if ($LASTEXITCODE -ne 0) { throw 'Registration refused or failed. Existing card types were not replaced.' }
  } catch {
    # Keep secured files if registration is uncertain; never leave a registered
    # DLL path pointing to removed code. Remove remains an explicit action.
    throw
  }
  Write-Output 'Prototype registered. Browser authentication still requires a separate real test. Protected Windows services may require Microsoft signing; this setup does not alter those policies.'
} else {
  if (-not (Test-Path -LiteralPath $target)) { throw 'Prototype installation not found.' }
  & (Join-Path $target 'cie_web_registration.exe') --remove
  if ($LASTEXITCODE -ne 0) { throw 'Removal not completed. Files retained.' }
  Remove-Item -LiteralPath $target -Recurse -Force
}
