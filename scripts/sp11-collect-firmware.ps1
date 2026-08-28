# SPDX-License-Identifier: MIT
# Copyright (c) 2026 turbinebmw
#
# Surface Pro 11 firmware collector (run from Windows).
#
# Copies the five Qualcomm/Microsoft firmware files that Linux needs for
# audio, microphones, sensors, the CDSP, and GPU acceleration out of this
# computer's own Windows driver store. Nothing is downloaded or uploaded.
#
# Usage (normally started by RUN-IN-WINDOWS.cmd on the live USB):
#   powershell -ExecutionPolicy Bypass -File .\sp11-collect-firmware.ps1 -TargetSP11FW
#   powershell -ExecutionPolicy Bypass -File .\sp11-collect-firmware.ps1 -OutputDirectory D:\SP11-FIRMWARE
#
# Works with the built-in Windows PowerShell 5.1 and with PowerShell 7.

param(
    [string]$OutputDirectory = "",
    [switch]$TargetSP11FW,
    [switch]$PreferKnown,
    [string]$WindowsDirectory = $env:WINDIR
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# What we need
# ---------------------------------------------------------------------------
$required = @(
    @{ Path = "qcom/x1e80100/microsoft/Denali/adsp_dtb.mbn";  Component = "adsp"; Names = @("adsp_dtbs.elf", "adsp_dtb.mbn"); Purpose = "Surface ADSP device tree" },
    @{ Path = "qcom/x1e80100/microsoft/Denali/qcadsp8380.mbn"; Component = "adsp"; Names = @("qcadsp8380.mbn");               Purpose = "Surface ADSP image (audio, sensors, battery)" },
    @{ Path = "qcom/x1e80100/microsoft/Denali/cdsp_dtb.mbn";  Component = "cdsp"; Names = @("cdsp_dtbs.elf", "cdsp_dtb.mbn"); Purpose = "Surface CDSP device tree" },
    @{ Path = "qcom/x1e80100/microsoft/Denali/qccdsp8380.mbn"; Component = "cdsp"; Names = @("qccdsp8380.mbn");               Purpose = "Surface CDSP image" },
    @{ Path = "qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn";     Component = "gpu";  Names = @("qcdxkmsuc8380.mbn");            Purpose = "Adreno GPU zap shader (GPU acceleration)" }
)

# Hashes exercised on the maintainer's unit. Informational: newer driver
# packages are accepted and expected after Windows Update.
$knownGood = @{
    "544bd795cb06cf8dee8119ede2a667f01066b2f1b9e4348f1772d080e2026ff4" = "adsp_dtb (Surface ADSP driver 8100.1.1.139)"
    "921870a839ee2aba647b04598d62ed96f3d2d5dfbb2499fc842f9a6ff0e0da13" = "qcadsp8380 (Surface ADSP driver 8100.1.1.139)"
    "444f79a6eb0f5309e12a953be4fe15a76a633a7864ac5217d0cadd13427ed1fb" = "cdsp_dtb (CDSP driver, mid 2025)"
    "b2ed1656c46b116f7a2adedce8e4502a2f8ed5e223b82e0ac6cc70e451d58ecc" = "qccdsp8380 (CDSP driver, mid 2025)"
    "93941f040da14b8305d39579686d886706d22954a538b03da676c1aaa191797f" = "cdsp_dtb (CDSP driver 30.0.0219.1000)"
    "4a67a03367f2eff2f8a0e867ca25d2bf2fcd5aee3e41e2c9f436c804e257c789" = "qccdsp8380 (CDSP driver 30.0.0219.1000)"
    "c89711a60240f29cb5df13f7b904642b78b7d9d6e614473751f7bf4049fab137" = "qcdxkmsuc8380 (Adreno driver 31.0.137.0)"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Utf8NoBom([string]$Path, [string[]]$Lines) {
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), $encoding)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-DriverRank([string]$PackageDirectory) {
    # Sortable "yyyyMMdd-v1.v2.v3.v4" string from the package INF DriverVer.
    $best = "00000000-000000.000000.000000.000000"
    foreach ($inf in Get-ChildItem -LiteralPath $PackageDirectory -Filter *.inf -File -ErrorAction SilentlyContinue) {
        try { $text = Get-Content -LiteralPath $inf.FullName -Raw -ErrorAction Stop } catch { continue }
        $match = [regex]::Match($text, 'DriverVer\s*=\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*,\s*([\d.]+)', 'IgnoreCase')
        if (-not $match.Success) { continue }
        $parts = @($match.Groups[4].Value.Split('.') | ForEach-Object { if ($_ -match '^\d+$') { [int]$_ } else { 0 } })
        while ($parts.Count -lt 4) { $parts += 0 }
        $rank = "{0:D4}{1:D2}{2:D2}-{3:D6}.{4:D6}.{5:D6}.{6:D6}" -f `
            [int]$match.Groups[3].Value, [int]$match.Groups[1].Value, [int]$match.Groups[2].Value, `
            $parts[0], $parts[1], $parts[2], $parts[3]
        if ($rank -gt $best) { $best = $rank }
    }
    return $best
}

function Format-Rank([string]$Rank) {
    if ($Rank.StartsWith("0000")) { return "unknown version" }
    $date = $Rank.Substring(0, 4) + "-" + $Rank.Substring(4, 2) + "-" + $Rank.Substring(6, 2)
    $version = ($Rank.Substring(9).Split('.') | ForEach-Object { [int]$_ }) -join '.'
    return "$date v$version"
}

# ---------------------------------------------------------------------------
# Output target
# ---------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $WindowsDirectory -PathType Container)) {
    throw "Windows directory was not found: $WindowsDirectory"
}
$targetVolumeMode = $false
if ($TargetSP11FW -and -not [string]::IsNullOrWhiteSpace($OutputDirectory)) {
    throw "-TargetSP11FW cannot be combined with -OutputDirectory"
}
if ($TargetSP11FW) {
    $volumes = @(Get-Volume -FileSystemLabel "SP11FW" -ErrorAction SilentlyContinue)
    if ($volumes.Count -ne 1) {
        throw "Expected exactly one mounted SP11FW volume, found $($volumes.Count). Plug in the SP11 live USB and make sure Windows shows the SP11FW drive."
    }
    $volume = $volumes[0]
    if ($null -eq $volume.DriveLetter) { throw "SP11FW has no drive letter; assign one in Disk Management" }
    $partition = Get-Partition -DriveLetter $volume.DriveLetter
    $disk = Get-Disk -Number $partition.DiskNumber
    if ($disk.BusType -ne "USB") { throw "Refusing: SP11FW is not on a USB disk (disk $($disk.Number))" }
    $OutputDirectory = "$($volume.DriveLetter):\"
    $targetVolumeMode = $true
} elseif ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot "SP11-FIRMWARE"
}
if (-not $targetVolumeMode -and (Test-Path -LiteralPath $OutputDirectory)) {
    throw "Refusing to replace existing output: $OutputDirectory (delete it first)"
}

