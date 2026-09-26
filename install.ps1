# el-commander (cm) installer for Windows (PowerShell).
#
# Usage:
#   irm https://raw.githubusercontent.com/elkaszcz/el-commander-releases/main/install.ps1 | iex
#   & ([scriptblock]::Create((irm .../install.ps1))) -WithPdf   # also install PDF support
#   & ([scriptblock]::Create((irm .../install.ps1))) -NoPdf     # don't ask about it
#
# Downloads the latest release, verifies its Minisign signature and SHA-256
# checksum, installs cm.exe to ~\tools, adds ~\tools to your user PATH, and
# installs a `cm` wrapper that follows el-commander into its last directory
# when you quit.
#
# PDF support (liteparse `lit`, for the viewer's PDF views) is optional: the
# installer asks, or -WithPdf / -NoPdf / $env:CM_WITH_PDF = 1/0 answer in
# advance. It goes to ~\.cm\tools\lit\<version>\, verified like cm, and
# `cm update` keeps it current (`cm update --with-pdf` / `--no-pdf`).
param([switch]$WithPdf, [switch]$NoPdf)
$ErrorActionPreference = "Stop"

$Repo       = "elkaszcz/el-commander-releases"
$InstallDir = Join-Path $HOME "tools"
# Release signing key (#28). Must match MINISIGN_PUBKEY in the binary
# (crates/elc-app/src/update.rs) and the -P key in release.yml.
$MinisignPubKey = "RWQ2phjehTa48pOz8sOJEliKh7S5FVT+YBcyerOJTjrBXwsX7oAkWAwD"

function Fail($msg) { Write-Host "Error: $msg" -ForegroundColor Red; exit 1 }
function Warn($msg) { Write-Host "Warning: $msg" -ForegroundColor Yellow }

# 0. Options: $wantPdf is $true / $false, or $null to ask.
if ($WithPdf -and $NoPdf) { Fail "Use either -WithPdf or -NoPdf, not both." }
$wantPdf = $null
switch -Regex ("$env:CM_WITH_PDF") {
    '^(1|y|yes|true)$'  { $wantPdf = $true }
    '^(0|n|no|false)$'  { $wantPdf = $false }
    '^$'                { }
    default             { Fail "CM_WITH_PDF must be 1 or 0 (got '$env:CM_WITH_PDF')." }
}
if ($WithPdf) { $wantPdf = $true }
if ($NoPdf)   { $wantPdf = $false }

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

    # 5b. Optional PDF support: liteparse `lit`, listed in the same verified
    #     SHA256SUMS. A failure here leaves cm installed and PDF support off.
    $pdfNote = $null
    if ($null -eq $wantPdf) {
        $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
        if ($interactive) {
            Write-Host ""
            Write-Host "Install PDF support? (liteparse ``lit``, ~12 MB download)"
            Write-Host "It adds the viewer's PDF views: Markdown and layout text (F3)."
            $answer = Read-Host "Install PDF support? [y/N]"
            $wantPdf = $answer -match '^(y|yes)$'
        } else {
            $wantPdf = $false
        }
    }
    if ($wantPdf) {
        try {
            $litLine = Get-Content $sums | Where-Object {
                $_ -match ('^[0-9a-fA-F]{64}\s+\*?(lit-(\d+\.\d+\.\d+)-' + [regex]::Escape($target) + '\.tar\.gz)$')
            } | Select-Object -First 1
            if (-not $litLine) { throw "This release has no PDF support package for $target." }
            $null = $litLine -match ('^([0-9a-fA-F]{64})\s+\*?(lit-(\d+\.\d+\.\d+)-' + [regex]::Escape($target) + '\.tar\.gz)$')
            $litExpected = $Matches[1].ToLower(); $litAsset = $Matches[2]; $litVer = $Matches[3]
            $root = Join-Path $HOME ".cm\tools\lit"
            $dest = Join-Path $root $litVer
            if (Test-Path (Join-Path $dest "lit.exe")) {
                Write-Host "PDF support (lit $litVer) is already installed."
            } else {
                Write-Host "Downloading $litAsset ..."
                $litTgz = Join-Path $tmp $litAsset
                Invoke-WebRequest -Uri "$base/$litAsset" -OutFile $litTgz -UseBasicParsing
                $litActual = (Get-FileHash -Algorithm SHA256 -Path $litTgz).Hash.ToLower()
                if ($litExpected -ne $litActual) { throw "Checksum mismatch for $litAsset." }

                # Only the expected regular files under the one expected
                # directory (cm's own installer refuses the same).
                $top = "lit-$litVer-$target"
                $listing = & tar.exe -tvzf $litTgz
                if ($LASTEXITCODE -ne 0) { throw "Cannot read $litAsset." }
                if ($listing | Where-Object { $_ -notmatch '^[-d]' }) { throw "$litAsset contains links or special files." }
                $names = & tar.exe -tzf $litTgz
                $allowed = '^' + [regex]::Escape($top) + '/((lit\.exe|pdfium\.dll)|LICENSES/([A-Za-z0-9._-]+)?)?$'
                if ($names | Where-Object { $_ -notmatch $allowed -or $_ -match '\.\.' }) {
                    throw "$litAsset holds unexpected entries."
                }

                $stage = Join-Path $root (".install-$litVer-" + [guid]::NewGuid())
                New-Item -ItemType Directory -Path $stage -Force | Out-Null
                try {
                    & tar.exe -xzf $litTgz -C $stage
                    if ($LASTEXITCODE -ne 0) { throw "Could not unpack $litAsset." }
                    $unpacked = Join-Path $stage $top
                    foreach ($f in @("lit.exe", "pdfium.dll")) {
                        if (-not (Test-Path -PathType Leaf (Join-Path $unpacked $f))) { throw "$litAsset lacks $f." }
                    }
                    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
                    Move-Item -Path $unpacked -Destination $dest
                } finally {
                    Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
                }
                $pdfNote = "PDF support (lit $litVer) installed to $dest"
            }
        } catch {
            Warn "$($_.Exception.Message) PDF support not installed."
            Write-Host "You can retry later with: cm update --with-pdf"
        }
    }

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
    if ($pdfNote) { Write-Host "Success: $pdfNote" -ForegroundColor Green }
    Write-Host "Open a new terminal for PATH and profile changes to take effect, then run: cm"
}
catch {
    Fail $_.Exception.Message
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
