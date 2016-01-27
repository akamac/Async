$Script:PSDefaultParameterValues = $Global:PSDefaultParameterValues.Clone()

try {
Add-Type -ea SilentlyContinue @'
namespace System.Management.Automation.Internal.Host {
    using System;
    using System.Globalization;
    using System.Management.Automation.Host;
    
    public class SHost {
        private bool shouldExit;
        private int exitCode;
        public bool ShouldExit {
            get { return this.shouldExit; }
            set { this.shouldExit = value; }
        }
        public int ExitCode {
            get { return this.exitCode; }
            set { this.exitCode = value; }
        }
        private static void Main(string[] args) {
        }
    }

    public class StubHost : PSHost {
        private SHost program;
        private CultureInfo originalCultureInfo =
            System.Threading.Thread.CurrentThread.CurrentCulture;
        private CultureInfo originalUICultureInfo =
            System.Threading.Thread.CurrentThread.CurrentUICulture;
        private Guid instanceId = Guid.NewGuid();
        
        public StubHost() {}
        public StubHost(SHost program) {
            this.program = program;
        }
        public override CultureInfo CurrentCulture {
            get { return this.originalCultureInfo; }
        }
        public override CultureInfo CurrentUICulture {
            get { return this.originalUICultureInfo; }
        }
        public override Guid InstanceId {
            get { return this.instanceId; }
        }
        public override string Name {
            get { return "StubHost"; }
        }
        public override PSHostUserInterface UI {
            get { return null; }
        }
        public override Version Version {
            get { return new Version(1, 0); }
        }
        public override void EnterNestedPrompt() {
            throw new NotImplementedException(
                "The method or operation is not implemented.");
        }
        public override void ExitNestedPrompt() {
            throw new NotImplementedException(
                "The method or operation is not implemented.");
        }
        public override void NotifyBeginApplication() {
            return;  
        }
        public override void NotifyEndApplication() {
            return; 
        }
        public override void SetShouldExit(int exitCode) {
            this.program.ShouldExit = true;
            this.program.ExitCode = exitCode;
        }
    }
}
'@
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