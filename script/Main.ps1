param(
    [String]$ClientRb = "Client.rb",
    [string]$ClientPem = "client.pem",
    [string]$RootPath = "C:\chef\"
)

$ErrorActionPreference = "Stop"
Write-Output "Script:main.ps1 starting"

$pathToClientPem = Join-path -Path $RootPath -ChildPath $ClientPem
$pathToClientRb = Join-path -Path $RootPath -ChildPath $ClientRb

if (Test-Path $PathToClientPem)
{
    Write-Output "Script:main.ps1 $pathToClientPem already exists. Nothing to do. Exiting"
    return
}

# Add approot module path
$modulePath = resolve-Path -Path $PSScriptRoot\Modules
if(-not $env:PSModulePath.Contains($modulePath.Path))
{
    $env:PSModulePath += (";" + $modulePath.Path)
    Write-Output "PSModulePath: $env:PSModulePath"
}

# Insert your custom logic below...

# Import modules
Import-Module InstallationSDK.ChefClientInstaller
Import-Module InstallationSDK.AzureServiceRuntime

# Go ahead and install, we'll need the knife tool later
# Override the rootdrive, for Azure
Install-ChefClient -RootDrive "C:" -RootPath $RootPath

$ClientRbObject = $null

# Get template Client.rb file, if it exists
$TemplateClientRb = Join-Path $PSScriptRoot $ClientRb

$ClientRbObject = Get-ChefClientConfig

# Set node name. Format: [cloud service name]_IN_[Azure instance number]
Get-CloudServiceRoleInstance -ErrorAction Continue | out-Null
$roleInstance = Get-CloudServiceRoleInstance
$config = ConvertFrom-Json ((Get-Content $PSScriptRoot\config.json -ErrorAction SilentlyContinue) -join "`n")
$name = $roleInstance.DeploymentID
$roleName = $roleInstance.Id.Substring(0, $roleInstance.Id.IndexOf("_"))
if ($config -and $config.name)
{
    $name = $config.name
}

# Add Instance number to the node name
Write-Output "Role Instance Name: $($roleInstance.Id)"
$nodeName = $($roleInstance.Id).Replace($roleName, $name)

# Set ssl_verify_mode on Client.rb. (As of Chef 12, it defaults to :verify_peer). 
# For Non-Production ONLY: Unless a valid certificate is set, need to use :verify_none
if ($config -and $config.sslVerifyMode)
{
    $sslVerifyMode = $config.sslVerifyMode
    $ClientRbObject.ssl_verify_mode = $sslVerifyMode
    Write-Output "Set ssl_verify_mode to: $sslVerifyMode"
    if ($sslVerifyMode -eq ":verify_none")
    {
        Write-Warning "`"ssl_verify_mode: '$sslVerifyMode'`" should only be used for testing purposes only!"
    }
}

# Try to get server_url from Cloud Service CsCfg first. If not, check the config.json
# Value from Cloud Service CsCfg always wins.
$url = Get-CloudServiceConfigurationSettingValue "ChefClient_ServerUrl"
if (-not $url -and ($config -and $config.serverUrl))
{
    $url = $config.serverUrl
}

if ($url)
{
    $ClientRbObject.chef_server_url = $url
    Write-Output "Set chef url to: $url"

    #
    # If we're connecting to the server. Client Name and Validation Key needs to be set
    #

    # Validation client name is now on a per-org basis
    if ($config -and $config.ValidationClientName)
    {
        $validationClientName = $config.ValidationClientName
        $ClientRbObject.validation_client_name = $validationClientName
        Write-Output "Set Validation Client Name to '$validationClientName'"

        # Temporarily set node name to validation client name. This is so we can call node list and determine what names are available
        $ClientRbObject.node_name = $validationClientName
    }
    else
    {
        throw "Validation client name must be set if serverUrl is defined"
    }

    # Try to get validationKey from Cloud Service CsCfg first. If not, check the config.json
    # Value from Cloud Service CsCfg always wins.
    $validationKey = Get-CloudServiceConfigurationSettingValue "ChefClient_ValidationKey"
    if (-not $validationKey -and ($config -and $config.validationKey))
    {
        $validationKey = $config.validationKey
    }

    if ($validationKey)
    {
        # Ensure the key exists with that filename
        $validationKeyTemp = Join-Path $PSScriptRoot $validationKey 
        if (-not (Test-Path $validationKeyTemp))
        {
            throw "Did not find validation key at path $(Join-Path $PSScriptRoot $validationKey)"
        }
        
        $pathToValidationKey = Join-Path $RootPath $validationKey

        Copy-Item $validationKeyTemp $pathToValidationKey -Force
        $ClientRBObject.validation_key = $pathToValidationKey
        Write-Output "Set validation key to '$pathToValidationKey'"

        # Temporarily set node name to validation client name. This is so we can call node list and determine what names are available
        $ClientRbObject.client_key = $pathToValidationKey
    }
    else
    {
        throw "Validation key must be set if serverUrl is defined"
    }

    #
    # Check if the node's name is available
    #
    $tempConfigFile = $null
    try
    {
        $tempConfigFile = [IO.Path]::GetRandomFileName()
        Copy-Item -Path $TemplateClientRb -Destination $tempConfigFile
        Save-ChefClientConfig -InputObject $ClientRbObject -Path $tempConfigFile -Append
        $nodes = Get-ChefNodeList -Config $tempConfigFile
    }
    finally
    {
        if ($tempConfigFile)
        {
            Remove-Item -Path $tempConfigFile -ErrorAction SilentlyContinue
        }
    }
    
    # increment the node name until one exists that doesn't conflict
    $baseName = $nodeName
    for($i = 1; $nodes.Contains($nodeName) ;$i++)
    {
        $nodeName = "$baseName{0}" -f ".$i"
    }
}
else
{
    Write-Output "chef url not set in configuration file. Node will not register with Chef Server."
}

# Alter client.rb with new node name
$ClientRbObject.node_name = $nodeName
Write-Output "Set chef node_name to: $nodeName"
$ClientRbObject.client_key = $pathToClientPem
Write-Output "Set chef client_key to: $pathToClientRb"

if ($config -and $config.pollInterval)
{
    $interval = $config.pollInterval
    $ClientRbObject.interval = $interval
    Write-Output "Set poll interval to: $interval seconds"
}
else
{
    Write-Output "Poll Interval not set. Default value (if not set) is 1800s (30m)."
}

# Create first-run-bootstrap.json to register new node with Chef Server
if ($config -and $config.role)
{
    # Register with the correct update domain role [role name]
    $chefRole = $($config.role)
    $bootStrapperFile = "first-run-bootstrap.json"
    $bootStrapper = "{`r`n `"run_list`": [ `"role[$chefRole]`" ]`r`n}"
    Write-Output "Setting bootstrap content: $bootStrapper"
    
    $pathToBootStrapper = Join-Path $RootPath $bootStrapperFile
    $bootStrapper | Out-File $pathToBootStrapper -Encoding ascii
    $ClientRbObject.json_attribs = $pathToBootStrapper
    
    Write-Output "Set bootstrapper path to: '$pathToBootStrapper'"
}

Copy-Item -Path $TemplateClientRb -Destination $pathToClientRb -Force
$ClientRbObject | Save-ChefClientConfig -Path $pathToClientRb -Append

start-service chef-client

Write-Output "Script:main.ps1 exiting"
