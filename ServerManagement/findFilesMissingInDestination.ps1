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



# Helper function to get files in batches using .NET methods
function Get-FilesBatch {
    param (
        [string]$Path,
        [int]$Skip,
        [int]$First
    )
    $files = [System.IO.Directory]::GetFiles($Path, "*", [System.IO.SearchOption]::AllDirectories)
    $files | Select-Object -Skip $Skip -First $First | ForEach-Object {
        $fullPath = $_
        [PSCustomObject]@{
            FullName = $fullPath
            RelativePath = $fullPath.Substring($Path.Length)
        }
    }
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
$sourceFiles = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$destFiles = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

# Function to process files in parallel using runspaces
function Invoke-FilesParallel {
    param(
        [string]$Path,
        [string]$Type,
        [System.Collections.Concurrent.ConcurrentBag[string]]$ResultBag
    )

    # Get all files at once using .NET method - much faster than Get-ChildItem
    Write-Host "Getting files from $Type..." -ForegroundColor Cyan
    $files = [System.IO.Directory]::GetFiles($Path, "*", [System.IO.SearchOption]::AllDirectories)
    $totalFiles = $files.Count
    Write-Host "Found $totalFiles files in $Type" -ForegroundColor Cyan

    $batches = [math]::Ceiling($totalFiles / $BatchSize)
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxJobs)
    $runspacePool.Open()
    $runspaces = [System.Collections.ArrayList]::new()

    for ($i = 0; $i -lt $batches; $i++) {
        $skip = $i * $BatchSize
        $batchFiles = $files | Select-Object -Skip $skip -First $BatchSize
        
        $powershell = [powershell]::Create()
        $powershell.RunspacePool = $runspacePool
        
        $null = $powershell.AddScript({
            param($path, $batchFiles)
            foreach ($file in $batchFiles) {
                $file.Substring($path.Length)
            }
        }).AddArgument($Path).AddArgument($batchFiles)
        
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
            if ($runspace.Handle.IsCompleted) {
                $results = $runspace.Pipe.EndInvoke($runspace.Handle)
                foreach ($relativePath in $results) {
                    $ResultBag.Add($relativePath)
                }
                $runspace.Pipe.Dispose()
                $runspaces.RemoveAt($r)
                $completed++
                $processed = [Math]::Min($completed * $BatchSize, $totalFiles)
                Write-Progress -Activity "Processing $Type files" -Status "$processed of $totalFiles files" -PercentComplete (($processed / $totalFiles) * 100)
            }
        }
        if ($runspaces.Count -gt 0) {
            Start-Sleep -Milliseconds 100
        }
    }
    $runspacePool.Close()
    $runspacePool.Dispose()
    Write-Progress -Activity "Processing $Type files" -Completed
}

# Process source and destination files
Write-Host "`nPhase 1: Processing source directory..." -ForegroundColor Green
Invoke-FilesParallel -Path $SourcePath -Type "source" -ResultBag $sourceFiles
Write-Host "Found $($sourceFiles.Count) files in source directory" -ForegroundColor Cyan

Write-Host "`nPhase 2: Processing destination directory..." -ForegroundColor Green
Invoke-FilesParallel -Path $DestinationPath -Type "destination" -ResultBag $destFiles
Write-Host "Found $($destFiles.Count) files in destination directory" -ForegroundColor Cyan

Write-Host "`nPhase 3: Comparing files..." -ForegroundColor Green
# Convert destination files to HashSet for faster lookup
$destHashSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$destFiles)

Write-Host "Finding missing files..." -ForegroundColor Cyan
$missingFiles = $sourceFiles | Where-Object { -not $destHashSet.Contains($_) }
$missingCount = ($missingFiles | Measure-Object).Count

if ($missingCount -gt 0) {
    Write-Host "`nFound $missingCount files that exist in source but are missing in destination:" -ForegroundColor Yellow
    $missingFiles | ForEach-Object {
        Write-Host "Missing: $_" -ForegroundColor Red
    }
} else {
    Write-Host "`nComparison complete! All files from source exist in destination." -ForegroundColor Green
}

Write-Host "`nProcess completed!" -ForegroundColor Green