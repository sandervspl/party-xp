[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$artifactDirectory = Join-Path $root "artifacts"
New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null
$artifact = Join-Path $artifactDirectory "party-xp-e2e.tap"
Push-Location $root
try {
    # Some Windows Busted wrappers emit a harmless WSL startup warning on stderr.
    $ErrorActionPreference = "Continue"
    busted --output=TAP 2>&1 | Tee-Object -FilePath $artifact
    $testExitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($testExitCode -ne 0) {
        throw "Busted failed with exit code $testExitCode. See $artifact"
    }
    Write-Host "Test artifact: $artifact"
}
finally {
    Pop-Location
}
