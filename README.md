# PowerShell Scripts Collection

A collection of useful PowerShell scripts for server and system management tasks.

## Scripts

### Server Management

#### [findFilesMissingInDestination.ps1](ServerManagement/findFilesMissingInDestination.ps1)
Compares two directory paths and identifies files that exist in the source directory but are missing in the destination directory. Useful for verifying file synchronization or backup completeness.

**Usage:**
```powershell
./findFilesMissingInDestination.ps1 -SourcePath "<source_directory>" -DestinationPath "<destination_directory>"
```

**Parameters:**
- `-SourcePath`: Path to the source directory
- `-DestinationPath`: Path to the destination directory to compare against

**Output:**
- Lists any files that exist in the source but are missing in the destination
- For each missing file, shows:
  - Relative path
  - File size
  - Last write time
- Displays a success message if all files exist in both locations

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
