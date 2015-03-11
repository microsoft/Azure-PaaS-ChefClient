$ErrorActionPreference = "Stop"

[void][Reflection.Assembly]::LoadWithPartialName("Microsoft.WindowsAzure.ServiceRuntime")
$roleEnvironment = [Microsoft.WindowsAzure.ServiceRuntime.RoleEnvironment]

function Get-CloudServiceRole
{
  <#
    .SYNOPSIS
      Gets one or more Azure Roles.
    
    .PARAMETER Current
      If set, gets only the current role.
  #>
  [CmdletBinding()]
  Param
  (
    [Switch] $Current
  )
  Process
  {
    if ($Current)
    {
      return $roleEnvironment::CurrentRoleInstance.Role
    }
    else
    {
      return ($roleEnvironment::Roles).Value
    }
  }
}

function Get-CloudServiceConfigurationSettingValue
{
  <#
    .SYNOPSIS
      Gets the configuration setting value from the Azure CSCFG.
    
    .PARAMETER Name
	  The setting to retrieve.
  #>
  [CmdletBinding()]
  Param
  (
	[Parameter(Mandatory=$true)]
    [string] $Name
  )
  Process
  {
	try
	{
      return $roleEnvironment::GetConfigurationSettingValue($Name);
	}
	catch
	{
	  # TODO: DO we want this in prod? Or just return an error?
	  # If setting doesn't exist. Just return null.
	  return $null;
	}
  }
}

function Get-CloudServiceRoleInstance
{
  <#
    .SYNOPSIS
      Gets one or more Azure Role Instances.
    
    .PARAMETER Role
      The role to get the instances of.
    
    .PARAMETER Current
      If set, gets the current role instance.
  #>
  [CmdletBinding()]
  Param
  (
    [Parameter(Mandatory, ParameterSetName="ByRole")]
    [ValidateNotNull()]
    [Object] $Role,
    
    [Parameter(ParameterSetName="ByCurrent")]
    [Switch] $Current
  )
  Process
  {
    if ($PSCmdlet.ParamSetName -eq "ByRole")
    {
      return $Role.Instances
    }
    else
    {
      return $roleEnvironment::CurrentRoleInstance
    }
  }
}

function Get-CloudServiceLocalResource
{
  <#
    .SYNOPSIS
      Gets details for an Azure Local Resource.
    
    .PARAMETER ResourceName
      The name of the Azure Local Resource.
  #>
  [CmdletBinding()]
  Param
  (
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [String] $ResourceName
  )
  Process
  {
    try
    {
      return $roleEnvironment::GetLocalResource($resourceName)
    }
    catch
    {
      Write-Warning "Unable to get to get Azure local resource $ResourceName, possibly because it does not exist ($_)."
      return $null
    }
  }
}

function Get-CloudServiceEnvironmentType
{
  <#
    .SYNOPSIS
      Gets the type of environment that the scripts are currently running in.
    
    .NOTES
      Will be one of "Emulated", "Azure", or "NotAvailable"
  #>
  [CmdletBinding()]
  Param()
  Process
  {
    if ($roleEnvironment::IsAvailable)
    {
      if ($roleEnvironment::IsEmulated)
      {
        return "Emulated"
      }
      
      return "Azure"
    }
    
    return "NotAvailable"
  }
}

Export-ModuleMember Get-CloudServiceRole
Export-ModuleMember Get-CloudServiceRoleInstance
Export-ModuleMember Get-CloudServiceLocalResource
Export-ModuleMember Get-CloudServiceEnvironmentType
Export-ModuleMember Get-CloudServiceConfigurationSettingValue
