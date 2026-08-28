[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

$ExpectedQcSocSha256 = "a73546cfc985de10aac843df15d753e4677beaff9f8b41c400333577d56b1188"
$ExpectedWlanSha256 = "ca884ce1a22113194f3c467f36abc39afb0c137e5a7a8e2697420438b21e4115"
$DppGuid = [Guid]"f97b8793-3abf-4719-896b-7c3e9b85e104"
$DevicePath = "\\.\QcSOCPartitionDevice"
$MaxItemBytes = 16MB

# These are the only two QcSOCPartition operations this script contains:
#   0xECAF32C6: query a DPP item's size
#   0xECAF32C2: read a DPP item
# The driver's write IOCTLs are intentionally absent.
$IoctlDppItemSize = [Convert]::ToUInt32("ECAF32C6", 16)
$IoctlDppItemRead = [Convert]::ToUInt32("ECAF32C2", 16)
$AllowedIoctls = @($IoctlDppItemSize, $IoctlDppItemRead)

$NativeSource = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class Sp11DppNative
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern SafeFileHandle CreateFile(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DeviceIoControl(
        SafeFileHandle device,
        uint controlCode,
        byte[] inputBuffer,
        uint inputLength,
        byte[] outputBuffer,
        uint outputLength,
        out uint bytesReturned,
        IntPtr overlapped);
}
'@

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run this script as Administrator. The launcher will request elevation."
    }
}

function Get-DriverEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required installed driver was not found: $Path"
    }

    $item = Get-Item -LiteralPath $Path
    $actualSha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $ExpectedSha256) {
        throw ("Driver safety check failed for {0}. Expected SHA256 {1}, found {2}. " +
               "No device request was sent.") -f $Path, $ExpectedSha256, $actualSha256
    }

    [pscustomobject]@{
        Path = $item.FullName
        Size = $item.Length
        Sha256 = $actualSha256
        FileVersion = $item.VersionInfo.FileVersion
    }
}

