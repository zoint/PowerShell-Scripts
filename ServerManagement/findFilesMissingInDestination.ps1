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
$sourceFiles = Get-ChildItem -Path $SourcePath -Recurse -File | 
    Select-Object Name, FullName, Length, LastWriteTime, 
    @{Name="RelativePath";Expression={$_.FullName.Substring($SourcePath.Length)}}

$destFiles = Get-ChildItem -Path $DestinationPath -Recurse -File | 
    Select-Object Name, FullName, Length, LastWriteTime,
    @{Name="RelativePath";Expression={$_.FullName.Substring($DestinationPath.Length)}}

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