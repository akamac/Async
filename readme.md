## Framework for asynchronous command execution with runspace pools
Usage example:  

```
$RunspacePool = Create-RunspacePool -PoolSize 4 -Modules Networking -Variables (@{port=24}) -StubHost
$ErrorStream = [ref](@())

$ScriptBlock = {
    [CmdletBinding()]
    param(
        [string] $ip
    )
    Invoke-RestMethod "https://$ip:$port/cgi-bin/discover"
}
$Param = @{
    RunspacePool = $RunspacePool
    ScriptBlock = $ScriptBlock    
}
,(Split-Network -Subnet '192.168.0.0./24' -SubnetSize 32 | % {
    Invoke-Async @Param -Parameters @{ip = $_ -replace '/32$'; Verbose = $true}}
} | Receive-AsyncResults -All -Timeout (28*60) -Verbose -es $ErrorStream

- or -

$Pipelines = 1..10 | Invoke-Async -RunspacePool $RunspacePool -ScriptBlock {[math]::pow($port,$args[0])}
Receive-AsyncResults -Pipelines $Pipelines -All
```  
*The purpose of StubHost class is to suppress output from runspaces*