# ---------------------------------------------------------------------------
# Discover candidates
# ---------------------------------------------------------------------------
$system32 = Join-Path $WindowsDirectory "System32"
$repository = Join-Path (Join-Path $system32 "DriverStore") "FileRepository"
if (-not (Test-Path -LiteralPath $repository -PathType Container)) {
    throw "Windows driver store was not found: $repository"
}
$wanted = @{}
foreach ($entry in $required) { foreach ($name in $entry.Names) { $wanted[$name.ToLowerInvariant()] = $entry.Path } }

Write-Host "Scanning the Windows driver store ..."
$candidates = @{}
foreach ($entry in $required) { $candidates[$entry.Path] = @() }
$reportLines = @("candidate`tpackage`tdriver_version`tbytes`tsha256`tknown")
foreach ($package in Get-ChildItem -LiteralPath $repository -Directory -ErrorAction SilentlyContinue) {
    $hits = @(Get-ChildItem -LiteralPath $package.FullName -File -ErrorAction SilentlyContinue |
        Where-Object { $wanted.ContainsKey($_.Name.ToLowerInvariant()) })
    if ($hits.Count -eq 0) { continue }
    $rank = Get-DriverRank $package.FullName
    foreach ($hit in $hits) {
        $hash = Get-Sha256 $hit.FullName
        $known = if ($knownGood.ContainsKey($hash)) { $knownGood[$hash] } else { "" }
        $candidates[$wanted[$hit.Name.ToLowerInvariant()]] += [PSCustomObject]@{
            File = $hit; Package = $package.Name; Rank = $rank; Hash = $hash; Known = $known
            Note = "DriverStore $($package.Name) ($(Format-Rank $rank))"
        }
        $reportLines += "$($hit.FullName)`t$($package.Name)`t$(Format-Rank $rank)`t$($hit.Length)`t$hash`t$known"
    }
}
$deployedGpu = Join-Path $system32 "qcdxkmsuc8380.mbn"
if (Test-Path -LiteralPath $deployedGpu -PathType Leaf) {
    $file = Get-Item -LiteralPath $deployedGpu
    $hash = Get-Sha256 $file.FullName
    $known = if ($knownGood.ContainsKey($hash)) { $knownGood[$hash] } else { "" }
    $candidates["qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn"] += [PSCustomObject]@{
        File = $file; Package = "System32"; Rank = "99991231-999999.999999.999999.999999"; Hash = $hash; Known = $known
        Note = "Windows\System32 (currently deployed copy)"
    }
    $reportLines += "$($file.FullName)`tSystem32`tdeployed`t$($file.Length)`t$hash`t$known"
}

# ---------------------------------------------------------------------------
# Select one coherent package per component
# ---------------------------------------------------------------------------
function Save-Report([string]$Directory) {
    try {
        $reportPath = Join-Path $Directory "SP11-FIRMWARE-COLLECTOR-REPORT.tsv"
        Write-Utf8NoBom $reportPath $reportLines
        Write-Warning "Saved a list of everything that was found: $reportPath"
    } catch { }
}