function Get-ServiceDriverEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$ServiceName,
        [Parameter(Mandatory = $true)][string]$ExpectedFileName,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    $serviceKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName"
    if (-not (Test-Path -LiteralPath $serviceKeyPath)) {
        throw "Required installed driver service was not found: $ServiceName"
    }

    $service = Get-ItemProperty -LiteralPath $serviceKeyPath
    $registeredImagePath = [string]$service.ImagePath
    if ([string]::IsNullOrWhiteSpace($registeredImagePath)) {
        throw "Required installed driver service has no ImagePath: $ServiceName"
    }

    $imagePath = [Environment]::ExpandEnvironmentVariables($registeredImagePath.Trim())

    # A driver service normally has only a binary path. Still accept a quoted
    # path so this resolver does not accidentally treat trailing arguments as
    # part of a file name.
    if ($imagePath.StartsWith('"')) {
        $closingQuote = $imagePath.IndexOf('"', 1)
        if ($closingQuote -lt 2) {
            throw "Driver service has an invalid quoted ImagePath: $ServiceName"
        }
        $imagePath = $imagePath.Substring(1, $closingQuote - 1)
    }

    # Kernel driver ImagePath values commonly use either of these NT forms.
    if ($imagePath.StartsWith("\??\", [StringComparison]::OrdinalIgnoreCase)) {
        $imagePath = $imagePath.Substring(4)
    }
    if ($imagePath.StartsWith("\SystemRoot\", [StringComparison]::OrdinalIgnoreCase)) {
        $imagePath = Join-Path $env:WINDIR $imagePath.Substring(12)
    }
    elseif ($imagePath.StartsWith("SystemRoot\", [StringComparison]::OrdinalIgnoreCase)) {
        $imagePath = Join-Path $env:WINDIR $imagePath.Substring(11)
    }
    elseif (-not [IO.Path]::IsPathRooted($imagePath)) {
        $imagePath = Join-Path $env:WINDIR ("System32\drivers\" + $imagePath)
    }

    if ([IO.Path]::GetFileName($imagePath) -ine $ExpectedFileName) {
        throw ("Driver service {0} points to unexpected file {1}. " +
               "No device request was sent.") -f $ServiceName, $imagePath
    }

    $evidence = Get-DriverEvidence -Path $imagePath -ExpectedSha256 $ExpectedSha256
    $evidence | Add-Member -NotePropertyName ServiceName -NotePropertyValue $ServiceName
    $evidence | Add-Member -NotePropertyName RegisteredImagePath `
        -NotePropertyValue $registeredImagePath
    return $evidence
}

function New-DppRequest {
    param(
        [Parameter(Mandatory = $true)][string]$QualifiedItemName,
        [Parameter(Mandatory = $true)][ValidateSet("Size", "Read")][string]$Operation
    )

    $request = New-Object byte[] 0x128
    $guidBytes = $DppGuid.ToByteArray()
    [Array]::Copy($guidBytes, 0, $request, 0, $guidBytes.Length)

    $nameBytes = [Text.Encoding]::Unicode.GetBytes($QualifiedItemName + [char]0)
    if ($nameBytes.Length -gt 0xC0) {
        throw "DPP item name is too long for the verified request structure: $QualifiedItemName"
    }
    [Array]::Copy($nameBytes, 0, $request, 0x58, $nameBytes.Length)

    if ($Operation -eq "Size") {
        # QcSOCPartition query selector: return the item's payload byte count.
        $selectorBytes = [BitConverter]::GetBytes([uint32]2)
        [Array]::Copy($selectorBytes, 0, $request, 0x118, 4)
    }

    return $request
}

function Invoke-ReadOnlyIoctl {
    param(
        [Parameter(Mandatory = $true)]$Handle,
        [Parameter(Mandatory = $true)][uint32]$ControlCode,
        [Parameter(Mandatory = $true)][byte[]]$InputBuffer,
        [Parameter(Mandatory = $true)][int]$OutputLength
    )

    if ($AllowedIoctls -notcontains $ControlCode) {
        throw ("Internal safety guard rejected IOCTL 0x{0:X8}." -f $ControlCode)
    }
    if ($OutputLength -lt 0x12C -or $OutputLength -gt ($MaxItemBytes + 0x128)) {
        throw "Internal safety guard rejected output length $OutputLength."
    }

    $output = New-Object byte[] $OutputLength
    [uint32]$bytesReturned = 0
    $ok = [Sp11DppNative]::DeviceIoControl(
        $Handle,
        $ControlCode,
        $InputBuffer,
        [uint32]$InputBuffer.Length,
        $output,
        [uint32]$output.Length,
        [ref]$bytesReturned,
        [IntPtr]::Zero)

    if (-not $ok) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $exception = New-Object ComponentModel.Win32Exception($errorCode)
        throw ("DeviceIoControl 0x{0:X8} failed: Win32 {1} ({2})" -f
               $ControlCode, $errorCode, $exception.Message)
    }

    [pscustomobject]@{
        Buffer = $output
        BytesReturned = $bytesReturned
        DriverStatus = [BitConverter]::ToUInt32($output, 4)
    }
}

function Format-NtStatus {
    param([uint32]$Status)
    return ("0x{0:X8}" -f $Status)
}

function Get-DppItem {
    param(
        [Parameter(Mandatory = $true)]$Handle,
        [Parameter(Mandatory = $true)][string]$QualifiedItemName
    )

    $sizeRequest = New-DppRequest -QualifiedItemName $QualifiedItemName -Operation Size
    $sizeResponse = Invoke-ReadOnlyIoctl -Handle $Handle `
        -ControlCode $IoctlDppItemSize -InputBuffer $sizeRequest -OutputLength 0x12C

    if ($sizeResponse.DriverStatus -ne 0) {
        throw ("DPP size query for {0} returned driver status {1}." -f
               $QualifiedItemName, (Format-NtStatus $sizeResponse.DriverStatus))
    }

    [uint32]$sizePayloadLength = [BitConverter]::ToUInt32($sizeResponse.Buffer, 0x10)
    if ($sizePayloadLength -ne 4) {
        throw "DPP size query returned an unexpected payload length: $sizePayloadLength"
    }

    [uint32]$itemLength = [BitConverter]::ToUInt32($sizeResponse.Buffer, 0x14)
    if ($itemLength -eq 0 -or $itemLength -gt $MaxItemBytes) {
        throw "DPP item length failed the 1..$MaxItemBytes byte safety check: $itemLength"
    }

    $readRequest = New-DppRequest -QualifiedItemName $QualifiedItemName -Operation Read
    $readResponse = Invoke-ReadOnlyIoctl -Handle $Handle `
        -ControlCode $IoctlDppItemRead -InputBuffer $readRequest `
        -OutputLength ([int]$itemLength + 0x128)

    if ($readResponse.DriverStatus -ne 0) {
        throw ("DPP read for {0} returned driver status {1}." -f
               $QualifiedItemName, (Format-NtStatus $readResponse.DriverStatus))
    }

    [uint32]$returnedLength = [BitConverter]::ToUInt32($readResponse.Buffer, 0x10)
    if ($returnedLength -ne $itemLength) {
        throw "DPP read length mismatch: queried $itemLength, returned $returnedLength"
    }
    if (([uint64]$returnedLength + 0x14) -gt [uint64]$readResponse.Buffer.Length) {
        throw "DPP response payload lies outside the verified output buffer."
    }

    $payload = New-Object byte[] $returnedLength
    [Array]::Copy($readResponse.Buffer, 0x14, $payload, 0, $returnedLength)

    [pscustomobject]@{
        QualifiedName = $QualifiedItemName
        Data = $payload
        Length = $returnedLength
        SizeIoctlBytesReturned = $sizeResponse.BytesReturned
        ReadIoctlBytesReturned = $readResponse.BytesReturned
    }
}

function Get-PayloadKind {
    param([Parameter(Mandatory = $true)][byte[]]$Data)

    if ($Data.Length -ge 4 -and
        $Data[0] -eq 0x7F -and $Data[1] -eq 0x45 -and
        $Data[2] -eq 0x4C -and $Data[3] -eq 0x46) {
        return "ELF"
    }
    if ($Data.Length -ge 15) {
        $prefix = [Text.Encoding]::ASCII.GetString($Data, 0, 15)
        if ($prefix -eq "QCA-ATH12K-BOARD") {
            return "ath12k-board-container"
        }
    }
    return "binary"
}

function Save-DppItem {
    param(
        [Parameter(Mandatory = $true)]$Item,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][string]$BaseName
    )

    $path = Join-Path $OutputDirectory ($BaseName + ".bin")
    [IO.File]::WriteAllBytes($path, $Item.Data)
    $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    $kind = Get-PayloadKind -Data $Item.Data

    if ($kind -eq "ELF") {
        $elfPath = Join-Path $OutputDirectory ($BaseName + ".elf")
        Copy-Item -LiteralPath $path -Destination $elfPath
    }

    [pscustomobject]@{
        QualifiedName = $Item.QualifiedName
        Path = $path
        Size = $Item.Length
        Sha256 = $hash
        Kind = $kind
        SizeIoctlBytesReturned = $Item.SizeIoctlBytesReturned
        ReadIoctlBytesReturned = $Item.ReadIoctlBytesReturned
    }
}

Assert-Administrator

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resultDirectory = Join-Path $PSScriptRoot "SP11-DPP-WLAN-BDF-RESULT-$timestamp"
New-Item -ItemType Directory -Path $resultDirectory | Out-Null
$transcriptPath = Join-Path $resultDirectory "extractor-transcript.txt"

try {
    Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null

    Write-Host "SP11 read-only Qualcomm DPP WLAN extractor"
    Write-Host "Output: $resultDirectory"
    Write-Host "Verifying exact installed drivers before opening the device..."

    $qcSocEvidence = Get-ServiceDriverEvidence `
        -ServiceName "QcSOCPartition" `
        -ExpectedFileName "QcSOCPartition.sys" `
        -ExpectedSha256 $ExpectedQcSocSha256
    $wlanEvidence = Get-ServiceDriverEvidence `
        -ServiceName "qcwlan" `
        -ExpectedFileName "qcwlanhmt8380.sys" `
        -ExpectedSha256 $ExpectedWlanSha256
    Write-Host ("  QcSOCPartition: {0} (SHA256 {1})" -f
        $qcSocEvidence.Path, $qcSocEvidence.Sha256)
    Write-Host ("  qcwlan: {0} (SHA256 {1})" -f
        $wlanEvidence.Path, $wlanEvidence.Sha256)

    if (-not ("Sp11DppNative" -as [type])) {
        Add-Type -TypeDefinition $NativeSource -Language CSharp
    }

    # Start with no requested file access. If this Windows build requires an
    # access bit for CreateFile, fall back to GENERIC_READ only. Never request
    # GENERIC_WRITE.
    [uint32]$desiredAccess = 0
    [uint32]$shareReadWrite = 3
    [uint32]$openExisting = 3
    $handle = [Sp11DppNative]::CreateFile(
        $DevicePath, $desiredAccess, $shareReadWrite, [IntPtr]::Zero,
        $openExisting, 0, [IntPtr]::Zero)

    if ($handle.IsInvalid) {
        $handle.Dispose()
        $desiredAccess = [Convert]::ToUInt32("80000000", 16)
        $handle = [Sp11DppNative]::CreateFile(
            $DevicePath, $desiredAccess, $shareReadWrite, [IntPtr]::Zero,
            $openExisting, 0, [IntPtr]::Zero)
    }
    if ($handle.IsInvalid) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $exception = New-Object ComponentModel.Win32Exception($errorCode)
        $handle.Dispose()
        throw ("Could not open {0} without write access: Win32 {1} ({2})" -f
               $DevicePath, $errorCode, $exception.Message)
    }

    try {
        $savedItems = @()

        Write-Host "Reading QCOM\WLAN_CLPC.PROVISION..."
        $boardItem = Get-DppItem -Handle $handle `
            -QualifiedItemName "QCOM\WLAN_CLPC.PROVISION"
        $savedItems += Save-DppItem -Item $boardItem `
            -OutputDirectory $resultDirectory -BaseName "WLAN_CLPC.PROVISION"

        Write-Host "Checking optional QCOM\WLAN_CTL.PROVISION..."
        try {
            $ctlItem = Get-DppItem -Handle $handle `
                -QualifiedItemName "QCOM\WLAN_CTL.PROVISION"
            $savedItems += Save-DppItem -Item $ctlItem `
                -OutputDirectory $resultDirectory -BaseName "WLAN_CTL.PROVISION"
        }
        catch {
            Set-Content -LiteralPath (Join-Path $resultDirectory "WLAN_CTL.PROVISION-not-present.txt") `
                -Value $_.Exception.Message -Encoding UTF8
            Write-Host "Optional CTL object was not extracted: $($_.Exception.Message)"
        }
    }
    finally {
        $handle.Dispose()
    }

    $scriptHash = (Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [pscustomobject]@{
        Created = (Get-Date).ToString("o")
        ComputerName = $env:COMPUTERNAME
        DevicePath = $DevicePath
        OpenedWith = $(if ($desiredAccess -eq 0) { "no requested access" } else { "GENERIC_READ" })
        Operations = @(
            "0xECAF32C6 DPP item size (read-only)",
            "0xECAF32C2 DPP item read (read-only)"
        )
        DppNamespaceGuid = $DppGuid.ToString()
        Script = [pscustomobject]@{
            Path = $PSCommandPath
            Sha256 = $scriptHash
        }
        Drivers = @($qcSocEvidence, $wlanEvidence)
        Items = $savedItems
    }
    $manifest | ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $resultDirectory "manifest.json") -Encoding UTF8

    $summary = @(
        "SP11 Qualcomm DPP WLAN extraction completed successfully."
        "Created: $($manifest.Created)"
        "Device: $DevicePath"
        "Handle access: $($manifest.OpenedWith)"
        "Only read-only IOCTLs 0xECAF32C6 and 0xECAF32C2 were issued."
        ""
    )
    foreach ($saved in $savedItems) {
        $summary += ("{0}`n  file: {1}`n  kind: {2}`n  size: {3}`n  sha256: {4}`n" -f
            $saved.QualifiedName, $saved.Path, $saved.Kind, $saved.Size, $saved.Sha256)
    }
    $summary | Set-Content -LiteralPath (Join-Path $resultDirectory "RESULT-SUMMARY.txt") `
        -Encoding UTF8

    Write-Host ""
    Write-Host "Extraction succeeded."
    foreach ($saved in $savedItems) {
        Write-Host ("  {0}: {1} bytes, SHA256 {2}" -f
            $saved.QualifiedName, $saved.Size, $saved.Sha256)
    }
    Write-Host "Bring this result directory back to Linux:"
    Write-Host "  $resultDirectory"
}
catch {
    $message = $_ | Out-String
    Set-Content -LiteralPath (Join-Path $resultDirectory "ERROR.txt") `
        -Value $message -Encoding UTF8
    Write-Host ""
    Write-Host "Extraction stopped safely: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "No partition write IOCTL exists in this script."
    Write-Host "Error details: $(Join-Path $resultDirectory 'ERROR.txt')"
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch {}
}
