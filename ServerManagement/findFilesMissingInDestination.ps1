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

function Invoke-FilesParallel {
    param(
        [string]$Path,
        [string]$Type,
        [System.Collections.Concurrent.ConcurrentBag[string]]$ResultBag
    )

    Write-Host "Processing $Type directory..." -ForegroundColor Cyan
    
    # Create runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxJobs)
    $runspacePool.Open()

    # Create runspace for file processing
    $powershell = [powershell]::Create()
    $powershell.RunspacePool = $runspacePool
    
    # Add script to process files
    $null = $powershell.AddScript({
        param($path)
        
        $results = @()
        try {
            $di = New-Object System.IO.DirectoryInfo($path)
            $files = $di.EnumerateFiles("*", [System.IO.SearchOption]::AllDirectories)
            $processedFiles = 0
            
            foreach ($file in $files) {
                try {
                    $processedFiles++
                    # Update progress every 100 files to reduce overhead
                    if ($processedFiles % 100 -eq 0) {
                        Write-Progress -Activity "Scanning files" -Status "Processed $processedFiles files" 
                    }
                    $results += $file.FullName.Substring($path.Length)
                }
                catch {
                    Write-Warning "Unable to process file: $($file.FullName)"
                }
            }
            
            Write-Progress -Activity "Scanning files" -Completed
            return $results
        }
        catch {
            Write-Warning "Error enumerating files: $_"
            return $results
        }
    }).AddArgument($Path)
    
    # Start processing
    $handle = $powershell.BeginInvoke()
    
    # Show progress while waiting
    $spinnerChars = '|','/','-','\'
    $spinnerIndex = 0
    while (-not $handle.IsCompleted) {
        $spinnerChar = $spinnerChars[$spinnerIndex % $spinnerChars.Length]
        Write-Progress -Activity "Processing $Type directory" -Status "Scanning files... $spinnerChar"
        $spinnerIndex++
        Start-Sleep -Milliseconds 100
    }
    
    # Get results
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
$processedFiles = 0
$totalSourceFiles = $sourceFiles.Count
$missingFiles = @()

foreach ($file in $sourceFiles) {
    $processedFiles++
    $percentComplete = [math]::Min(100, [math]::Round(($processedFiles / $totalSourceFiles) * 100))
    Write-Progress -Activity "Comparing files" -Status "$processedFiles of $totalSourceFiles files checked" -PercentComplete $percentComplete
    
    if (-not $destHashSet.Contains($file)) {
        $missingFiles += $file
    }
}
Write-Progress -Activity "Comparing files" -Completed
$missingCount = $missingFiles.Count

if ($missingCount -gt 0) {
    Write-Host "`nFound $missingCount files that exist in source but are missing in destination:" -ForegroundColor Yellow
    $missingFiles | ForEach-Object {
        Write-Host "Missing: $_" -ForegroundColor Red
    }
} else {
    Write-Host "`nComparison complete! All files from source exist in destination." -ForegroundColor Green
}

Write-Host "`nProcess completed!" -ForegroundColor Green