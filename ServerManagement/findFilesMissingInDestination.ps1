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

Write-Host "`nStarting file comparison process..." -ForegroundColor Green
Write-Host "Source Path: $SourcePath" -ForegroundColor Cyan
Write-Host "Destination Path: $DestinationPath" -ForegroundColor Cyan
Write-Host "Batch Size: $BatchSize files" -ForegroundColor Cyan
Write-Host "Maximum concurrent jobs: $MaxJobs`n" -ForegroundColor Cyan

# Initialize arrays to store results
$sourceFiles = [System.Collections.ArrayList]::new()
$destFiles = [System.Collections.ArrayList]::new()


    # Function to process files in parallel using runspaces
function Invoke-FilesParallel {
    param(
        [string]$Path,
        [string]$Type,
        [System.Collections.ArrayList]$ResultArray
    )

    Add-Type -AssemblyName System.Collections
    $totalFiles = (Get-ChildItem -Path $Path -File -Recurse | Measure-Object).Count
    $batches = [math]::Ceiling($totalFiles / $BatchSize)
    Write-Host "Processing $totalFiles files from $Type in $batches batches..." -ForegroundColor Cyan

    $sync = [System.Collections.ArrayList]::Synchronized($ResultArray)
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxJobs)
    $runspacePool.Open()
    $runspaces = [System.Collections.ArrayList]::new()

    for ($i = 0; $i -lt $batches; $i++) {
        $skip = $i * $BatchSize
        $powershell = [powershell]::Create()
        $powershell.RunspacePool = $runspacePool
        $null = $powershell.AddScript({
            param($path, $skip, $batchSize)
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
            Get-FilesBatch -Path $path -Skip $skip -First $batchSize
        }).AddArgument($Path).AddArgument($skip).AddArgument($BatchSize)
        $null = $runspaces.Add([PSCustomObject]@{
            Pipe = $powershell
            Handle = $powershell.BeginInvoke()
            Batch = $i
        })
    }

    $completed = 0
    while ($runspaces.Count -gt 0) {
        for ($r = $runspaces.Count - 1; $r -ge 0; $r--) {
            $runspace = $runspaces[$r]
            if ($runspace.Pipe.EndInvoke($runspace.Handle)) {
                $results = $runspace.Pipe.EndInvoke($runspace.Handle)
                foreach ($result in $results) {
                    $relativePath = $result.FullName.Substring($Path.Length)
                    $null = $sync.Add([PSCustomObject]@{
                        Name = $result.Name
                        FullName = $result.FullName
                        Length = $result.Length
                        LastWriteTime = $result.LastWriteTime
                        RelativePath = $relativePath
                    })
                }
                $runspace.Pipe.Dispose()
                $runspaces.RemoveAt($r)
                $completed++
                $processed = [Math]::Min($completed * $BatchSize, $totalFiles)
                Write-Progress -Activity "Processing $Type files" -Status "$processed of $totalFiles files" -PercentComplete (($processed / $totalFiles) * 100)
            }
        }
        Start-Sleep -Milliseconds 200
    }
    $runspacePool.Close()
    $runspacePool.Dispose()
    Write-Progress -Activity "Processing $Type files" -Completed
}


# Process source and destination files
Write-Host "`nPhase 1: Processing source directory..." -ForegroundColor Green
Invoke-FilesParallel -Path $SourcePath -Type "source" -ResultArray $sourceFiles
Write-Host "Found $($sourceFiles.Count) files in source directory" -ForegroundColor Cyan

Write-Host "`nPhase 2: Processing destination directory..." -ForegroundColor Green
Invoke-FilesParallel -Path $DestinationPath -Type "destination" -ResultArray $destFiles
Write-Host "Found $($destFiles.Count) files in destination directory" -ForegroundColor Cyan

Write-Host "`nPhase 3: Comparing files..." -ForegroundColor Green
# Compare files between directories using hash tables for better performance
$destHash = @{}
$destFiles | ForEach-Object { $destHash[$_.RelativePath] = $_ }

Write-Host "Building comparison hash table..." -ForegroundColor Cyan
$missingFiles = $sourceFiles | Where-Object { 
    -not $destHash.ContainsKey($_.RelativePath)
}

$missingCount = ($missingFiles | Measure-Object).Count

if ($missingFiles) {
    Write-Host "`nFound $missingCount files that exist in source but are missing in destination:" -ForegroundColor Yellow
    $missingFiles | ForEach-Object {
        Write-Host "Missing: $($_.RelativePath)" -ForegroundColor Red
    }
} else {
    Write-Host "`nComparison complete! All files from source exist in destination." -ForegroundColor Green
}

Write-Host "`nProcess completed!" -ForegroundColor Green