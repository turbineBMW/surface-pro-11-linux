# SPDX-License-Identifier: MIT
# Copyright (c) 2026 turbinebmw

[CmdletBinding()]
param(
    [ValidateSet("Auto", "Arm", "Collect", "Inventory")]
    [string]$Mode = "Auto"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ProbeVersion = "1"
$WorkRoot = Join-Path $env:ProgramData "SP11-WLAN-BDF-PROBE"
$StatePath = Join-Path $WorkRoot "state.json"
$ProcmonDownload = "https://download.sysinternals.com/files/ProcessMonitor.zip"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )
}

function Invoke-ElevatedSelf {
    $quotedScript = '"' + $PSCommandPath.Replace('"', '""') + '"'
    $arguments = (
        "-NoLogo -NoProfile -ExecutionPolicy Bypass -File " +
        "$quotedScript -Mode $Mode"
    )
    $process = Start-Process -FilePath "powershell.exe" `
        -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

function Get-SP11FWRoot {
    $volumes = @(Get-Volume -FileSystemLabel "SP11FW" `
        -ErrorAction SilentlyContinue)
    if ($volumes.Count -ne 1) {
        throw "Expected exactly one mounted SP11FW volume; found $($volumes.Count)."
    }
    $volume = $volumes[0]
    if ($volume.FileSystemType -ne "FAT32" -or
        $null -eq $volume.DriveLetter) {
        throw "SP11FW must be a mounted FAT32 volume with a drive letter."
    }
    $partition = Get-Partition -DriveLetter $volume.DriveLetter
    $disk = Get-Disk -Number $partition.DiskNumber
    if ($disk.BusType -ne "USB") {
        throw "Refusing SP11FW volume on non-USB disk $($disk.Number)."
    }
    return "$($volume.DriveLetter):\"
}

function New-EvidenceDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$Phase
    )
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $path = Join-Path $Root "SP11-WLAN-BDF-$Phase-$stamp"
    New-Item -ItemType Directory -Path $path | Out-Null
    return $path
}

function Write-CommandOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Command
    )
    try {
        (& $Command 2>&1 | Out-String -Width 4096) |
            Set-Content -LiteralPath $Path -Encoding UTF8
    } catch {
        @(
            "Collection failed:",
            $_.Exception.ToString()
        ) | Set-Content -LiteralPath $Path -Encoding UTF8
    }
}

function Get-WlanDevices {
    return @(
        Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DeviceID -match "VEN_17CB&DEV_1107" -or
                $_.Name -match "Qualcomm.*(FastConnect|Wi-Fi|WLAN)"
            }
    )
}

function Write-RegistryEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    Write-CommandOutput `
        -Path (Join-Path $OutputDirectory "registry-bdf-filename-search.txt") `
        -Command {
            & reg.exe query "HKLM\SYSTEM" /f "BDFileName" /s
        }

    $serviceKeys = @(
        Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services" `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.PSChildName -match "^qcwlan" }
    )
    $serviceOutput = Join-Path $OutputDirectory "registry-qcwlan-services.txt"
    if ($serviceKeys.Count -eq 0) {
        "No qcwlan* service registry keys found." |
            Set-Content -LiteralPath $serviceOutput -Encoding UTF8
    } else {
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($key in $serviceKeys) {
            $nativePath = "HKLM\SYSTEM\CurrentControlSet\Services\" +
                $key.PSChildName
            $lines.Add("===== $nativePath =====")
            $lines.Add((& reg.exe query $nativePath /s 2>&1 |
                Out-String -Width 4096))
        }
        $lines | Set-Content -LiteralPath $serviceOutput -Encoding UTF8
    }

    $deviceOutput = Join-Path $OutputDirectory "registry-wlan-devices.txt"
    $deviceLines = New-Object System.Collections.Generic.List[string]
    foreach ($device in Get-WlanDevices) {
        $nativePath = "HKLM\SYSTEM\CurrentControlSet\Enum\" +
            $device.DeviceID
        $deviceLines.Add("===== $nativePath =====")
        $deviceLines.Add((& reg.exe query $nativePath /s 2>&1 |
            Out-String -Width 4096))
    }
    if ($deviceLines.Count -eq 0) {
        $deviceLines.Add("No matching Qualcomm WLAN PnP devices found.")
    }
    $deviceLines |
        Set-Content -LiteralPath $deviceOutput -Encoding UTF8
}

