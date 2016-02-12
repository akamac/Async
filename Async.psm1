$PSDefaultParameterValues = Import-PSDefaultParameterValues
try {
	#$MyInvocation.MyCommand.Module.RequiredModules does not work here
	(Test-ModuleManifest $PSScriptRoot\*.psd1).RequiredModules | % {
		Import-Module -RequiredVersion $_.Version -Name $_.Name -ea Stop
	}
} catch {
	Write-Error $_.Exception
	throw 'Failed to load required dependency'
}

#------------------------------------------------------------------------------

try {
Add-Type -ea SilentlyContinue -Language CSharpVersion3 -TypeDefinition (Get-Content $PSScriptRoot\StubHost.cs)
} catch {}

function Create-RunspacePool {
    [CmdletBinding()]
    Param (
        [ValidateNotNull()]
        [int] $PoolSize = ($env:NUMBER_OF_PROCESSORS - 1),
        [System.Threading.ApartmentState] $ApartmentState = 'STA',
        [string[]] $Modules,
        [string[]] $SnapIns,
        $Variables, # dictionary
        [timespan] $CleanupInterval,
        [switch] $StubHost
    )
    $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
    $InitialSessionState.ApartmentState = $ApartmentState
    if ($Variables) {
        $Variables.GetEnumerator() | % {
            $InitialSessionState.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry($_.Name,$_.Value,$null)))
        }
    }
    if ($Modules) { $InitialSessionState.ImportPSModule($Modules) }
    if ($SnapIns) { $SnapIns | % { $InitialSessionState.ImportPSSnapIn($_, [ref](New-Object System.Management.Automation.Runspaces.PSSnapInException("Can't load snap-in $_"))) } | Out-Null }
    $RunSpacePool = [RunspaceFactory]::CreateRunspacePool(1, $PoolSize, $InitialSessionState,
    (?: {$StubHost.IsPresent} {New-Object System.Management.Automation.Internal.Host.StubHost} {$Host}))
    if ($CleanupInterval) { $RunSpacePool.CleanupInterval = $CleanupInterval }
    $RunSpacePool.Open()
    $RunSpacePool
}

function Invoke-Async {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.RunspacePool] $RunspacePool,
        [Parameter(Mandatory,ParameterSetName='ScriptBlock')]
        [ScriptBlock] $ScriptBlock,
        [Parameter(Mandatory,ParameterSetName='Command')]
        [string] $Command,
        [Parameter(HelpMessage='Accepted types: hashtable - named, array - positional',ValueFromPipeline)]
        $Parameters
    )
Process {
    $Pipeline = [powershell]::Create()
    $Pipeline.RunspacePool = $RunSpacePool
    if ($PSCmdlet.ParameterSetName -eq 'ScriptBlock') {
        [void]$Pipeline.AddScript($ScriptBlock)
    } else {
        [void]$Pipeline.AddCommand($Command)
    }
    if (-not ($Parameters -as [System.Collections.IDictionary])) {
        $Parameters = ,$Parameters
    }
    if ($Parameters -as [System.Collections.IDictionary] -or
        $Parameters -as [System.Collections.IList]) {
            [void]$Pipeline.AddParameters($Parameters)
    } elseif ($Parameters) {
        throw 'Invalid Parameters type. Accepted types: hashtable/array'
    }
	$AsyncResult = $Pipeline.BeginInvoke()
    [PSCustomObject]@{Pipeline = $Pipeline; AsyncResult = $AsyncResult}
}
}

function Receive-AsyncResults {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory)]
        [System.Collections.ArrayList] $Pipelines,
        [Parameter(Mandatory,ParameterSetName='One')]
		[switch] $One,
        [Parameter(Mandatory,ParameterSetName='All')]
		[switch] $All,
        [Parameter(HelpMessage='In seconds, after pipeline execution started. Default - infinite')]
        [int] $Timeout = 0,
        [Parameter(HelpMessage='Redirect error stream')]
        [Alias('es')]
        [ref] $ErrorStream
    )
    $Pool = $Pipelines[0].Pipeline.RunspacePool
    $i = $Count = $Pipelines.Count
    Write-Verbose 'Waiting for threads'
    $StartTime = Get-Date
    :done while ($i) {
        Write-Progress -Activity 'Waiting threads execution results' -Status "$i of $Count threads remaining" `
        -PercentComplete (100*(1 - $i/$Count))
        $Completed = $Pipelines.Where({$_.AsyncResult.IsCompleted})
        $Completed | % { # | % { # ? {$_.AsyncResult.AsyncWaitHandle.WaitOne(0)}
            try {
                if ($Timeout -and ((Get-Date) - $StartTime).Seconds -ge $Timeout) {
                    throw 'Specified timeout reached'
                }
                #Write-Verbose 'Parameters:'
                #$_.Pipeline.Commands.Commands.Parameters | ? Name -notin ErrorAction,WarningAction,Verbose |
                #% { Write-Verbose ($_.Name,$_.Value -join ' ')}
                #Write-Verbose 'Thread verbose stream:'
                @($_.Pipeline.Streams.Verbose) -ne $null | % { Write-Verbose $_ }
                if ($_.Pipeline.Streams.Error) {
                    Write-Verbose 'Error occured'
				    throw ($_.Pipeline)
			    } else {
                    Write-Verbose 'Finished successfully'
                    $_.Pipeline.EndInvoke($_.AsyncResult)
                }
            } catch {
                if ($ErrorStream) {
                    $ErrorStream.Value += $_.TargetObject
                } else {
                    $_.TargetObject.Streams.Error.Exception.Message |
                    % { Write-Error $_ }
                }
            } finally { 
                $_.Pipeline.Dispose()
                $Pipelines.Remove($_)
                $i--
                if (-not $i) {
                    $Pool.Close()
                    $Pool.Dispose()
                }
            }
            if ($PSCmdlet.ParameterSetName -eq 'One') { break done }
        }
    }
}