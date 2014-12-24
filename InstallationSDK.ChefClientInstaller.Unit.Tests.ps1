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
$PSProjDepedencies = @(
    Join-Path $PSScriptRoot "..\InstallationSDK.AzureServiceRuntime\InstallationSDK.AzureServiceRuntime.psproj"
    )
$ModuleDependencies = @()
$ErrorActionPreference = "STOP"

$modulesToCleanup = @($ModuleUnderTest)


Import-Module Pester
Import-Module Powershellution

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
    New-ProjectBuild -Path $dependantPSproject
    $moduleName = [IO.Path]::GetFileNameWithoutExtension((Split-Path -Leaf $dependantPSproject))
    $moduleFolder = Join-Path (Split-Path $dependantPSproject) "bin"

    SafeAddModuleFolderToPSRoot $moduleFolder
    ImportModuleAndToCleanupList $moduleName
}

#
# Build Module Under Test
#
WriteVerbose "Building the Module Under Test"
$psprojFile = Resolve-Path (Join-Path $PSScriptRoot "*.psproj")
Write-Verbose "Building psproj: $psprojFile"
New-ProjectBuild -Path $psprojFile

#
# Loading Module-Under-Test
#
WriteVerbose "Loading Module-Under-Test"
$ModuleRoot = Join-Path $PSScriptRoot "bin"
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
            $msiExecCommand | Should Match "\.msi"
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
}

#
# Clean-up
#
WriteVerbose "DONE! Cleaning up"
Cleanup