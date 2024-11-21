param(
    [ValidateSet("UserDatabase", "Backups", "Random")]
    [string]$Scenario, # Required scenario
    [int]$MaxTotalSize, # Required total size in bytes
    [switch]$RandomSize, # Use random file sizes
    [switch]$ExactSize,  # Generate files of exact size
    [int]$ExactFileSize, # Size of each file if ExactSize is specified
    [int]$FileCount = 5, # Number of files (default: 5)
    [string[]]$Extensions = @("conf", "sql", "bak", "zip"), # Valid extensions
    [switch]$Help # Display help
)

if ($Help) {
    Write-Host @"
Usage: Generate-BogusData.ps1 [OPTIONS]

Options:
    -Scenario       Required: Specify a scenario ('UserDatabase', 'Backups', or 'Random').
    -MaxTotalSize   Required: Maximum total size for all generated files (in bytes).
    -RandomSize     Generate random file sizes within max total size.
    -ExactSize      Generate files of exact sizes specified by -ExactFileSize.
    -ExactFileSize  File size in bytes if ExactSize is specified.
    -FileCount      Number of files to generate (default: 5).
    -Extensions     File extensions to use (default: conf, sql, bak, zip).
    -Help           Display this help information.
"@
    exit
}

# Validate required arguments
if (-not $Scenario -or -not $MaxTotalSize -or (-not $RandomSize -and -not $ExactSize)) {
    Write-Error "Required options missing: -Scenario, -MaxTotalSize, and one of -RandomSize or -ExactSize."
    exit
}

if ($ExactSize -and (-not $ExactFileSize)) {
    Write-Error "-ExactFileSize must be provided when -ExactSize is specified."
    exit
}

# Check available disk space
$DriveInfo = Get-PSDrive -Name (Get-Location).Drive.Name
$FreeSpace = $DriveInfo.Free
if ($MaxTotalSize -gt $FreeSpace) {
    Write-Error "Not enough free disk space to generate the specified data."
    exit
}
if ($FreeSpace -lt ($FreeSpace - $MaxTotalSize) * 0.05) {
    Write-Warning "Warning: Disk space usage will exceed 95% of capacity."
}

# Directory creation
$BaseDir = "DATA"
$i = 0
while (Test-Path "$BaseDir$i") { $i++ }
$TargetDir = "$BaseDir$i"
New-Item -ItemType Directory -Path $TargetDir | Out-Null

# File templates and names
$FileTemplates = @{
    "conf" = "# Configuration File"
    "sql"  = "-- SQL Dump File"
    "bak"  = "BAK"
    "zip"  = [byte[]](0x50, 0x4B, 0x03, 0x04)
}

$NameDictionaries = @{
    "UserDatabase" = @("users.sql", "schema.sql", "config.conf", "backup2024.bak")
    "Backups" = @("backup2024.zip", "system.bak", "archive.zip")
    "Random" = @("random.conf", "temp.sql", "data.zip")
}

# File size allocation
$TotalSize = 0
$RemainingSize = $MaxTotalSize
$MinConfSize = 200
$MaxConfSize = 20480
$GeneratedFiles = @()

for ($j = 1; $j -le $FileCount; $j++) {
    $FileType = Get-Random -InputObject $Extensions
    $FileName = if ($Scenario -ne "Random") {
        Get-Random -InputObject $NameDictionaries[$Scenario]
    } else {
        "random_$j.$FileType"
    }
    $FileName = "$TargetDir\$FileName"

    # Determine file size
    if ($FileType -eq "conf") {
        $FileSize = Get-Random -Minimum $MinConfSize -Maximum $MaxConfSize
    } elseif ($ExactSize) {
        $FileSize = $ExactFileSize
    } else {
        $FileSize = [math]::Min(
            (Get-Random -Minimum ([math]::Floor($RemainingSize * 0.2)) -Maximum ([math]::Floor($RemainingSize * 0.5))),
            $RemainingSize
        )
    }

    if ($TotalSize + $FileSize -gt $MaxTotalSize) { break }

    # Write file
    if ($FileTemplates[$FileType] -is [byte[]]) {
        [System.IO.File]::WriteAllBytes($FileName, $FileTemplates[$FileType])
    } else {
        Set-Content -Path $FileName -Value $FileTemplates[$FileType]
    }

    $RandomData = [byte[]](Get-Random -Minimum 0 -Maximum 255) * ($FileSize - 10) # Account for header
    [System.IO.File]::WriteAllBytes($FileName, $RandomData)

    $TotalSize += $FileSize
    $RemainingSize -= $FileSize
    $GeneratedFiles += @{"FileName"=$FileName;"FileSize"=[math]::Round($FileSize/1MB,2)}
}

# Output summary
foreach ($File in $GeneratedFiles) {
    Write-Host "Generated: $($File.FileName) (Size: $($File.FileSize) MB)"
}
Write-Host "Completed: $($GeneratedFiles.Count) files in $TargetDir. Total size: $([math]::Round($TotalSize / 1MB, 2)) MB."
