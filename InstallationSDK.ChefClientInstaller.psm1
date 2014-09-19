# Installer chef client

$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

pushd $PSScriptRoot
try
{
    $msi = (resolve-path "./resources/*msi").path
}
finally
{
    popd
}

function Install-ChefClient
{
  <#
    .SYNOPSIS
      Install Chef Client from Assemblies directory 
    
    .DESCRIPTION
      Run the offline installer for Chef Client
    
    .NOTES
      Downloaded from: http://www.getchef.com/chef/install/
    
    .EXAMPLE
      Install-ChefClient -verbose
  #>

    Process
    {
        # TODO - change the location of the client root via chef-client configuration so that we don't install on the System Drive.
        md d:\chef -ErrorAction SilentlyContinue
        copy-item .\*.rb d:\chef
        copy-item .\*.pem d:\chef
        write-verbose $PSScriptRoot   
        write-verbose "Installing chef client from $msi."
        start-process msiexec -ArgumentList "/qn /i $msi ADDLOCAL=`"ChefClientFeature,ChefServiceFeature`" /log $($msi).log" -Wait
        sc.exe failure "chef-client" reset= 86400 actions= restart/5000
        start-service chef-client
    }
}

Export-ModuleMember Install-ChefClient