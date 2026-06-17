# el-commander (cm) installer for Windows (PowerShell).
#
# Usage:
#   irm https://raw.githubusercontent.com/elkaszcz/el-commander-releases/main/install.ps1 | iex
#
# Downloads the latest release, verifies its Minisign signature and SHA-256
# checksum, installs cm.exe to ~\tools, adds ~\tools to your user PATH, and
# installs a `cm` wrapper that follows el-commander into its last directory
# when you quit.
$ErrorActionPreference = "Stop"

$Repo       = "elkaszcz/el-commander-releases"
$InstallDir = Join-Path $HOME "tools"
# Release signing key (#28). Must match MINISIGN_PUBKEY in the binary
# (crates/elc-app/src/update.rs) and the -P key in release.yml.
$MinisignPubKey = "RWQ2phjehTa48pOz8sOJEliKh7S5FVT+YBcyerOJTjrBXwsX7oAkWAwD"

function Fail($msg) { Write-Host "Error: $msg" -ForegroundColor Red; exit 1 }

# 1. Detect architecture (only the 64-bit x86 build is published).
$arch = $env:PROCESSOR_ARCHITECTURE
if ($arch -ne "AMD64") {
    Fail "Unsupported architecture: $arch (only 64-bit x86 Windows builds are published)."
}
$target = "x86_64-pc-windows-msvc"

# 2. Resolve the latest release tag.
Write-Host "Fetching latest release of $Repo ..."
$rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
                         -Headers @{ "User-Agent" = "cm-install" }
$tag = $rel.tag_name
if (-not $tag) { Fail "Could not determine the latest release tag." }
Write-Host "Latest version: $tag"

$asset = "cm-$tag-$target.zip"
$base  = "https://github.com/$Repo/releases/download/$tag"
$tmp   = Join-Path $env:TEMP ("cm-install-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    # 3. Download the archive, the checksum manifest, and its signature.
    $zip = Join-Path $tmp $asset
    Write-Host "Downloading $asset ..."
    Invoke-WebRequest -Uri "$base/$asset" -OutFile $zip -UseBasicParsing
    $sums = Join-Path $tmp "SHA256SUMS"
    Write-Host "Downloading SHA256SUMS ..."
    Invoke-WebRequest -Uri "$base/SHA256SUMS" -OutFile $sums -UseBasicParsing
    $sig = Join-Path $tmp "SHA256SUMS.minisig"
    Write-Host "Downloading SHA256SUMS.minisig ..."
    Invoke-WebRequest -Uri "$base/SHA256SUMS.minisig" -OutFile $sig -UseBasicParsing

    # 3b. Verify the SHA256SUMS signature against the release key (#28). A
    #     leaked publish token is then insufficient to ship a malicious binary:
    #     forging the manifest requires the (separate) signing key.
    $minisign = Get-Command minisign -ErrorAction SilentlyContinue
    if ($minisign) {
        Write-Host "Verifying signature ..."
        & $minisign.Source -Vm $sums -x $sig -P $MinisignPubKey | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail "Signature verification failed -- refusing to install." }
    } else {
        Write-Host "Warning: minisign not installed; skipping signature verification." -ForegroundColor Yellow
        Write-Host "         The SHA-256 checksum is still enforced below. For full" -ForegroundColor Yellow
        Write-Host "         verification install minisign: https://jedisct1.github.io/minisign/" -ForegroundColor Yellow
    }

    # 4. Verify the checksum before installing.
    Write-Host "Verifying checksum ..."
    $line = Get-Content $sums | Where-Object { $_ -match ([regex]::Escape($asset) + '$') } | Select-Object -First 1
    if (-not $line) { Fail "No checksum entry found for $asset." }
    $expected = ($line -split '\s+')[0].ToLower()
    $actual   = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToLower()
    if ($expected -ne $actual) { Fail "Checksum mismatch -- refusing to install." }

    # 5. Extract and install.
    Write-Host "Installing to $InstallDir ..."
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $bin = Get-ChildItem -Path $tmp -Filter "cm.exe" -Recurse | Select-Object -First 1
    if (-not $bin) { Fail "cm.exe not found inside the archive." }
    Copy-Item -Path $bin.FullName -Destination (Join-Path $InstallDir "cm.exe") -Force

    # 6. Add ~\tools to the user PATH.
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$InstallDir*") {
        $newPath = if ($userPath) { "$userPath;$InstallDir" } else { $InstallDir }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "Added $InstallDir to your user PATH."
    }

    # 7. Install the `cm` directory-follow wrapper into the PowerShell profile.
    $marker = "# >>> el-commander (cm) >>>"
    if (-not (Test-Path $PROFILE) -or -not (Select-String -Path $PROFILE -SimpleMatch $marker -Quiet)) {
        $profileDir = Split-Path $PROFILE -Parent
        if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
        $wrapper = @'

# >>> el-commander (cm) >>>
function cm {
    & "$HOME\tools\cm.exe" @args
    $lastdir = Join-Path $HOME ".cache\el-commander\lastdir"
    if (Test-Path $lastdir) {
        $dir = (Get-Content -Raw $lastdir).Trim()
        if ($dir -and (Test-Path -PathType Container $dir) -and ($dir -ne $PWD.Path)) {
            Set-Location $dir
        }
    }
}
# <<< el-commander (cm) <<<
'@
        Add-Content -Path $PROFILE -Value $wrapper
        Write-Host "Added cm directory-follow wrapper to $PROFILE."
    }

    Write-Host ""
    Write-Host "Success: cm $tag installed to $InstallDir\cm.exe" -ForegroundColor Green
    Write-Host "Open a new terminal for PATH and profile changes to take effect, then run: cm"
}
catch {
    Fail $_.Exception.Message
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