function Write-DriverStoreEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    $driverStore = Join-Path $env:WINDIR `
        "System32\DriverStore\FileRepository"
    $packageDirectories = @(
        Get-ChildItem -LiteralPath $driverStore -Directory `
            -Filter "qcwlanhmt*" -ErrorAction SilentlyContinue
    )
    $interestingNames = @(
        "bdwlan*",
        "wlanfw*.mbn",
        "phy_ucode*.elf",
        "regdb.bin",
        "qcwlanhmt*.inf",
        "qcwlanhmt*.sys",
        "qcwlanhmt*.cat"
    )
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($directory in $packageDirectories) {
        foreach ($file in Get-ChildItem -LiteralPath $directory.FullName `
            -File -Recurse -ErrorAction SilentlyContinue) {
            $interesting = $false
            foreach ($pattern in $interestingNames) {
                if ($file.Name -like $pattern) {
                    $interesting = $true
                    break
                }
            }
            if ($interesting) {
                $files.Add($file)
            }
        }
    }

    $manifest = New-Object System.Collections.Generic.List[string]
    $manifest.Add("path`tbytes`tsha256`tlast_write_utc")
    foreach ($file in ($files | Sort-Object FullName -Unique)) {
        $hash = (Get-FileHash -LiteralPath $file.FullName `
            -Algorithm SHA256).Hash.ToLowerInvariant()
        $manifest.Add(
            "$($file.FullName)`t$($file.Length)`t$hash`t" +
            $file.LastWriteTimeUtc.ToString("o")
        )
    }
    $manifest | Set-Content -LiteralPath `
        (Join-Path $OutputDirectory "driverstore-wlan-files.tsv") `
        -Encoding UTF8

    $copyRoot = Join-Path $OutputDirectory "BDF-COPIES"
    New-Item -ItemType Directory -Path $copyRoot | Out-Null
    foreach ($file in ($files | Where-Object { $_.Name -like "bdwlan*" })) {
        $packageName = $file.Directory.Parent.Name
        if ($file.Directory.Parent.FullName -ne $driverStore) {
            $packageName = $file.Directory.Name
        }
        $packageName = $packageName -replace '[^A-Za-z0-9_.-]', '_'
        $destinationDirectory = Join-Path $copyRoot $packageName
        New-Item -ItemType Directory -Path $destinationDirectory `
            -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName `
            -Destination (Join-Path $destinationDirectory $file.Name) `
            -Force
    }
}

function Write-Inventory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )

    Write-Host "Collecting Windows and Qualcomm WLAN inventory ..."
    @(
        "SP11 WLAN BDF probe inventory",
        "probe_version=$ProbeVersion",
        "timestamp_utc=$([DateTime]::UtcNow.ToString('o'))",
        "computer=$env:COMPUTERNAME",
        "windows=$env:WINDIR",
        "architecture=$env:PROCESSOR_ARCHITECTURE"
    ) | Set-Content -LiteralPath `
        (Join-Path $OutputDirectory "inventory-summary.txt") `
        -Encoding UTF8

    Write-CommandOutput `
        -Path (Join-Path $OutputDirectory "systeminfo.txt") `
        -Command { & systeminfo.exe }

    $devices = @(Get-WlanDevices)
    $devices | Select-Object Status, Name, Manufacturer, DeviceID, `
        PNPClass, Service, ConfigManagerErrorCode |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath `
            (Join-Path $OutputDirectory "wlan-pnp-devices.json") `
            -Encoding UTF8

    $signedDrivers = @(
        Get-CimInstance Win32_PnPSignedDriver `
            -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DeviceID -match "VEN_17CB&DEV_1107" -or
                $_.DeviceName -match "Qualcomm.*(FastConnect|Wi-Fi|WLAN)"
            }
    )
    $signedDrivers | Select-Object DeviceName, DeviceID, DriverVersion, `
        DriverDate, InfName, DriverProviderName, Manufacturer, `
        IsSigned, Signer |
        ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath `
            (Join-Path $OutputDirectory "wlan-signed-drivers.json") `
            -Encoding UTF8

    Write-CommandOutput `
        -Path (Join-Path $OutputDirectory "pnputil-network-drivers.txt") `
        -Command { & pnputil.exe /enum-drivers /class Net /files }

    Write-RegistryEvidence -OutputDirectory $OutputDirectory
    Write-DriverStoreEvidence -OutputDirectory $OutputDirectory

    Write-CommandOutput `
        -Path (Join-Path $OutputDirectory "recent-wlan-system-events.txt") `
        -Command {
            Get-WinEvent -FilterHashtable @{
                LogName = "System"
                StartTime = (Get-Date).AddDays(-7)
            } -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.ProviderName -match "WLAN|NDIS|Kernel-PnP" -or
                    $_.Message -match "Qualcomm|FastConnect|VEN_17CB|qcwlan"
                } |
                Select-Object TimeCreated, Id, LevelDisplayName, `
                    ProviderName, Message |
                Format-List
        }
}

function Test-MicrosoftProcmon {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($null -eq $signature.SignerCertificate -or
        $signature.SignerCertificate.Subject -notmatch "Microsoft") {
        throw "Procmon is not signed by Microsoft: $Path"
    }
    return $signature
}

function Get-Procmon {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SP11FWRoot
    )

    New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
    $binaryName = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        "Procmon64a.exe"
    } elseif ([Environment]::Is64BitOperatingSystem) {
        "Procmon64.exe"
    } else {
        "Procmon.exe"
    }
    $installedPath = Join-Path $WorkRoot $binaryName
    if (Test-Path -LiteralPath $installedPath -PathType Leaf) {
        [void](Test-MicrosoftProcmon -Path $installedPath)
        return $installedPath
    }

    $portableBinary = Join-Path $SP11FWRoot $binaryName
    if (Test-Path -LiteralPath $portableBinary -PathType Leaf) {
        [void](Test-MicrosoftProcmon -Path $portableBinary)
        Copy-Item -LiteralPath $portableBinary `
            -Destination $installedPath
        return $installedPath
    }

    $zipPath = Join-Path $WorkRoot "ProcessMonitor.zip"
    $portableZip = Join-Path $SP11FWRoot "ProcessMonitor.zip"
    if (Test-Path -LiteralPath $portableZip -PathType Leaf) {
        Copy-Item -LiteralPath $portableZip -Destination $zipPath
    } else {
        Write-Host "Downloading Process Monitor from Microsoft Sysinternals ..."
        [Net.ServicePointManager]::SecurityProtocol = `
            [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $ProcmonDownload -OutFile $zipPath `
            -UseBasicParsing
    }

    $extractRoot = Join-Path $WorkRoot "procmon-unpack"
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractRoot
    $extractedPath = Join-Path $extractRoot $binaryName
    [void](Test-MicrosoftProcmon -Path $extractedPath)
    Copy-Item -LiteralPath $extractedPath -Destination $installedPath
    return $installedPath
}

function Invoke-Procmon {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProcmonPath,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )
    $quoted = @(
        foreach ($argument in $Arguments) {
            if ($argument -match '[\s"]') {
                '"' + $argument.Replace('"', '""') + '"'
            } else {
                $argument
            }
        }
    )
    $process = Start-Process -FilePath $ProcmonPath `
        -ArgumentList $quoted -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Procmon exited with code $($process.ExitCode)."
    }
}

function Invoke-Arm {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SP11FWRoot
    )

    if (Test-Path -LiteralPath $StatePath) {
        throw (
            "A probe is already armed. Reboot Windows, then run " +
            "RUN-WLAN-BDF-PROBE.cmd again."
        )
    }

    $evidence = New-EvidenceDirectory -Root $SP11FWRoot -Phase "ARM"
    Write-Inventory -OutputDirectory $evidence
    $procmon = Get-Procmon -SP11FWRoot $SP11FWRoot
    $signature = Test-MicrosoftProcmon -Path $procmon
    @(
        "path=$procmon",
        "sha256=$((Get-FileHash -LiteralPath $procmon -Algorithm SHA256).Hash.ToLowerInvariant())",
        "signature_status=$($signature.Status)",
        "signer=$($signature.SignerCertificate.Subject)",
        "source=$ProcmonDownload"
    ) | Set-Content -LiteralPath `
        (Join-Path $evidence "procmon-provenance.txt") `
        -Encoding UTF8

    Write-Host "Enabling Process Monitor boot logging ..."
    Invoke-Procmon -ProcmonPath $procmon -Arguments @(
        "/AcceptEula",
        "/Quiet",
        "/EnableBootLogging"
    )

    New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
    $state = @{
        ProbeVersion = $ProbeVersion
        ArmedAtUtc = [DateTime]::UtcNow.ToString("o")
        BootAtArmUtc = (
            Get-CimInstance Win32_OperatingSystem
        ).LastBootUpTime.ToUniversalTime().ToString("o")
        ArmEvidence = $evidence
        ProcmonPath = $procmon
    }
    $state | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $StatePath -Encoding UTF8

    @(
        "SP11 WLAN BDF BOOT TRACE ARMED",
        "",
        "1. Leave the SP11FW USB connected.",
        "2. Reboot Windows normally.",
        "3. Sign in and wait for Wi-Fi to reconnect.",
        "4. Double-click RUN-WLAN-BDF-PROBE.cmd again.",
        "",
        "Do not boot Linux between steps 2 and 4."
    ) | Set-Content -LiteralPath `
        (Join-Path $SP11FWRoot "WLAN-BDF-PROBE-ARMED.txt") `
        -Encoding ASCII

    Write-Host ""
    Write-Host "Boot trace armed successfully."
    Write-Host "Reboot Windows normally, sign in, and run this launcher again."
}

