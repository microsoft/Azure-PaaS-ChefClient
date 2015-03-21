<#
    .SYNOPSIS
      Runs the unit tests for the Chef Client Installer

    .DESCRIPTION
      Builds the Chef Client Installer using the Powershellution Module. Then
      executes unit tests for the Chef Client Installer. Functions are 
      mocked to have no impact on the computer on which you execute the script
      and to have no external dependencies.

    .INPUTS
      <None>

    .OUTPUTS
      <Test results>

    .NOTES
      Requires Pester (PowerShell Testing Framework). Download from 
        https://github.com/pester/Pester 
      or use Chocolatey (https://chocolatey.org/)
        choco install pester
      or use PsGet (http://psget.net/)
        Install-Module Pester
      to install 
#>
$ModuleUnderTest = "InstallationSDK.ChefClientInstaller"
$PSProjDepedencies = @( )
$ModuleDependencies = @()
$ErrorActionPreference = "STOP"

$modulesToCleanup = @($ModuleUnderTest)


Import-Module Pester

#region Helper Functions

function WriteVerbose
{
    param($msg)

    Write-Verbose ("{0}: {1}" -f (Split-Path -Leaf $MyInvocation.ScriptName),$msg)
}

function ImportModuleAndToCleanupList
{
    param($module)

    Import-Module $module
    $script:modulesToCleanup += $module
}

function SafeAddModuleFolderToPSRoot
{
    param($moduleFolder)

    if (-not $env:PSModulePath.Contains($moduleFolder))
    {
        $env:PSModulePath += ";$moduleFolder"
    }
}

function Cleanup
{
    foreach($module in $modulesToCleanup)
    {
        Remove-Module $module -Force -ErrorAction SilentlyContinue
    }

    # Eh, sometimes Pester fails with the error that TestDrive already exists.. clear it for them
    Remove-Variable -Name TestDrive -Force -Scope Script -ErrorAction SilentlyContinue
}

function CreateRoleInstanceEndpoint
{
param(
    [string]$parsableIPAddress,
    [string]$parsableIPAddressPublic,
    [string]$protocol
)

    $ip = $parsableIPAddress.Split(":")
    $ipEndpoint = New-Object System.Net.IPEndPoint -ArgumentList ([System.Net.IPAddress]$ip[0], $ip[1])

    $publicIpEndpoint = $null
    if($parsableIPAddressPublic)
    {
        $public = $parsableIPAddressPublic.Split(":")
        $publicIpEndpoint = New-Object System.Net.IPEndPoint -ArgumentList ([System.Net.IPAddress]$public[0], $public[1])
    }

    New-Object psobject -Property @{
        "IPEndpoint" = $ipEndpoint
        "PublicIPEndpoint" = $publicIpEndpoint
        "Protocol" = $protocol
    }
}

function CreateVirtualIPEndpoint
{
param(
    [string]$groupName,
    [System.Net.IPAddress[]]$ipAddresses,
    $roleInstanceEndpoints
)
    # Weird dictionary thingy
    $instanceEndpoints = @{}
    $i = 0
    foreach($roleInstanceEndpoint in $roleInstanceEndpoints)
    {
        $instanceEndpoints[($i++)] = $roleInstanceEndpoint
    }

    $virtualIpEndpoints = @{}
    foreach($ipAddress in $ipAddresses)
    {
        $virtualIpEndpoints[$ipAddress] = New-Object psobject -Property @{
            "PublicIPAddress" = $ipAddress
            "InstanceEndpoints" = $instanceEndpoints
        }
    }

    New-Object psobject -Property @{
        "VirtualIPGroupName" = $groupName
        "VirtualIPEndpoints" = $virtualIpEndpoints
    }
}
#endregion

#region Setup

#
# Ensure clean environment
#
WriteVerbose "Remove modules to ensure a clean environment"
Cleanup

#
# Build Dependent psprojs
#
WriteVerbose "Building Project Dependencies"
foreach ($dependantPSproject in $PSProjDepedencies)
{
    $moduleFolder = Join-Path (Split-Path $dependantPSproject) "bin"
    $moduleName = [IO.Path]::GetFileNameWithoutExtension((Split-Path -Leaf $dependantPSproject))

    if (Test-Path $moduleFolder)
    {
        Remove-Item -Path $moduleFolder -Recurse -Force
    }

    New-ProjectBuild -Path $dependantPSproject

    SafeAddModuleFolderToPSRoot $moduleFolder
    ImportModuleAndToCleanupList $moduleName
}

#
# Build Module Under Test
#
$ModuleRoot = Join-Path $PSScriptRoot "bin"
WriteVerbose "Building the Module Under Test"
if (Test-Path $ModuleRoot)
{
    Remove-Item -Path $ModuleRoot -Recurse -Force
}

$psprojFile = Resolve-Path (Join-Path $PSScriptRoot "*.psproj")
Write-Verbose "Building psproj: $psprojFile"
New-ProjectBuild -Path $psprojFile

#
# Loading Module-Under-Test
#
WriteVerbose "Loading Module-Under-Test"
SafeAddModuleFolderToPSRoot $moduleRoot
Import-Module $ModuleUnderTest

#endregion

#
# Ready to run tests!
#
InModuleScope $ModuleUnderTest {
    Describe "Get-ChefClientConfig" {
        $tempFile = "TestDrive:\test.txt"

        It "Should parse and return an object" {
            "log_level :info" | Set-Content $tempFile
            $config = Get-ChefClientConfig -Path $tempFile
            $config.log_level | Should Be ":info"
        }

        It "Should parse a value with spaces in them and return an object" {
            "cache_path 'C:\Some Path With Spaces''" | Set-Content $tempFile
            $config = Get-ChefClientConfig -Path $tempFile
            $config.cache_path | Should Be "C:\Some Path With Spaces"
        }

        Context "Given no arguments" {
            It "Should return an empty object" {
                $config = Get-ChefClientConfig
                $members = $config | Get-Member -MemberType NoteProperty | Select-Object -Property Name
                $members.Count -gt 0 | Should Be $true
                ($members | where { $_.Name -eq "node_name" }).Name | Should BeExactly "node_name"
                $config.node_name | Should BeNullOrEmpty
            }
        }
    }

    Describe "Save-ChefClientConfig" {
        $tempFile = "TestDrive:\test.txt"
        $newFile = "TestDrive:\new.txt"
        $templateFile = "TestDrive:\template.rb"

        "cache_path 'C:\chef'`nlog_level :info`ninterval 100" | Set-Content $tempFile
        "now = Time.new`n`nlog_location `"c:/chef/client_`" + now.strftime(`"%Y%m%d`") + `".log`"`nlog_level :info`ninterval 999" | Set-Content $templateFile
        Get-ChefClientConfig -Path $tempFile | Save-ChefClientConfig -Path $newFile

        It "Should save a properly formatted file" {
            $newFile | Should Exist
            $newFile | Should Contain "cache_path\s+'C:\\chef'"        
        }

        It "Should check that symbols are not quoted" {
            $newFile | Should Exist
            $newFile | Should Contain "['`"][^:]"
            $newFile | Should Contain "[^']:"
        }

        It "Should check that numbers are not quoted" {
            $newFile | Should Exist
            $newFile | Should Contain "\s[^'][0-9]"
        }

        It "Should overwrite when -Overwrite is used" {
            # overwrite new file with an empty file, so we can properly check the contents
            New-Item $newFile -ItemType File -Force
            { Get-ChefClientConfig -Path $tempFile | Save-ChefClientConfig -Path $newFile } | Should Throw
            { Get-ChefClientConfig -Path $tempFile | Save-ChefClientConfig -Path $newFile -Overwrite } | Should Not Throw
            $newFile | Should Exist
            $newFile | Should Contain "cache_path\s+'C:\\chef'"
        }

        It "Should append to an existing file" {
            Get-ChefClientConfig -Path $tempFile | Save-ChefClientConfig -Path $templateFile -Append
            $templateFile | Should Exist
            $templateFile | Should Contain "now = Time\.new"
            $templateFile | Should Contain ([regex]::Escape("log_location `"c:/chef/client_`" + now.strftime(`"%Y%m%d`") + `".log`""))
            $templateFile | Should Contain "interval\s*100"
        }
    }

    Describe "Get-ChefNodeList" {
        Context "Verify Command Line if no client config" {
            Mock Invoke-Knife { "knife $args" }

            It "Should execute 'knife node list' if there's no client" {
                $commandLine = (Get-ChefNodeList).Trim()
                $commandLine | Should BeExactly "knife node list"
            }
        }

        Context "Verify Command Line if client config is specified" {
            Mock Invoke-Knife { "knife $args" }

            $configFile = "TestDrive:\Config.rb"
            "chef_server_url 'http://localhost/organizations/msn'" | Set-Content $configFile
            $configObject = Get-ChefClientConfig -Path $configFile

            It "Should execute 'knife node list -c client.rb' if given the config file path" {
                $commandLine = (Get-ChefNodeList -Config $configFile).Trim()
                $commandLine | Should Match ("knife node list -c {0}" -f [regex]::Escape($configFile))
            }

            It "Should execute 'knife node list -c client.rb' if given the config object" {
                $commandLine = (Get-ChefNodeList -Config $configObject).Trim()
                $commandLine | Should Match "knife node list -c .*"
            }

            It "Should fail if config does not exist" {
                { Get-ChefNodeList -Config "DoesNotExist" } | Should Throw
            }
        }

        Context "Returns as expected" {
            Mock Invoke-Knife { return @("SomeNode_0","SomeNode_1","SomeNode_2") }
            $nodes = Get-ChefNodeList
    
            It "Should return a list of nodes" {
                $nodes | Should Be @("SomeNode_0","SomeNode_1","SomeNode_2")
            }
        }
    }

    Describe "Install-ChefClient" {
        Mock Start-Process {param($FilePath, $ArgumentList) "$FilePath $ArgumentList" }
        Mock Invoke-SC { "sc.exe $args" }
        Mock Set-Path { "$env:path;$args" }

        $InstallLocation = "TestDrive:\Opscode"
        $RootPath = "TestDrive:\Chef"
        $commandLinesToExecute = Install-ChefClient -InstallLocation $InstallLocation -RootPath $RootPath
        
        $msiExecCommand = $commandLinesToExecute[0]
        $scFailureCommand = $commandLinesToExecute[1]
        $scConfigCommand = $commandLinesToExecute[2]
        $path = $commandLinesToExecute[3]
        It "(msiexec) should contain everything it needs to install the chef-client properly" {
            $msiExecCommand | Should Match "msiexec"
            # We currently do not package the msi with the nuget package. Ignore this for now
            # $msiExecCommand | Should Match "\.msi"
            $msiExecCommand | Should Match "ChefClientFeature,ChefServiceFeature"
            $msiExecCommand | Should Match "InstallLocation"
            $msiExecCommand | Should Match "ROOTDRIVE"
        }

        It "(sc) should set the reset on failure settings properly" {
            $scFailureCommand | Should Match "sc.exe"
            $scFailureCommand | Should Match "failure"
            $scFailureCommand | Should Match "chef-client reset= [0-9]* actions= restart/[0-9]*"
        }

        It "(sc) should configure the service with the binpath" {
            $rubyPath = "$InstallLocation\chef\embedded\bin\ruby.exe"
            $servicePath = "$InstallLocation\chef\bin\chef-windows-service"
            $scConfigCommand | Should Match "sc.exe"
            $scConfigCommand | Should Match "config"
            $scConfigCommand | Should Match ("chef-client binpath= `"{0} {1} -c {2} -l {3}`"" -f 
                [regex]::Escape($rubyPath),
                [regex]::Escape($servicePath),
                [regex]::Escape("$RootPath\Client.rb"),
                [regex]::Escape("$RootPath\client.log"))
        }

        It "Path environment variable should installation directory" {
            $path | Should Match ([Regex]::Escape("$InstallLocation\chef\bin"))
        }
    }

    Describe "Export-ChefAzureOhaiHints" {
        Mock Get-CloudServiceRoleInstance {
            param([Switch]$Current)

            # These RoleInstanceEndpoints were taken directly from a "test" azure instance
            $endpoint1 = CreateRoleInstanceEndpoint "100.68.46.96:80" "255.255.255.255:80" "http"
            $rdp = CreateRoleInstanceEndpoint "100.68.46.96:3389" $null "tcp"
            $rdpInput = CreateRoleInstanceEndpoint "100.68.46.96:20000" "255.255.255.255:3389" "tcp"

    
            New-Object psobject -Property @{
                "DeploymentID" = "9662c0f4355042c7b2eae7dd06e70c28"
                "ID" = "WebRole1_IN_0"
                "UpdateDomain" = 0
                "FaultDomain" = 0
                "Role" = New-Object psobject -property @{"Name" = "WebRole1"}
                "InstanceEndpoints" = @{
                    "Endpoint1" = $endpoint1
                    "Microsoft.WindowsAzure.Plugins.RemoteAccess.Rdp" = $rdp
                    "Microsoft.WindowsAzure.Plugins.RemoteForwarder.RdpInput" = $rdpInput
                }
                # Couldn't get a good working sample of VirtualIPGroups, these VirtualIPEndpoints were filled in using reasonable, expected values
                "VirtualIPGroups" = @{
                    "Group1" = CreateVirtualIPEndpoint "SomeGroup1" ("192.167.0.1","192.167.0.2","127.0.0.1") ($endpoint1,$rdp,$rdpInput)
                    "Group2" = CreateVirtualIPEndpoint "SomeGroup2" ("255.255.255.255","0.0.0.0","169.245.214.223") ($endpoint1,$rdp)
                }
            }
        }

        $roleInstance = Get-CloudServiceRoleInstance -Current

        $hintsDirectory = "TestDrive:\\Chef\Ohai\Hints"
        Export-ChefAzureOhaiHints -path $hintsDirectory

        $expectedAzureHintFile = Join-Path $hintsDirectory "azure.json"

        It "Should Parse Correctly" {
            $expectedAzureHintFile | Should Exist
            { ConvertFrom-Json ((Get-Content $expectedAzureHintFile) -join "`n")  } | Should Not Throw
        }

        It "Should have every property defined" {
            $deserialized = ConvertFrom-Json ((Get-Content $expectedAzureHintFile) -join "`n")
            $deserialized.deployment_id | Should Not BeNullOrEmpty
            $deserialized.deployment_id | Should BeExactly $roleInstance.DeploymentID
            $deserialized.role | Should Not BeNullOrEmpty
            $deserialized.role | Should BeExactly $roleInstance.Role.Name
            $deserialized.instance_endpoints.'Microsoft.WindowsAzure.Plugins.RemoteAccess.Rdp'.ip_endpoint | Should Not BeNullOrEmpty
            $deserialized.instance_endpoints.'Microsoft.WindowsAzure.Plugins.RemoteAccess.Rdp'.ip_endpoint | Should BeExactly $roleInstance.InstanceEndpoints["Microsoft.WindowsAzure.Plugins.RemoteAccess.Rdp"].IPEndpoint.ToString()
            $deserialized.instance_endpoints.'Microsoft.WindowsAzure.Plugins.RemoteAccess.Rdp'.public_ip_endpoint | Should BeNullOrEmpty
            $deserialized.virtual_ip_groups.'Group1'.group_name | Should Not BeNullOrEmpty
            $deserialized.virtual_ip_groups.'Group1'.group_name | Should BeExactly $roleInstance.VirtualIPGroups["Group1"].VirtualIPGroupName
            $deserialized.virtual_ip_groups.'Group1'.virtual_ip_endpoints.'192.167.0.1'.instance_endpoints.'0'.ip_endpoint | Should Not BeNullOrEmpty
            $deserialized.virtual_ip_groups.'Group1'.virtual_ip_endpoints.'192.167.0.1'.instance_endpoints.'0'.ip_endpoint | Should BeExactly $roleInstance.VirtualIPGroups["Group1"].VirtualIPEndpoints[[Net.IPAddress]"192.167.0.1"].InstanceEndpoints[0].IPEndpoint.ToString()
        }
    }
}

#
# Clean-up
#
WriteVerbose "DONE! Cleaning up"
Cleanup