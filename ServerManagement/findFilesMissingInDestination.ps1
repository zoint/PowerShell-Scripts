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

    Write-Host "Processing $Type directory..." -ForegroundColor Cyan
    
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxJobs)
    $runspacePool.Open()

    # Create a single runspace that will process all files
    $powershell = [powershell]::Create()
    $powershell.RunspacePool = $runspacePool
    
    $null = $powershell.AddScript({
        param($path)
        try {
            $di = New-Object System.IO.DirectoryInfo($path)
            $files = $di.EnumerateFiles("*", [System.IO.SearchOption]::AllDirectories)
            $totalFiles = 0
            
            foreach ($file in $files) {
                try {
                    $totalFiles++
                    if ($totalFiles % 1000 -eq 0) {
                        Write-Progress -Activity "Enumerating files" -Status "$totalFiles files found"
                    }
                    $file.FullName.Substring($path.Length)
                }
                catch {
                    Write-Warning "Unable to process file: $($file.FullName)"
                }
            }
        }
        catch {
            Write-Warning "Error enumerating files: $_"
        }
    }).AddArgument($Path)
    
    # Start the processing and wait for completion
    $handle = $powershell.BeginInvoke()
    
    # Show progress while waiting
    while (-not $handle.IsCompleted) {
        Write-Progress -Activity "Processing $Type directory" -Status "Scanning files..."
        Start-Sleep -Milliseconds 100
    }
    
    # Get the results and add them to the result bag
    $results = $powershell.EndInvoke($handle)
    foreach ($relativePath in $results) {
        $ResultBag.Add($relativePath)
    }
    
    # Cleanup
    $powershell.Dispose()
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    Write-Progress -Activity "Processing $Type directory" -Completed
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