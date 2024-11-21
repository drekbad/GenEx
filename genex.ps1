param(
    [ValidateSet("UserDatabase", "Backups", "Random")]
    [string]$Scenario, # Required scenario
    [Int64]$MaxTotalSize, # Required total size in bytes
    [switch]$RandomSize, # Use random file sizes
    [string[]]$Extensions = @("conf", "sql", "bak", "zip"), # Valid extensions
    [string]$Keyword,    # Optional keyword to inject into filenames
    [string]$CreatedDate, # Optional: Created date for files
    [switch]$Help # Display help
)

if ($Help) {
    Write-Host @"
Usage: Generate-BogusData.ps1 [OPTIONS]

Options:
    -Scenario       Required: Specify a scenario ('UserDatabase', 'Backups', or 'Random').
    -MaxTotalSize   Required: Maximum total size for all generated files (in bytes).
    -RandomSize     Generate random file sizes within max total size.
    -Extensions     File extensions to use (default: conf, sql, bak, zip).
    -Keyword        Inject this keyword into some filenames (optional).
    -CreatedDate    Specify a created date (e.g., "06/15/2023").
    -Help           Display this help information.
"@
    exit
}

# Validate required arguments
if (-not $Scenario -or -not $MaxTotalSize) {
    Write-Error "Required options missing: -Scenario and -MaxTotalSize."
    exit
}

# Function to write random data to a file
function Write-RandomFile {
    param(
        [string]$FileName,
        [Int64]$FileSize
    )
    try {
        $bufferSize = 1MB
        $bytesRemaining = $FileSize
        $fileStream = [System.IO.File]::Create($FileName)
        $random = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
        $buffer = New-Object byte[] $bufferSize

        while ($bytesRemaining -gt 0) {
            $bytesToWrite = [Int64]([Math]::Min($bufferSize, $bytesRemaining))
            $random.GetBytes($buffer)
            $fileStream.Write($buffer, 0, [int]$bytesToWrite)
            $bytesRemaining -= $bytesToWrite
        }
        $fileStream.Close()
        Write-Host "Finished writing $FileName"
    } catch {
        Write-Error "Failed to write to ${FileName}: $_"
    }
}

# Parse CreatedDate
if ($CreatedDate) {
    try {
        $ParsedCreatedDate = [datetime]::Parse($CreatedDate, [System.Globalization.CultureInfo]::InvariantCulture)
        # Write-Host "DEBUG: Parsed CreatedDate is $ParsedCreatedDate"
    } catch {
        Write-Error "Invalid -CreatedDate format. Please use a valid date format."
        exit
    }
}

# Directory creation
$BaseDir = "DATA"
$i = 0
while (Test-Path "$BaseDir$i") { $i++ }
$TargetDir = "$BaseDir$i"
New-Item -ItemType Directory -Path $TargetDir | Out-Null

# Scenario-specific names and logic
$NameDictionaries = @{
    "UserDatabase" = @("users.sql", "schema.sql", "config.conf", "backup.bak", "log.sql", "auth.sql")
    "Backups"      = @("full_backup.bak", "incremental_backup.bak", "backup_config.conf", "restore.sql")
    "Random"       = @("random_file.conf", "temp.sql", "archive.zip", "random_data.bak")
}

# Initialize variables
[Int64]$TotalSize = 0
$MinFileSize = 1MB
$MaxFileSize = 2GB  # Increased maximum individual file size to 2 GB
$GeneratedFiles = @()
$UniqueNames = @()     # Array for unique filenames
$FileIndex = 1

# Size limits for .conf files
$ConfMinSize = 1KB
$ConfMaxSize = 1000KB  # 1,000 KB = 1 MB

