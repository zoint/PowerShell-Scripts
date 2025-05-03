#to run this, excecute command
# ./findFilesMissingInDestination.ps1 -SourcePath "/path/to/source" -DestinationPath "/path/to/destination"
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationPath
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

# Get files from both directories recursively
Write-Host "Gathering files from source directory..." -ForegroundColor Cyan
$sourceFiles = @(Get-ChildItem -Path $SourcePath -Recurse -File)
$totalSource = $sourceFiles.Count
Write-Host "Processing $totalSource files from source..." -ForegroundColor Cyan
$sourceFiles = $sourceFiles | ForEach-Object -Begin {
    $current = 0
} -Process {
    $current++
    if ($current % 100 -eq 0) {  # Update progress every 100 files for better performance
        Write-Progress -Activity "Processing source files" -Status "$current of $totalSource files" -PercentComplete (($current / $totalSource) * 100)
    }
    $_ | Select-Object Name, FullName, Length, LastWriteTime, 
    @{Name="RelativePath";Expression={$_.FullName.Substring($SourcePath.Length)}}
}
Write-Progress -Activity "Processing source files" -Completed

Write-Host "Gathering files from destination directory..." -ForegroundColor Cyan
$destFiles = @(Get-ChildItem -Path $DestinationPath -Recurse -File)
$totalDest = $destFiles.Count
Write-Host "Processing $totalDest files from destination..." -ForegroundColor Cyan
$destFiles = $destFiles | ForEach-Object -Begin {
    $current = 0
} -Process {
    $current++
    if ($current % 100 -eq 0) {  # Update progress every 100 files for better performance
        Write-Progress -Activity "Processing destination files" -Status "$current of $totalDest files" -PercentComplete (($current / $totalDest) * 100)
    }
    $_ | Select-Object Name, FullName, Length, LastWriteTime,
    @{Name="RelativePath";Expression={$_.FullName.Substring($DestinationPath.Length)}}
}
Write-Progress -Activity "Processing destination files" -Completed

Write-Host "Comparing $totalSource source files with $totalDest destination files..." -ForegroundColor Cyan
# Compare files between directories
$missingFiles = Compare-Object -ReferenceObject $sourceFiles -DifferenceObject $destFiles -Property RelativePath |
    Where-Object { $_.SideIndicator -eq "<=" }

if ($missingFiles) {
    Write-Host "`nFiles that exist in source but are missing in destination:" -ForegroundColor Yellow
    $missingFiles | ForEach-Object {
        Write-Host "Missing: $($_.RelativePath)"
    }
} else {
    Write-Host "`nAll files from source exist in destination." -ForegroundColor Green
}