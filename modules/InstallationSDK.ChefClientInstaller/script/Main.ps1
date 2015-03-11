param(
    [String]$ClientRb = "Client.rb",
    [string]$ClientPem = "client.pem",
    [string]$RootPath = "C:\chef\"
)

$ErrorActionPreference = "Stop"
Write-Output "Script:main.ps1 starting"

$pathToClientPem = Join-path -Path $RootPath -ChildPath $ClientPem
$pathToClientRb = Join-path -Path $RootPath -ChildPath $ClientRb

# Set up the client chef folder structure that our cookbooks use (like PSModules cookbook).
$dllsPath = [System.IO.Path]::Combine($RootPath, "dlls")
$PSModulesPath = [System.IO.Path]::Combine($RootPath, "PSModules")
$ScriptsPath = [System.IO.Path]::Combine($RootPath, "scripts")
@($RootPath, $dllsPath, $PSModulesPath, $ScriptsPath) | % {
    if (!(Test-Path -Path $_)) 
    { 
        md $_ 
    }
}

# Persist the PSModulesPath for client execution to find our Share Modules Cookbook.
if (!($env:PSModulePath.Contains($PSModulesPath)))
{
    $env:PSModulePath += ";" + $PSModulesPath
    [Environment]::SetEnvironmentVariable("PSModulePath", $env:PSModulePath,  [System.EnvironmentVariableTarget]::Machine)
}

# Add approot module path for this session
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
Install-ChefClient -RootDrive "C:" -RootPath $RootPath -LogFile ("client_{0}.log" -f [DateTime]::Today.ToString("yyyyMMdd"))

$ClientRbObject = $null

# Get template Client.rb file, if it exists
$TemplateClientRb = Join-Path $PSScriptRoot $ClientRb

$ClientRbObject = Get-ChefClientConfig -Path $pathToClientRb

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

# Allow to pull from CSCFG allowing for easier targetting of node name prefix, this can only be set on initial deployment
# once the node name is established, the exisitng name will always win.
$cscfgName = Get-CloudServiceConfigurationSettingValue "ChefClient_Name"
if ($cscfgName)
{
    $name = $cscfgName
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

# Set the default encrypted_data_bag_secret

#
# Get Value (actual key) from RoleEnvironment
#

$encryptedDataBagSecret = Get-CloudServiceConfigurationSettingValue "ChefClient_EncryptedDataBagSecret"
if ($encryptedDataBagSecret)
{
    $pathToEncryptedDataBagSecret = Join-path -Path $RootPath -ChildPath "encrypted_data_bag_secret"
    $encryptedDataBagSecret | Set-Content -Path $pathToEncryptedDataBagSecret -Force

    Write-Output "Encrypted Data Bag Secret set to: $encryptedDataBagSecret"
}
elseif ($config -and $config.encrypted_data_bag_secret_file)
{
    $encryptedDataBagSecretFile = $config.encrypted_data_bag_secret_file

    # Ensure the secret exists with that filename
    $encryptedDataBagSecretFileTemp = Join-Path $PSScriptRoot $encryptedDataBagSecretFile 
    if (-not (Test-Path $encryptedDataBagSecretFileTemp))
    {
        throw "Did not find the encrypted_data_bag_secret at path $encryptedDataBagSecretFileTemp"
    }
        
    $pathToEncryptedDataBagSecret = Join-path -Path $RootPath -ChildPath $encryptedDataBagSecretFile

    Copy-Item $encryptedDataBagSecretFileTemp $pathToEncryptedDataBagSecret -Force
}

if ($pathToEncryptedDataBagSecret)
{
    $ClientRbObject.encrypted_data_bag_secret = $pathToEncryptedDataBagSecret 

    Write-Output "Set encrypted_data_bag to: $pathToEncryptedDataBagSecret"
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
    # Clear client pem to register with new server.
    if($ClientRbObject.chef_server_url -ne $url)
    {
        if(test-path -Path $pathToClientPem)
        {
            remove-item -Path $pathToClientPem -Force
        }
        $ClientRbObject.node_name = ""
    }
    
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

    }
    else
    {
        throw "Validation client name must be set if serverUrl is defined"
    }

    $validationKey = $config.validationKey

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
    }
    else
    {
        throw "Validation key must be set if serverUrl is defined"
    }

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

    #Check if the client.rb already has a node_name
    if((-not [System.String]::IsNullOrWhiteSpace($ClientRbObject.node_name) -and (Test-Path $pathToClientPem)))
    {
        Write-Output "Script:main.ps1 $pathToClientPem already exists. Register as existing node."
    }
    else
    {        
        #
        # Check if the node's name is available
        #
        $knifeConfigFile = $null

        $knifeConfigFile = "knife.rb"
        Copy-Item -Path $TemplateClientRb -Destination $knifeConfigFile -Force

        # Temporarily set node name to validation client name key. This is so we can call node list 
        # and determine what names are available. Make sure to remove the environment property.
        $knifeRbObject = $ClientRbObject.PSObject.Copy()
        $knifeRbObject.client_key = $pathToValidationKey
        $knifeRbObject.node_name = $validationClientName
        $knifeRbObject.PSObject.Properties.Remove('environment')

        Save-ChefClientConfig -InputObject $knifeRbObject -Path $knifeConfigFile -Overwrite
            
        #run node list
        $nodes = Get-ChefNodeList -Config $knifeConfigFile

        # increment the node name until one exists that doesn't conflict
        $baseName = $nodeName
        for($i = 1; $nodes.Contains($nodeName) ;$i++)
        {
            $nodeName = "$baseName{0}" -f ".$i"
        }

        # Alter client.rb with new node name
        $ClientRbObject.node_name = $nodeName
        Write-Output "Set chef node_name to: $nodeName"
        $ClientRbObject.client_key = $pathToClientPem
        Write-Output "Set chef client_key to: $pathToClientRb"
    }
}
else
{
    Write-Output "chef url not set in configuration file. Node will not register with Chef Server."
}

# Value from Cloud Service CsCfg always wins.
$chefRole = Get-CloudServiceConfigurationSettingValue "ChefClient_Role"
# Create first-run-bootstrap.json to register new node with Chef Server
if ($chefRole -or ($config -and $config.role))
{
    # Register with the correct update domain role [role name]
    if (-not $chefRole)
    {
        $chefRole = $($config.role)
    }
    $bootStrapperFile = "first-run-bootstrap.json"
    $bootStrapper = "{`r`n `"run_list`": [ `"role[$chefRole]`" ]`r`n}"
    Write-Output "Setting bootstrap content: $bootStrapper"
    
    $pathToBootStrapper = Join-Path $RootPath $bootStrapperFile
    $bootStrapper | Out-File $pathToBootStrapper -Encoding ascii
    $ClientRbObject.json_attribs = $pathToBootStrapper
    
    Write-Output "Set bootstrapper path to: '$pathToBootStrapper'"
}

# Value from Cloud Service CsCfg always wins.
$chefEnvironment = Get-CloudServiceConfigurationSettingValue "ChefClient_Environment"
if ($chefEnvironment)
{
    $ClientRbObject.environment = $chefEnvironment
}

Copy-Item -Path $TemplateClientRb -Destination $pathToClientRb -Force
$ClientRbObject | Save-ChefClientConfig -Path $pathToClientRb -Append

# Setup Azure Ohai
Export-ChefAzureOhaiHints

start-service chef-client

Write-Output "Script:main.ps1 exiting"
