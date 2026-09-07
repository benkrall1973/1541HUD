param(
    [Parameter(Mandatory=$true)]
    [string]$TestName,

    [string]$Repo = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$Git = "git"
$BuildDir = Join-Path $Repo "build-1541hud"
$BundleRoot = Join-Path $BuildDir ("SOURCE_BUNDLES\" + $TestName)
$SourceRoot = Join-Path $BundleRoot "source"

New-Item -ItemType Directory -Force -Path $SourceRoot | Out-Null

Push-Location $Repo
try {
    $branch = (& $Git rev-parse --abbrev-ref HEAD).Trim()
    $commit = (& $Git rev-parse HEAD).Trim()

    if ($branch -ne "dev-1541hud") {
        throw "Refusing to preserve from unexpected branch '$branch'. Expected dev-1541hud."
    }

    # Capture repository state first.
    (& $Git status --porcelain=v1 --untracked-files=all) |
        Set-Content -Encoding UTF8 (Join-Path $BundleRoot "git-status.txt")
    (& $Git diff --binary) |
        Set-Content -Encoding UTF8 (Join-Path $BundleRoot "working-tree.patch")
    (& $Git diff --cached --binary) |
        Set-Content -Encoding UTF8 (Join-Path $BundleRoot "index.patch")
    (& $Git log -1 --decorate --stat --oneline) |
        Set-Content -Encoding UTF8 (Join-Path $BundleRoot "git-head.txt")
    $commit | Set-Content -Encoding ASCII (Join-Path $BundleRoot "git-commit.txt")
    $branch | Set-Content -Encoding ASCII (Join-Path $BundleRoot "git-branch.txt")

    # Copy every tracked file plus every untracked, non-ignored file.
    # This preserves experimental source files that have not yet been committed.
    $files = & $Git ls-files -co --exclude-standard
    foreach ($rel in $files) {
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }

        # Keep generated build outputs out of source/, but capture selected
        # firmware artifacts separately below.
        if ($rel -like "build-1541hud/*" -or
            $rel -like "build-drivehud/*" -or
            $rel -like ".git/*") {
            continue
        }

        $src = Join-Path $Repo $rel
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue }

        $dst = Join-Path $SourceRoot $rel
        $dstDir = Split-Path -Parent $dst
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        Copy-Item -LiteralPath $src -Destination $dst -Force
    }

    # Capture matching firmware outputs if present.
    $artifactDir = Join-Path $BundleRoot "artifacts"
    New-Item -ItemType Directory -Force -Path $artifactDir | Out-Null

    $candidateArtifacts = Get-ChildItem -Path $BuildDir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like "*.uf2" -or
            $_.Name -like "*.bin" -or
            $_.Name -like "*.elf" -or
            $_.Name -like "*.map"
        }

    foreach ($f in $candidateArtifacts) {
        Copy-Item $f.FullName (Join-Path $artifactDir $f.Name) -Force
    }

    # Produce hashes for every preserved file.
    $manifest = Join-Path $BundleRoot "SHA256SUMS.txt"
    $allFiles = Get-ChildItem -Path $BundleRoot -Recurse -File |
        Where-Object { $_.FullName -ne $manifest } |
        Sort-Object FullName

    $lines = foreach ($f in $allFiles) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
        $rel = $f.FullName.Substring($BundleRoot.Length + 1).Replace('\','/')
        "$hash  $rel"
    }
    $lines | Set-Content -Encoding ASCII $manifest

    # Human-readable metadata.
    @"
1541HUD TEST SOURCE BUNDLE

Test: $TestName
Branch: $branch
Commit: $commit
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss zzz")

Contents:
- complete tracked source tree
- all untracked non-ignored source/files
- working-tree binary-capable patch
- staged/index patch
- git branch + commit metadata
- matching build artifacts found in build-1541hud
- SHA-256 manifest for every preserved file

This bundle is intended to make the test independently reconstructable later.
"@ | Set-Content -Encoding UTF8 (Join-Path $BundleRoot "README.txt")

    # Recompute manifest to include README.
    $allFiles = Get-ChildItem -Path $BundleRoot -Recurse -File |
        Where-Object { $_.FullName -ne $manifest } |
        Sort-Object FullName
    $lines = foreach ($f in $allFiles) {
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
        $rel = $f.FullName.Substring($BundleRoot.Length + 1).Replace('\','/')
        "$hash  $rel"
    }
    $lines | Set-Content -Encoding ASCII $manifest

    $zip = Join-Path $BuildDir ($TestName + "_FULL_SOURCE_BUNDLE.zip")
    if (Test-Path $zip) { Remove-Item $zip -Force }
    Compress-Archive -Path (Join-Path $BundleRoot "*") -DestinationPath $zip -CompressionLevel Optimal

    Write-Host ""
    Write-Host "SOURCE PRESERVATION COMPLETE"
    Write-Host "Bundle directory: $BundleRoot"
    Write-Host "ZIP:              $zip"
    Write-Host "ZIP SHA256:"
    Get-FileHash -Algorithm SHA256 $zip
}
finally {
    Pop-Location
}
