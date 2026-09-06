# SPDX-License-Identifier: MIT
# Copyright (c) 2026 turbinebmw
#
# Surface Pro 11 Linux: USB stick creator for Windows.
#
# Does the whole Windows side in one go, without Rufus or Etcher:
#   1. collects the five firmware files from this Windows installation
#      (sp11-collect-firmware.ps1, must sit next to this script);
#   2. writes the beta ISO to a USB stick sector by sector, exactly like
#      "dd" on Linux (the ISO is a hybrid image with three partitions, which
#      tools that "extract" an ISO onto a stick get wrong);
#   3. copies the firmware onto the stick's SP11FW partition.
#
# Usage (normally started by SP11-USB-CREATOR.cmd, which asks for admin):
#   powershell -ExecutionPolicy Bypass -File .\sp11-usb-creator.ps1 -Iso .\sp11-linux-beta-20260905-aarch64.iso
#   ... -DiskNumber 2      pick the stick without the menu
#   ... -SkipFirmware      only write the ISO (firmware can be added later with RUN-IN-WINDOWS.cmd)
#
# Needs an administrator PowerShell (5.1 or 7) and a stick of at least 4 GB.
# Everything on the stick is erased.

param(
    [string]$Iso = "",
    [int]$DiskNumber = -1,
    [switch]$SkipFirmware,
    [string]$WindowsDirectory = $env:WINDIR
)

$ErrorActionPreference = "Stop"
$script:ExitCode = 0

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "ERROR: $Message" -ForegroundColor Red
    throw $Message
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail "Run this as administrator (right-click SP11-USB-CREATOR.cmd > Run as administrator)."
}

# ---------------------------------------------------------------------------
# 1. The ISO
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($Iso)) {
    $candidates = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter "sp11-linux-beta-*-aarch64.iso" -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($candidates.Count -eq 0) {
        Fail "No sp11-linux-beta-*-aarch64.iso next to this script. Download it from the release and put it in the same folder, or pass -Iso <path>."
    }
    $Iso = $candidates[0].FullName
}
$Iso = (Resolve-Path -LiteralPath $Iso).Path
$isoInfo = Get-Item -LiteralPath $Iso
if ($isoInfo.Length -lt 1GB) { Fail "That does not look like the live ISO (smaller than 1 GB): $Iso" }
Write-Host "ISO: $Iso ($([math]::Round($isoInfo.Length / 1MB)) MB)"

$sums = Join-Path (Split-Path -Parent $Iso) "SHA256SUMS"
if (Test-Path -LiteralPath $sums) {
    $expected = (Get-Content -LiteralPath $sums | Where-Object { $_ -match [regex]::Escape($isoInfo.Name) } | Select-Object -First 1)
    if ($expected) {
        Write-Host "Verifying the ISO against SHA256SUMS (takes a moment) ..."
        $actual = (Get-FileHash -LiteralPath $Iso -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($expected.Split(' ')[0].ToLowerInvariant() -ne $actual) { Fail "ISO checksum mismatch. Download it again." }
        Write-Host "ISO checksum OK."
    }
}

# ---------------------------------------------------------------------------
# 2. Firmware first, so a stick is never wiped for nothing
# ---------------------------------------------------------------------------
$pack = $null
if (-not $SkipFirmware) {
    $collector = Join-Path $PSScriptRoot "sp11-collect-firmware.ps1"
    if (-not (Test-Path -LiteralPath $collector)) { Fail "sp11-collect-firmware.ps1 is missing next to this script." }
    $pack = Join-Path $env:TEMP ("sp11-firmware-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
    Write-Host ""
    Write-Host "Collecting firmware from this Windows installation ..."
    & $collector -OutputDirectory $pack -WindowsDirectory $WindowsDirectory
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { Fail "Firmware collection failed (see the report next to the collector)." }
    if (-not (Test-Path -LiteralPath (Join-Path $pack "SP11-FIRMWARE-MANIFEST.tsv"))) { Fail "Firmware collection produced no manifest." }
}

# ---------------------------------------------------------------------------
# 3. Pick the stick
# ---------------------------------------------------------------------------
$usb = @(Get-Disk | Where-Object { $_.BusType -eq "USB" } | Sort-Object Number)
if ($usb.Count -eq 0) { Fail "No USB disk found. Plug the stick in and try again." }
if ($DiskNumber -lt 0) {
    Write-Host ""
    Write-Host "USB disks:"
    foreach ($d in $usb) {
        Write-Host ("  [{0}] {1}  {2} GB" -f $d.Number, $d.FriendlyName.Trim(), [math]::Round($d.Size / 1GB, 1))
    }
    $answer = Read-Host "Disk number to ERASE and write the ISO to"
    if ($answer -notmatch '^\d+$') { Fail "Not a disk number." }
    $DiskNumber = [int]$answer
}
$disk = $usb | Where-Object { $_.Number -eq $DiskNumber } | Select-Object -First 1
if ($null -eq $disk) { Fail "Disk $DiskNumber is not a USB disk. Refusing." }
if ($disk.Size -lt $isoInfo.Length + 1MB) { Fail "Disk $DiskNumber is too small for the ISO." }
if ($disk.IsBoot -or $disk.IsSystem) { Fail "Disk $DiskNumber is the Windows system disk. Refusing." }
Write-Host ""
Write-Host ("About to ERASE disk {0}: {1} ({2} GB)" -f $disk.Number, $disk.FriendlyName.Trim(), [math]::Round($disk.Size / 1GB, 1)) -ForegroundColor Yellow
$confirm = Read-Host "Type ERASE to continue"
if ($confirm -cne "ERASE") { Fail "Cancelled." }

# ---------------------------------------------------------------------------
# 4. Raw write (dd)
# ---------------------------------------------------------------------------
$sector = [int]$disk.LogicalSectorSize
if ($sector -le 0) { $sector = 512 }
Write-Host "Removing the old partitions ..."
Get-Disk -Number $DiskNumber | Get-Partition -ErrorAction SilentlyContinue | ForEach-Object {
    Get-Volume -Partition $_ -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.DriveLetter) { Write-Host "  dismounting $($_.DriveLetter):" }
    }
}
Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
Set-Disk -Number $DiskNumber -IsReadOnly $false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$path = "\\.\PhysicalDrive$DiskNumber"
$chunk = 4MB
$buffer = New-Object byte[] $chunk
$total = $isoInfo.Length
$head = 1MB   # partition tables live here; written last so Windows does not
              # mount the new partitions while the rest is still being written
