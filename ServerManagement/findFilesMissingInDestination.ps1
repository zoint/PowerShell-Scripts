# to run this, execute command
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

# Verify paths exist
if (-not (Test-Path $SourcePath)) {
    Write-Error "Source path does not exist: $SourcePath"
    exit 1
}
if (-not (Test-Path $DestinationPath)) {
    Write-Error "Destination path does not exist: $DestinationPath"
    exit 1
}

Write-Host "`nStarting file comparison process..." -ForegroundColor Green
Write-Host "Source Path: $SourcePath" -ForegroundColor Cyan
Write-Host "Destination Path: $DestinationPath" -ForegroundColor Cyan
Write-Host "Batch Size: $BatchSize files" -ForegroundColor Cyan
Write-Host "Maximum concurrent jobs: $MaxJobs`n" -ForegroundColor Cyan

function Get-DirectoryBatches {
    param (
        [string]$Path
    )
    
    $allFiles = @()
    $di = New-Object System.IO.DirectoryInfo($Path)
    $allFiles = $di.EnumerateFiles("*", [System.IO.SearchOption]::AllDirectories)
    
    # Split files into batches
    $batches = @()
    $currentBatch = @()
    $count = 0
    
    foreach ($file in $allFiles) {
        $currentBatch += $file
        $count++
        
        if ($count % $BatchSize -eq 0) {
            $batches += , $currentBatch
            $currentBatch = @()
        }
    }
    
    if ($currentBatch.Count -gt 0) {
        $batches += , $currentBatch
    }
    
    return $batches
}

function Process-FileBatch {
    param (
        [array]$Batch,
        [string]$BasePath
    )
    
    $results = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($file in $Batch) {
        $relativePath = $file.FullName.Substring($BasePath.Length)
        $null = $results.Add($relativePath)
    }
    return $results
}

function Invoke-ParallelProcessing {
    param (
        [string]$Path,
        [string]$Type
    )
    
    Write-Host "Processing $Type directory..." -ForegroundColor Cyan
    
    # Get batches of files
    $batches = Get-DirectoryBatches -Path $Path
    
    # Create runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxJobs)
    $runspacePool.Open()
    
    $jobs = @()
    
    foreach ($batch in $batches) {
        $powershell = [powershell]::Create().AddScript({
            param($batch, $basePath)
            $results = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($file in $batch) {
                $relativePath = $file.FullName.Substring($basePath.Length)
                $null = $results.Add($relativePath)
            }
            return $results
        }).AddArgument($batch).AddArgument($Path)
        
        $powershell.RunspacePool = $runspacePool
        
        $jobs += @{
            PowerShell = $powershell
            Handle = $powershell.BeginInvoke()
        }
    }
    
    # Create a HashSet to store all results
    $results = [System.Collections.Generic.HashSet[string]]::new()
    
    # Process completed jobs
    foreach ($job in $jobs) {
        $jobResults = $job.PowerShell.EndInvoke($job.Handle)
        foreach ($result in $jobResults) {
            $null = $results.Add($result)
        }
        $job.PowerShell.Dispose()
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    return $results
}

# Process source and destination files in parallel
Write-Host "`nPhase 1: Processing source directory..." -ForegroundColor Green
$sourceFiles = Invoke-ParallelProcessing -Path $SourcePath -Type "source"
Write-Host "Found $($sourceFiles.Count) files in source directory" -ForegroundColor Cyan

Write-Host "`nPhase 2: Processing destination directory..." -ForegroundColor Green
$destFiles = Invoke-ParallelProcessing -Path $DestinationPath -Type "destination"
Write-Host "Found $($destFiles.Count) files in destination directory" -ForegroundColor Cyan

Write-Host "`nPhase 3: Comparing files..." -ForegroundColor Green

# Find missing files (files in source that aren't in destination)
$missingFiles = [System.Collections.Generic.HashSet[string]]::new()
foreach ($file in $sourceFiles) {
    [void]$missingFiles.Add($file)
}
$missingFiles.ExceptWith($destFiles)
$missingCount = $missingFiles.Count

if ($missingCount -gt 0) {
    Write-Host "`nFound $missingCount files that exist in source but are missing in destination:" -ForegroundColor Yellow
    foreach ($file in $missingFiles) {
        Write-Host "Missing: $file" -ForegroundColor Red
    }
} else {
    Write-Host "`nComparison complete! All files from source exist in destination." -ForegroundColor Green
}

Write-Host "`nProcess completed!" -ForegroundColor Green