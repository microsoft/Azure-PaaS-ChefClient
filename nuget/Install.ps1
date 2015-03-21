Param
(
  # Path to the folder where the package is installed
  $installPath,
  
  # Path to the tools directory in the folder where the package is installed
  $toolsPath,
  
  # A reference to the package object
  $package,
  
  # A reference to the EnvDTE project object and represents the project the package is installed into.
  # http://msdn.microsoft.com/en-us/library/51h9a6ew(v=VS.80).aspx
  $project
)

# http://msdn.microsoft.com/en-us/library/aa983962(VS.71).aspx
$BuildTypes = @{
  "None" = "0";
  "Compile" = "1";
  "Content" = "2";
}

$CopyToOutputDirectory = @{
  "DoNotCopy" = "0";
  "CopyAlways" = "1";
  "CopyIfNewer" = "2";
}

function Add-ContentsToProjectOutput
{
  <#
    .DESCRIPTION
      If the project item given by ProjectItem exists at the corresponding location given by PackagePath,
      then sets its properties such that the item will be copied to the build output. The intent is to not
      modify user's file which may also be present under the given project item.
    
    .PARAMETER ProjectItem
      The project item; should be a child object of a VS project.
    
    .PARAMETER PackagePath
      The physical path that should correspond to ProjectItem. If the path does not exist or otherwise does
      not match ProjectItem, then it will not be modified.
    
    .PARAMETER ProjectPath
      The logical path of the ProjectItem within the project. Used purely for logging.
    
    .PARAMETER Recurse
      A value indicating whether a ProjectItem whose type is PhysicalDirectory should be traversed.
  #>
  [CmdletBinding()]
  Param
  (
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [Object] $ProjectItem,
    
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String] $PackagePath,
    
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [String] $ProjectPath = "./",
    
    [Parameter()]
    [Switch] $Recurse
  )
  Process
  {
    $name = $ProjectItem.Name
    
    if ((IsPhysicalFolder $ProjectItem) -and $Recurse)
    {
      if (-not (Test-Path $PackagePath -PathType Container))
      {
        Write-Verbose "Folder '$ProjectPath' does not exist at location '$PackagePath'"
        return $null
      }
      
      Write-Verbose "'$ProjectPath' maps to folder '$PackagePath', checking its contents"
      
      return ($ProjectItem.ProjectItems | % {
        Add-ContentsToProjectOutput `
          -ProjectItem $_ `
          -PackagePath (Join-Path $PackagePath $_.Name) `
          -ProjectPath (Join-Path $ProjectPath $_.Name) `
          -Recurse:$Recurse
      })
    }
    elseif (IsPhysicalFile $ProjectItem)
    {
      if (-not (Test-Path $PackagePath -PathType Leaf))
      {
        Write-Verbose "File '$ProjectPath' does not exist at location '$PackagePath'"
        return $null
      }
      
      Write-Verbose "'$ProjectPath' maps to file '$PackagePath', adding it to build output"
      
      $ProjectItem.Properties.Item("CopyToOutputDirectory").Value = $CopyToOutputDirectory.CopyIfNewer
      $ProjectItem.Properties.Item("BuildAction").Value = $BuildTypes.None
      
      return $ProjectItem
    }
  }
}

function IsPhysicalFolder
{
  [CmdletBinding()]
  Param
  (
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [Object] $ProjectItem
  )
  Process
  {
    return ($ProjectItem.Kind -ieq "{6bb5f8ef-4483-11d3-8bcf-00c04f8ec28c}")
  }
}

function IsPhysicalFile
{
  [CmdletBinding()]
  Param
  (
    [Parameter(Mandatory)]
    [ValidateNotNull()]
    [Object] $ProjectItem
  )
  Process
  {
    return ($ProjectItem.Kind -ieq "{6bb5f8ee-4483-11d3-8bcf-00c04f8ec28c}")
  }
}

$rootItem = $project.ProjectItems.Item("Deployment")

if (-not $rootItem)
{
  Write-Warning "Root 'Deployment' item does not exist."
  return
}

$modified = Add-ContentsToProjectOutput `
  -ProjectItem $rootItem `
  -PackagePath (Join-Path $installPath "content/Deployment/")`
  -ProjectPath $rootItem.Name `
  -Recurse

Write-Verbose "Modified $($modified.Count) item(s)." 

return $modified
