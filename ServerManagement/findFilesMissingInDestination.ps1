#to run this, excecute command
# ./findFilesMissingInDestination.ps1 -SourcePath "/path/to/source" -DestinationPath "/path/to/destination"
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationPath,

    [Parameter(Mandatory=$false)]
    [int]$BatchSize = 10000,

    [Parameter(Mandatory=$false)]
    [int]$MaxJobs = 4
)

# Helper function to get files in batches
function Get-FilesBatch {
    param (
        [string]$Path,
        [int]$Skip,
        [int]$First
    )
    Get-ChildItem -Path $Path -File -Recurse | 
        Select-Object Name, FullName, Length, LastWriteTime |
        Select-Object -Skip $Skip -First $First
}

# Verify paths exist
if (-not (Test-Path $SourcePath)) {
    Write-Error "Source path does not exist: $SourcePath"
    exit 1
}
if (-not (Test-Path $DestinationPath)) {
    Write-Error "Destination path does not exist: $DestinationPath"
    exit 1
}

# Initialize arrays to store results
$sourceFiles = [System.Collections.ArrayList]::new()
$destFiles = [System.Collections.ArrayList]::new()

# Function to process files in parallel
function Process-FilesParallel {
    param(
        [string]$Path,
        [string]$Type,
        [System.Collections.ArrayList]$ResultArray
    )

    $totalFiles = (Get-ChildItem -Path $Path -File -Recurse | Measure-Object).Count
    $batches = [math]::Ceiling($totalFiles / $BatchSize)
    
    Write-Host "Processing $totalFiles files from $Type in $batches batches..." -ForegroundColor Cyan

    for ($i = 0; $i -lt $batches; $i += $MaxJobs) {
        $jobs = @()
        
        # Start parallel jobs
        for ($j = 0; $j -lt $MaxJobs -and ($i + $j) -lt $batches; $j++) {
            $skip = ($i + $j) * $BatchSize
            $jobs += Start-Job -ScriptBlock {
                param($path, $skip, $batchSize)
                Get-FilesBatch -Path $path -Skip $skip -First $batchSize
            } -ArgumentList $Path, $skip, $BatchSize
        }

        # Wait for all jobs and process results
        $jobs | Wait-Job | ForEach-Object {
            $results = Receive-Job -Job $_ -AutoRemoveJob -Wait
            foreach ($result in $results) {
                $relativePath = $result.FullName.Substring($Path.Length)
                $null = $ResultArray.Add([PSCustomObject]@{
                    Name = $result.Name
                    FullName = $result.FullName
                    Length = $result.Length
                    LastWriteTime = $result.LastWriteTime
                    RelativePath = $relativePath
                })
            }
        }

        # Report progress
        $processed = [Math]::Min(($i + $MaxJobs) * $BatchSize, $totalFiles)
        Write-Progress -Activity "Processing $Type files" -Status "$processed of $totalFiles files" -PercentComplete (($processed / $totalFiles) * 100)
        
        # Force garbage collection
        [System.GC]::Collect()
    }
    
    Write-Progress -Activity "Processing $Type files" -Completed
}

# Process source and destination files
Process-FilesParallel -Path $SourcePath -Type "source" -ResultArray $sourceFiles
Process-FilesParallel -Path $DestinationPath -Type "destination" -ResultArray $destFiles

Write-Host "Comparing files..." -ForegroundColor Cyan
# Compare files between directories using hash tables for better performance
$destHash = @{}
$destFiles | ForEach-Object { $destHash[$_.RelativePath] = $_ }

$missingFiles = $sourceFiles | Where-Object { 
    -not $destHash.ContainsKey($_.RelativePath)
}

if ($missingFiles) {
    Write-Host "`nFiles that exist in source but are missing in destination:" -ForegroundColor Yellow
    $missingFiles | ForEach-Object {
        Write-Host "Missing: $($_.RelativePath)"
    }
} else {
    Write-Host "`nAll files from source exist in destination." -ForegroundColor Green
}