function Export-RelevantProcmonRows {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceCsv,
        [Parameter(Mandatory = $true)]
        [string]$DestinationCsv
    )
    $patterns = @(
        "bdwlan",
        "wlanfw",
        "phy_ucode",
        "regdb.bin",
        "qcwlanhmt"
    )
    $reader = [IO.File]::OpenText($SourceCsv)
    $utf8WithBom = New-Object Text.UTF8Encoding($true)
    $writer = [IO.StreamWriter]::new(
        $DestinationCsv,
        $false,
        $utf8WithBom
    )
    try {
        $header = $reader.ReadLine()
        if ($null -ne $header) {
            $writer.WriteLine($header)
        }
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            foreach ($pattern in $patterns) {
                if ($line.IndexOf(
                    $pattern,
                    [StringComparison]::OrdinalIgnoreCase
                ) -ge 0) {
                    $writer.WriteLine($line)
                    break
                }
            }
        }
    } finally {
        $reader.Dispose()
        $writer.Dispose()
    }
}

function Invoke-Collect {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SP11FWRoot
    )

    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
        throw "No armed WLAN BDF probe was found."
    }
    $state = Get-Content -LiteralPath $StatePath -Raw |
        ConvertFrom-Json
    $armedAt = [DateTimeOffset]::Parse($state.ArmedAtUtc)
    $currentBoot = (
        Get-CimInstance Win32_OperatingSystem
    ).LastBootUpTime.ToUniversalTime()
    if ($currentBoot -le $armedAt.UtcDateTime) {
        throw (
            "Windows has not rebooted since the probe was armed. " +
            "Reboot normally, sign in, and run this launcher again."
        )
    }

    $procmon = [string]$state.ProcmonPath
    [void](Test-MicrosoftProcmon -Path $procmon)
    $evidence = New-EvidenceDirectory -Root $SP11FWRoot -Phase "RESULT"
    Write-Inventory -OutputDirectory $evidence

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $pml = Join-Path $WorkRoot "SP11-WLAN-BOOT-$stamp.pml"
    $csv = Join-Path $WorkRoot "SP11-WLAN-BOOT-$stamp.csv"
    Write-Host "Converting the Process Monitor boot trace ..."
    Invoke-Procmon -ProcmonPath $procmon -Arguments @(
        "/AcceptEula",
        "/Quiet",
        "/ConvertBootLog",
        $pml
    )
    if (-not (Test-Path -LiteralPath $pml -PathType Leaf)) {
        throw "Procmon did not create the expected boot log: $pml"
    }

    Write-Host "Exporting the trace for filtering ..."
    Invoke-Procmon -ProcmonPath $procmon -Arguments @(
        "/AcceptEula",
        "/Quiet",
        "/OpenLog",
        $pml,
        "/SaveAs",
        $csv
    )
    if (-not (Test-Path -LiteralPath $csv -PathType Leaf)) {
        throw "Procmon did not create the expected CSV export: $csv"
    }

    $filteredCsv = Join-Path $evidence "procmon-wlan-firmware-access.csv"
    Export-RelevantProcmonRows -SourceCsv $csv `
        -DestinationCsv $filteredCsv
    Remove-Item -LiteralPath $csv -Force

    $rows = @(Import-Csv -LiteralPath $filteredCsv)
    $paths = @(
        $rows |
            Where-Object {
                $_.Path -match "bdwlan|wlanfw|phy_ucode|regdb\.bin"
            } |
            Select-Object -ExpandProperty Path -Unique |
            Sort-Object
    )
    $pmlHash = (Get-FileHash -LiteralPath $pml `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    $pmlSize = (Get-Item -LiteralPath $pml).Length
    $summary = New-Object System.Collections.Generic.List[string]
    $summary.Add("SP11 WLAN BDF probe result")
    $summary.Add("")
    $summary.Add("probe_version=$ProbeVersion")
    $summary.Add("armed_utc=$($state.ArmedAtUtc)")
    $summary.Add("collected_utc=$([DateTime]::UtcNow.ToString('o'))")
    $summary.Add("matching_procmon_rows=$($rows.Count)")
    $summary.Add("full_pml_path=$pml")
    $summary.Add("full_pml_bytes=$pmlSize")
    $summary.Add("full_pml_sha256=$pmlHash")
    $summary.Add("")
    $summary.Add("Unique firmware paths observed:")
    if ($paths.Count -eq 0) {
        $summary.Add(
            "NONE -- inspect procmon-wlan-firmware-access.csv and the " +
            "inventory files."
        )
    } else {
        foreach ($path in $paths) {
            $summary.Add($path)
        }
    }
    $summary.Add("")
    $summary.Add(
        "The full PML remains on the Windows C: drive because it may be " +
        "too large for SP11FW."
    )
    $summary | Set-Content -LiteralPath `
        (Join-Path $evidence "RESULT-SUMMARY.txt") `
        -Encoding UTF8

    if (Test-Path -LiteralPath `
        (Join-Path $SP11FWRoot "WLAN-BDF-PROBE-ARMED.txt")) {
        Remove-Item -LiteralPath `
            (Join-Path $SP11FWRoot "WLAN-BDF-PROBE-ARMED.txt") `
            -Force
    }
    Remove-Item -LiteralPath $StatePath -Force

    @(
        "SP11 WLAN BDF PROBE COMPLETE",
        "",
        "Results:",
        $evidence,
        "",
        "Safely eject SP11FW before returning to Linux."
    ) | Set-Content -LiteralPath `
        (Join-Path $SP11FWRoot "WLAN-BDF-PROBE-COMPLETE.txt") `
        -Encoding ASCII

    Write-Host ""
    Write-Host "Collection completed successfully:"
    Write-Host "  $evidence"
    if ($paths.Count -gt 0) {
        Write-Host ""
        Write-Host "Firmware paths observed:"
        foreach ($path in $paths) {
            Write-Host "  $path"
        }
    } else {
        Write-Warning "No direct firmware path was found in the filtered trace."
    }
    Write-Host ""
    Write-Host "Safely eject SP11FW before returning to Linux."
}

if (-not (Test-IsAdministrator)) {
    Invoke-ElevatedSelf
}

$sp11fwRoot = Get-SP11FWRoot
New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null

switch ($Mode) {
    "Auto" {
        if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
            Invoke-Collect -SP11FWRoot $sp11fwRoot
        } else {
            Invoke-Arm -SP11FWRoot $sp11fwRoot
        }
    }
    "Arm" {
        Invoke-Arm -SP11FWRoot $sp11fwRoot
    }
    "Collect" {
        Invoke-Collect -SP11FWRoot $sp11fwRoot
    }
    "Inventory" {
        $evidence = New-EvidenceDirectory -Root $sp11fwRoot `
            -Phase "INVENTORY"
        Write-Inventory -OutputDirectory $evidence
        Write-Host "Inventory completed: $evidence"
    }
}
