# PowerShell Scripts Collection

A collection of useful PowerShell scripts for server and system management tasks.

## Scripts

### Server Management

#### [findFilesMissingInDestination.ps1](ServerManagement/findFilesMissingInDestination.ps1)
Compares two directory paths and identifies files that exist in the source directory but are missing in the destination directory. Uses parallel processing for improved performance when handling large directories. Useful for verifying file synchronization or backup completeness.

**Usage:**
```powershell
./findFilesMissingInDestination.ps1 -SourcePath "<source_directory>" -DestinationPath "<destination_directory>" [-BatchSize <size>] [-MaxJobs <number>]
```

**Parameters:**
- `-SourcePath`: Path to the source directory
- `-DestinationPath`: Path to the destination directory to compare against
- `-BatchSize`: (Optional) Number of files to process in each batch (Default: 10000)
- `-MaxJobs`: (Optional) Maximum number of parallel jobs to run (Default: 4)

**Features:**
- Parallel processing for improved performance
- Progress bars showing completion status
- Memory-efficient batch processing
- Detailed output for missing files

**Output:**
- Lists any files that exist in the source but are missing in the destination
- For each missing file, shows the relative path
- Displays a success message if all files exist in both locations
- Shows progress during processing of both directories

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.