$chosen = @{}
try {
    foreach ($component in @("adsp", "cdsp", "gpu")) {
        $paths = @($required | Where-Object { $_.Component -eq $component } | ForEach-Object { $_.Path })
        $packages = @{}
        foreach ($path in $paths) {
            foreach ($candidate in $candidates[$path]) {
                if (-not $packages.ContainsKey($candidate.Package)) { $packages[$candidate.Package] = @{} }
                $current = $packages[$candidate.Package][$path]
                if ($null -eq $current -or $candidate.Rank -gt $current.Rank) { $packages[$candidate.Package][$path] = $candidate }
            }
        }
        $complete = @($packages.Keys | Where-Object { $members = $packages[$_]; @($paths | Where-Object { -not $members.ContainsKey($_) }).Count -eq 0 })
        if ($complete.Count -eq 0) {
            $missing = @($paths | Where-Object { $candidates[$_].Count -eq 0 })
            throw "No driver package on this computer contains every $($component.ToUpper()) file (missing: $($missing -join ', ')). Windows Update usually restores them; otherwise install the latest Surface drivers and retry."
        }
        $best = $null
        $bestKey = ""
        foreach ($name in $complete) {
            $members = $packages[$name]
            $allKnown = @($paths | Where-Object { -not $members[$_].Known }).Count -eq 0
            $rank = ($paths | ForEach-Object { $members[$_].Rank } | Sort-Object -Descending | Select-Object -First 1)
            $key = if ($PreferKnown) { "$([int]$allKnown)-$rank" } else { "$rank-$([int]$allKnown)" }
            if ($key -gt $bestKey) { $bestKey = $key; $best = $members }
        }
        foreach ($path in $paths) { $chosen[$path] = $best[$path] }
    }
} catch {
    if ($targetVolumeMode) { Save-Report $OutputDirectory } else { Save-Report $PSScriptRoot }
    throw
}

# ---------------------------------------------------------------------------
# Write the pack
# ---------------------------------------------------------------------------
$stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sp11-firmware-" + [System.Guid]::NewGuid().ToString("N"))
$staging = Join-Path $stagingRoot "pack"
New-Item -ItemType Directory -Path $staging | Out-Null
try {
    $manifest = @("manifest_version`tpath`tbytes`tsha256`tcomponent`tsource_package`tselection`tcandidate_names`tpurpose")
    $report = @(
        "Surface Pro 11 firmware pack",
        "Created: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')) UTC",
        "Source: Windows installation at $WindowsDirectory",
        "",
        "These files belong to Microsoft/Qualcomm and were copied from your own",
        "Windows installation. Do not upload or redistribute this directory.",
        ""
    )
    Write-Host ""
    Write-Host "Selected firmware:"
    foreach ($entry in $required) {
        $candidate = $chosen[$entry.Path]
        $flag = if ($candidate.Known) { "known-good" } else { "newest-driver" }
        Write-Host "  $($entry.Path)"
        Write-Host "      $($candidate.Note) [$flag]"
        $destination = Join-Path $staging (("usr/lib/firmware/" + $entry.Path) -replace '/', [string][System.IO.Path]::DirectorySeparatorChar)
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $candidate.File.FullName -Destination $destination
        $manifest += "2`t$($entry.Path)`t$($candidate.File.Length)`t$($candidate.Hash)`t$($entry.Component)`t$($candidate.Package)`t$flag`t$($entry.Names -join ',')`t$($entry.Purpose)"
        $report += $entry.Path
        $report += "    from: $($candidate.File.FullName)"
        $report += "    $($candidate.Note)"
        $report += "    $($candidate.File.Length) bytes, sha256 $($candidate.Hash)"
        $report += "    " + $(if ($candidate.Known) { "known-good: $($candidate.Known)" } else { "not seen on the maintainer's unit yet (normal after Windows Update); Linux validates it at boot" })
    }
    Write-Utf8NoBom (Join-Path $staging "SP11-FIRMWARE-MANIFEST.tsv") $manifest
    Write-Utf8NoBom (Join-Path $staging "SP11-FIRMWARE-REPORT.txt") $report
    Write-Utf8NoBom (Join-Path $staging "README.txt") @(
        "SP11 external firmware pack", "",
        "These files were copied from the device owner's Windows installation.",
        "Do not upload, publish, or redistribute this directory.")

    if ($targetVolumeMode) {
        Copy-Item -Path (Join-Path $staging "*") -Destination $OutputDirectory -Recurse -Force
        $stale = Join-Path $OutputDirectory "SP11-FIRMWARE-COLLECTOR-REPORT.tsv"
        if (Test-Path -LiteralPath $stale) { Remove-Item -LiteralPath $stale -Force }
    } else {
        $parent = Split-Path -Parent $OutputDirectory
        if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Move-Item -LiteralPath $staging -Destination $OutputDirectory
    }
} finally {
    if (Test-Path -LiteralPath $stagingRoot) { Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Host ""
if ($targetVolumeMode) {
    Write-Host "Done. The firmware is now on the live USB partition SP11FW ($OutputDirectory)."
    Write-Host "Safely eject the USB drive, then boot the Surface from it."
} else {
    Write-Host "Done. Firmware pack: $OutputDirectory"
    Write-Host "Copy its contents onto the SP11FW partition of the live USB."
}
