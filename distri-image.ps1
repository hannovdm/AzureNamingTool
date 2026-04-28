<#
.SYNOPSIS
    Deterministically maps an image name to one of 10 Azure Compute Gallery names.

.DESCRIPTION
    Azure Compute Gallery (Shared Image Gallery) naming rules:
      - 1-80 characters
      - Alphanumeric, periods and underscores only
      - Must start and end with an alphanumeric
    Naming convention used here (aligned with the Azure CAF abbreviation "gal"):
        gal_<workload>_<env>_<region>_<NN>
    e.g. gal_images_prod_eastus_01 ... gal_images_prod_eastus_10

    The mapping is stable: the same input image name always resolves to the same
    gallery, and inputs are evenly distributed across the 10 galleries by
    taking SHA256(imageName) modulo 10.
#>

function Get-ImageGalleryName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ImageName,

        [Parameter()]
        [string]$Workload = 'images',

        [Parameter()]
        [string]$Environment = 'prod',

        [Parameter()]
        [string]$Region = 'eastus',

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$GalleryCount = 10
    )

    process {
        # Normalize so "MyImage" and "myimage" land on the same gallery.
        $normalized = $ImageName.Trim().ToLowerInvariant()

        # SHA256 gives a stable, well-distributed hash across processes/machines
        # (unlike [string].GetHashCode() which is randomized per process in .NET Core).
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
            $hash  = $sha256.ComputeHash($bytes)
        }
        finally {
            $sha256.Dispose()
        }

        # Use the first 8 bytes as an unsigned 64-bit integer for the modulo.
        $value = [System.BitConverter]::ToUInt64($hash, 0)
        $index = [int]($value % [uint64]$GalleryCount)   # 0 .. GalleryCount-1

        # Gallery names only allow alphanumerics, '.' and '_' -> use underscores.
        $suffix = ('{0:D2}' -f ($index + 1))
        return ('gal_{0}_{1}_{2}_{3}' -f $Workload, $Environment, $Region, $suffix).ToLowerInvariant()
    }
}

# Example:
# Get-ImageGalleryName -ImageName 'ubuntu-22.04-base'
'win2022-sql','ubuntu-22.04-base','rhel9-web' | Get-ImageGalleryName