$source = [System.IO.File]::OpenRead($Iso)
$output = New-Object System.IO.FileStream($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, $chunk, [System.IO.FileOptions]::WriteThrough)
try {
    $script:written = 0
    $sw = [Diagnostics.Stopwatch]::StartNew()
    function Write-Range([long]$From, [long]$To) {
        $source.Position = $From
        $output.Position = $From
        $pos = $From
        while ($pos -lt $To) {
            $want = [int][math]::Min($chunk, $To - $pos)
            $read = $source.Read($buffer, 0, $want)
            if ($read -le 0) { break }
            $aligned = $read
            if ($read % $sector -ne 0) {
                $aligned = $read + ($sector - ($read % $sector))
                [Array]::Clear($buffer, $read, $aligned - $read)
            }
            $output.Write($buffer, 0, $aligned)
            $pos += $read
            $script:written += $read
            if (($script:written % (64MB)) -lt $chunk) {
                $pct = [math]::Round(100 * $script:written / $total)
                $rate = if ($sw.Elapsed.TotalSeconds -gt 0) { [math]::Round($script:written / 1MB / $sw.Elapsed.TotalSeconds, 1) } else { 0 }
                Write-Progress -Activity "Writing the ISO to disk $DiskNumber" -Status "$pct % ($rate MB/s)" -PercentComplete $pct
            }
        }
    }
    Write-Host "Writing $([math]::Round($total / 1MB)) MB to $path ..."
    Write-Range $head $total
    Write-Range 0 $head
    $output.Flush($true)
    Write-Progress -Activity "Writing the ISO to disk $DiskNumber" -Completed
    Write-Host ("Written in {0:N0} s." -f $sw.Elapsed.TotalSeconds)
} finally {
    $output.Dispose()
    $source.Dispose()
}

# ---------------------------------------------------------------------------
# 5. Firmware onto SP11FW
# ---------------------------------------------------------------------------
Write-Host "Letting Windows rescan the stick ..."
"rescan" | & diskpart.exe | Out-Null
Update-Disk -Number $DiskNumber -ErrorAction SilentlyContinue
$volume = $null
for ($i = 0; $i -lt 30 -and $null -eq $volume; $i++) {
    Start-Sleep -Seconds 1
    $volume = Get-Volume -FileSystemLabel "SP11FW" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $volume -and -not $volume.DriveLetter) {
        $partition = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Where-Object { (Get-Volume -Partition $_ -ErrorAction SilentlyContinue).FileSystemLabel -eq "SP11FW" } | Select-Object -First 1
        if ($partition) { $partition | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction SilentlyContinue }
        $volume = $null
    }
}
if ($null -eq $volume) {
    Write-Host ""
    Write-Host "The stick is written, but Windows has not shown the SP11FW partition yet." -ForegroundColor Yellow
    Write-Host "Unplug and replug it, open the SP11FW drive and run RUN-IN-WINDOWS.cmd to add the firmware."
    if ($pack) { Write-Host "The collected firmware pack is at $pack" }
} elseif ($pack) {
    $target = "$($volume.DriveLetter):\"
    Write-Host "Copying the firmware onto SP11FW ($target) ..."
    Copy-Item -Path (Join-Path $pack "*") -Destination $target -Recurse -Force
    Remove-Item -LiteralPath $pack -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ""
    Write-Host "Done. Firmware is on the stick." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Done (no firmware step). Run RUN-IN-WINDOWS.cmd from the SP11FW drive to add it later." -ForegroundColor Green
}
Write-Host "Safely eject the stick, then on the Surface: Volume-Down + Power to boot from USB (Secure Boot off)."