# Generate files until MaxTotalSize is reached
while ($TotalSize -lt $MaxTotalSize) {
    $FileType = Get-Random -InputObject $Extensions

    # Generate unique filenames
    $BaseFileName = if ($Scenario -ne "Random") {
        Get-Random -InputObject $NameDictionaries[$Scenario]
    } else {
        "random_file_$FileIndex.$FileType"
    }

    # Inject keyword into logical file types
    if ($Keyword) {
        $InjectKeyword = $FileType -in @("sql", "bak")
        if ($InjectKeyword) {
            $BaseFileName = "$Keyword" + "_" + $BaseFileName
        }
    }

    # Ensure uniqueness
    $FileName = "$TargetDir\$BaseFileName"
    $Counter = 1
    while ($UniqueNames -contains $FileName) {
        $FileName = "$TargetDir\$($BaseFileName.Split('.')[0])_$Counter.$FileType"
        $Counter++
    }
    $UniqueNames += $FileName

    # Determine file size
    if ($RandomSize) {
        # Calculate remaining size
        $RemainingSize = $MaxTotalSize - $TotalSize

        if ($FileType -eq "conf") {
            # Set file size for .conf files between 1 KB and 1,000 KB
            if ($ConfMaxSize -gt $RemainingSize) {
                $ConfMaxSize = $RemainingSize
            }
            if ($ConfMinSize -gt $ConfMaxSize) {
                $ConfMinSize = $ConfMaxSize
            }
            if ($ConfMinSize -eq $ConfMaxSize) {
                $FileSize = $ConfMinSize
            } else {
                $FileSize = Get-Random -Minimum $ConfMinSize -Maximum $ConfMaxSize
            }
        } else {
            # AdjustedMaxFileSize = Min($MaxFileSize, $RemainingSize)
            if ($MaxFileSize -le $RemainingSize) {
                $AdjustedMaxFileSize = $MaxFileSize
            } else {
                $AdjustedMaxFileSize = $RemainingSize
            }

            # Set a reasonable minimum file size
            if ($MinFileSize -le $AdjustedMaxFileSize) {
                $AdjustedMinFileSize = $MinFileSize
            } else {
                $AdjustedMinFileSize = $AdjustedMaxFileSize
            }

            # Random file size between AdjustedMinFileSize and AdjustedMaxFileSize
            if ($AdjustedMinFileSize -eq $AdjustedMaxFileSize) {
                [Int64]$FileSize = $AdjustedMinFileSize
            } else {
                [Int64]$FileSize = Get-Random -Minimum $AdjustedMinFileSize -Maximum $AdjustedMaxFileSize
            }
        }
    } else {
        # Fixed size files
        if ($FileType -eq "conf") {
            $FileSize = $ConfMinSize
        } else {
            [Int64]$FileSize = $MinFileSize
        }
    }

    # Adjust FileSize if it would exceed MaxTotalSize
    if ($TotalSize + $FileSize -gt $MaxTotalSize) {
        $FileSize = $MaxTotalSize - $TotalSize
    }

    if ($FileSize -le 0) {
        break
    }

    # Write random data to file
    Write-RandomFile -FileName $FileName -FileSize $FileSize

    # Set created and modified dates
    if ($CreatedDate) {
        $now = Get-Date
        # Write-Host "DEBUG: \$now is of type $($now.GetType().FullName) with value $now"
        # Write-Host "DEBUG: \$ParsedCreatedDate is of type $($ParsedCreatedDate.GetType().FullName) with value $ParsedCreatedDate"

        try {
            $TimeSpan = $now - $ParsedCreatedDate
        } catch {
            Write-Error "Failed to calculate TimeSpan: $_"
            exit
        }

        if ($TimeSpan.TotalSeconds -gt 0) {
            $TotalSeconds = [Int64][Math]::Floor($TimeSpan.TotalSeconds)
            $RandomSeconds = Get-Random -Minimum 0 -Maximum $TotalSeconds
            $ModifiedDate = $ParsedCreatedDate.AddSeconds($RandomSeconds)
        } else {
            $ModifiedDate = $ParsedCreatedDate
        }
        (Get-Item $FileName).CreationTime = $ParsedCreatedDate
        (Get-Item $FileName).LastWriteTime = $ModifiedDate
    }

    $TotalSize += $FileSize
    $GeneratedFiles += @{
        "FileName" = $FileName
        "FileSize" = [math]::Round($FileSize / 1MB, 2)
    }
    $FileIndex++
}

# Output summary
foreach ($File in $GeneratedFiles) {
    Write-Host "Generated: $($File.FileName) (Size: $($File.FileSize) MB)"
}
Write-Host "Completed: $($GeneratedFiles.Count) files in $TargetDir. Total size: $([math]::Round($TotalSize / 1MB, 2)) MB."
