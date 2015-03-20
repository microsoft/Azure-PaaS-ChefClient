$VerbosePreference = "Continue"

$exitCode = 1

& {
  $VerbosePreference = "Continue"
  Write-Verbose "Starting installation from $(pwd)"
  
  try
  {
    .\Main.ps1
  }
  catch
  {
    Write-Verbose "$_"
    
    if ($_ -is [System.Management.Automation.ErrorRecord])
    {
      Write-Verbose "$($_.ScriptStackTrace)"      
    }
    elseif ($_ -is [Exception])
    {
      Write-Verbose "$($_.ErrorRecord.ScriptStackTrace)"
    }
    
    throw
  }
  
  $Script:exitCode = 0
} *> .\Start.transcript.log 

exit $exitCode
