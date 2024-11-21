param(
    [ValidateSet("UserDatabase", "Backups", "Random")]
    [string]$Scenario, # Required scenario
    [int]$MaxTotalSize, # Required total size in bytes
    [switch]$RandomSize, # Use random file sizes
    [int]$FileCount,     # Number of files (optional)
    [string[]]$Extensions = @("conf", "sql", "bak", "zip"), # Valid extensions
    [string]$Keyword,    # Optional keyword to inject into filenames
    [string]$CreatedDate, # Optional: Created date for files in mm/dd/yyyy format
    [switch]$Help # Display help
)

if ($Help) {
    Write-Host @"
Usage: Generate-BogusData.ps1 [OPTIONS]

Options:
    -Scenario       Required: Specify a scenario ('UserDatabase', 'Backups', or 'Random').
    -MaxTotalSize   Required: Maximum total size for all generated files (in bytes).
    -RandomSize     Generate random file sizes within max total size.
    -FileCount      Number of files to generate (optional; default: random between 4 and 10).
    -Extensions     File extensions to use (default: conf, sql, bak, zip).
    -Keyword        Inject this keyword into some filenames (optional).
    -CreatedDate    Specify a created date (e.g., "06/15/2023"). Modified dates will be random between created and current date.
    -Help           Display this help information.
"@
    exit
}

# Validate required arguments
if (-not $Scenario -or -not $MaxTotalSize -or (-not $RandomSize)) {
    Write-Error "Required options missing: -Scenario, -MaxTotalSize, and -RandomSize."
    exit
}

# Parse CreatedDate
if ($CreatedDate) {
    try {
        # Handle 2-digit year logic
        $CreatedDate = if ($CreatedDate -match "/\d{2}$") {
            $Year = [int]($CreatedDate.Split('/')[-1])
            $Year = if ($Year -le [int](Get-Date -Year (Get-Date).Year).ToString("yy")) {
                2000 + $Year
            } else {
                1900 + $Year
            }
            [datetime]::ParseExact("$($CreatedDate.Substring(0, $CreatedDate.Length - 2))/$Year", "MM/dd/yyyy", $null)
        } else {
            [datetime]::ParseExact($CreatedDate, "MM/dd/yyyy", $null)
        }
    } catch {
        Write-Error "Invalid -CreatedDate format. Please use mm/dd/yyyy or mm/dd/yy."
        exit
    }
}

# Determine file count
if (-not $FileCount) {
    $FileCount = Get-Random -Minimum 4 -Maximum 10
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
    "Backups" = @("full_backup.bak", "incremental_backup.bak", "backup_config.conf", "restore.sql")
    "Random" = @("random_file.conf", "temp.sql", "archive.zip", "random_data.bak")
}

# Initialize variables
$TotalSize = 0
$RemainingSize = [math]::Floor($MaxTotalSize * 0.95) # 95% of MaxTotalSize
$MinConfSize = 1024    # 1 KB
$MaxConfSize = 25600   # 25 KB
$GeneratedFiles = @()
$UniqueNames = @() # Array for unique filenames

# Generate files
for ($j = 1; $j -le $FileCount; $j++) {
    $FileType = Get-Random -InputObject $Extensions

    # Generate unique filenames
    $BaseFileName = if ($Scenario -ne "Random") {
        Get-Random -InputObject $NameDictionaries[$Scenario]
    } else {
        "random_file_$j.$FileType"
    }

    # Inject keyword into logical file types (sql, bak) with higher priority
    if ($Keyword) {
        $InjectKeyword = $FileType -in @("sql", "bak") -or (Get-Random -Minimum 0 -Maximum 2) -eq 1
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
    if ($FileType -eq "conf") {
        $FileSize = Get-Random -Minimum $MinConfSize -Maximum $MaxConfSize
    } else {
        $FileSize = Get-Random -Minimum ([math]::Floor($RemainingSize * 0.1)) -Maximum ([math]::Floor($RemainingSize * 0.4))
    }

    # Ensure total size does not exceed max
    if ($TotalSize + $FileSize -gt $MaxTotalSize) {
        $FileSize = $MaxTotalSize - $TotalSize
    }

    # Write random data to file
    try {
        $RandomData = [byte[]](Get-Random -Minimum 0 -Maximum 255) * $FileSize
        [System.IO.File]::WriteAllBytes($FileName, $RandomData)

        # Set created and modified dates
        if ($CreatedDate) {
            $ModifiedDate = Get-Random -Minimum $CreatedDate.Ticks -Maximum ([datetime]::Now.Ticks)
            $ModifiedDate = [datetime]::FromFileTimeUtc($ModifiedDate)
            (Get-Item $FileName).CreationTime = $CreatedDate
            (Get-Item $FileName).LastWriteTime = $ModifiedDate
        }
    } catch {
        Write-Error "Failed to write to $FileName. $_"
        continue
    }

    $TotalSize += $FileSize
    $RemainingSize -= $FileSize
    $GeneratedFiles += @{"FileName"=$FileName;"FileSize"=[math]::Round($FileSize/1MB,2)}
}

# Output summary
foreach ($File in $GeneratedFiles) {
    Write-Host "Generated: $($File.FileName) (Size: $($File.FileSize) MB)"
}
Write-Host "Completed: $($GeneratedFiles.Count) files in $TargetDir. Total size: $([math]::Round($TotalSize / 1MB, 2)) MB."
