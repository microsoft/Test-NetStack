[CmdletBinding()]
Param(
  [Parameter(Mandatory=$True, Position=1, HelpMessage="Interface index of the adapter for which RDMA config is to be verified")]
  [string] $IfIndex,  
  [Parameter(Mandatory=$True, Position=2, HelpMessage="True if underlying fabric type is RoCE. False for iWarp or IB")]
  [bool] $IsRoCE,
  [Parameter(Mandatory=$True, Position=3, HelpMessage="IP address of the remote RDMA adapter")]
  [string] $RemoteIpAddress,
  [Parameter(Mandatory=$False, Position=4, HelpMessage="Full path to the folder containing diskspd.exe")]
  [string] $PathToDiskspd,
  [Parameter(Mandatory=$False, Position=5, HelpMessage="Output level [none|verbose|debug]")]
  [string] $OutputLevel, 
  [Parameter(Mandatory=$False, Position=6, HelpMessage="Interface ID of VF driver in Guest OS (mandatory for Guest RDMA tests only)")]
  [string] $VfIndex,
  [Parameter(Mandatory=$False, Position=7, HelpMessage="Host name of the remote RDMA adapter. NDKPing tests will fail without this.")]
  [string] $RemoteName,
  [Parameter(Mandatory=$False, Position=8, HelpMessage="Path to NDKPing.exe and NDKPing.sys if NDKPing is not native to OS. Leave empty to not run.")]
  [string] $NDKPingPath)
  

if ($OutputLevel -eq "none") 
{
    $OutputLevel = 0
}
elseif ($OutputLevel -eq "debug" )
{
    $OutputLevel = 2
}
else
{
    $OutputLevel = 1  # verbose
}

$port = 9000

$OsRelease = [System.Environment]::OSVersion.Version.Build

if($OsRelease -like '*14393*')
{
    $OsRelease = 'RS1'
}

$adapter = Get-NetAdapter -InterfaceIndex $IfIndex
$padapter = (Get-VMNetworkAdapterTeamMapping -VMNetworkAdapterName $adapter.Name -managementos).NetAdapterName
$padapter = Get-NetAdapter -Name $padapter
$NDKPingReady = 'No'

if(-not ($padapter.InterfaceDescription -like '*QLogic*') -and $OSRelease -ne 'RS1')
{
    if($OsRelease -gt 18800)
    {
         $NDKPingReady = 'Native'
    }
    elseif($NDKPingPath -ne $null)
    {
        #If a path to NDKPing.sys and NDKPing.exe is provided, we will create a new NDKPing service to run the test
        $NDKPingReady = 'Not Native'
    }
}

$LogFileName = [Environment]::GetEnvironmentVariable("SystemDrive") + "\NDKPing-$RemoteName.log"

if($NDKPingReady -eq 'Not Native')
{
    #create NDKPing service if it doesn't already exist
    if(-not (get-service 'NDKPing' -ErrorAction SilentlyContinue))
    {
        cmd /c "sc create NDKPing type=kernel binpath=$NDKPingPath\NDKPing.sys"
    }
}

if ($RemoteIpAddress -ne $null)
{
    if (($PathToDiskspd -eq $null) -Or ($PathToDiskspd -eq ''))
    {
        $PathToDiskspd = "C:\Windows\System32"
    }
    
    $FullPathToDiskspd = $PathToDiskspd + "\diskspd.exe"
    if ((Test-Path $FullPathToDiskspd) -eq $false)
    {
        Write-Host "ERROR: Diskspd.exe not found at" $FullPathToDiskspd ". Please download diskspd.exe and place it in the specified location. Exiting." -ForegroundColor Red
        return
    }
    elseif ($OutputLevel -gt 0)
    {
        Write-Host "VERBOSE: Diskspd.exe found at" $FullPathToDiskspd 
    }
}


$rdmaAdapter = Get-NetAdapter -IfIndex $IfIndex

if ($outputLevel -eq 2)
{
    Write-Host "DEBUG: Name is " $rdmaAdapter.Name
    Write-Host "DEBUG: IfDesc is " $rdmaAdapter.InterfaceDescription
}

if ($rdmaAdapter -eq $null)
{
    Write-Host "ERROR: The adapter with interface index $IfIndex not found" -ForegroundColor Red
    return
}

$rdmaAdapterName = $rdmaAdapter.Name

if ($rdmaAdapter.InterfaceDescription -Match "Hyper-V Virtual Ethernet Adapter")
{
    $rdmaAdapterType = "vNIC"
} 
elseif ($rdmaAdapter.InterfaceDescription -Match "Microsoft Hyper-V Network Adapter")
{
    $rdmaAdapterType = "vmNIC"
    if( $VfIndex -eq "" )
    {
       Write-Host "ERROR: VF adapter Interface Index missing" -ForegroundColor Red
       return
    }
    $VFAdapter = Get-NetAdapter -IfIndex $VfIndex
    if ($outputLevel -eq 2)
    {    
        Write-Host "DEBUG: VF Name is " $VFAdapter.Name
        Write-Host "DEBUG: IfDesc of VF is " $VFAdapter.InterfaceDescription
    }
    $VFrdmaCapabilities = Get-NetAdapterRdma -InterfaceDescription $VFAdapter.InterfaceDescription
} 
else
{
     $rdmaAdapterType = "pNIC"
}
if ($outputLevel -gt 0)
{
    Write-Host "VERBOSE: The adapter " $rdmaAdapterName " is a " $rdmaAdapterType
}

$rdmaCapabilities = Get-NetAdapterRdma -InterfaceDescription $rdmaAdapter.InterfaceDescription

if ($rdmaCapabilities -eq $null -or $rdmaCapabilities.Enabled -eq $false) 
{
    Write-Host "ERROR: The adapter " $rdmaAdapterName " is not enabled for RDMA" -ForegroundColor Red
    return
}
if ($rdmaAdapterType -eq "vmNIC" -and ( $VFrdmaCapabilities -eq $null -or $VFrdmaCapabilities.Enabled -eq $false ))
{
    Write-Host "ERROR: The VF adapter " $VFAdapter.Name " is not enabled for RDMA" -ForegroundColor Red
    return
}

if ($rdmaCapabilities.MaxQueuePairCount -eq 0)
{ 
    Write-Host "ERROR: RDMA capabilities for adapter $rdmaAdapterName are not valid : MaxQueuePairCount is 0" -ForegroundColor Red
    return
}

if ($rdmaCapabilities.MaxCompletionQueueCount -eq 0)
{
    Write-Host "ERROR: RDMA capabilities for adapter $rdmaAdapterName are not valid : MaxCompletionQueueCount is 0" -ForegroundColor Red
    return
}

$smbClientNetworkInterfaces = Get-SmbClientNetworkInterface

if ($smbClientNetworkInterfaces -eq $null)
{
    Write-Host "ERROR: No network interfaces detected by SMB (Get-SmbClientNetworkInterface)" -ForegroundColor Red
    return 
}

$rdmaAdapterSmbClientNetworkInterface = $null
foreach ($smbClientNetworkInterface in $smbClientNetworkInterfaces)
{
    if ($smbClientNetworkInterface.InterfaceIndex -eq $IfIndex)
    {
        $rdmaAdapterSmbClientNetworkInterface = $smbClientNetworkInterface
    }
}

if ($rdmaAdapterSmbClientNetworkInterface -eq $null)
{
    Write-Host "ERROR: No network interfaces found by SMB for adapter $rdmaAdapterName (Get-SmbClientNetworkInterface)" -ForegroundColor Red
    return
}

if ($rdmaAdapterSmbClientNetworkInterface.RdmaCapable -eq $false)
{
    Write-Host "ERROR: SMB did not detect adapter $rdmaAdapterName as RDMA capable. Make sure the adapter is bound to TCP/IP and not to other protocol like vmSwitch." -ForegroundColor Red
    return
}

$rdmaAdapters = $rdmaAdapter
if ($RdmaAdapterType -eq "vNIC")
{
    if ($OutputLevel -gt 0)
    {
        Write-Host "VERBOSE: Retrieving vSwitch bound to the virtual adapter"
    }
    $virtualAdapter = Get-VMNetworkAdapter -ManagementOS | where DeviceId -eq $rdmaAdapter.DeviceID
    $switchName = $virtualAdapter.switchName
    if ($OutputLevel -gt 0)
    {
        Write-Host "VERBOSE: Found vSwitch: $switchName"
    }
    $vSwitch = Get-VMSwitch -Name $switchName
    $rdmaAdapters = Get-NetAdapter -InterfaceDescription $vSwitch.NetAdapterInterfaceDescriptions
    if ($OutputLevel -gt 0)
    {
        $vSwitchAdapterMessage = "VERBOSE: Found the following physical adapter(s) bound to vSwitch: "
        $index = 1
        foreach ($qosAdapter in $rdmaAdapters)
        {        
            $qosAdapterName = $qosAdapter.Name
            $vSwitchAdapterMessage = $vSwitchAdapterMessage + [string]$qosAdapterName
            if ($index -lt $rdmaAdapters.Length)
            { 
                $vSwitchAdapterMessage = $vSwitchAdapterMessage + ", " 
            }
            $index = $index + 1
        }
        Write-Host $vSwitchAdapterMessage 
    }
}


if ($IsRoCE -eq $true -and $RdmaAdapterType -ne "vmNIC")
{
    Write-Host "VERBOSE: Underlying adapter is RoCE. Checking if QoS/DCB/PFC is configured on each physical adapter(s)"
    foreach ($qosAdapter in $rdmaAdapters)
    {
        $qosAdapterName = $qosAdapter.Name
        $qos = Get-NetAdapterQos -Name $qosAdapterName 
        if ($qos.Enabled -eq $false)
        {
            Write-Host "ERROR: QoS is not enabled for adapter $qosAdapterName" -ForegroundColor Red
            return            
        }

        if ($qos.OperationalFlowControl -eq "All Priorities Disabled")
        {
            Write-Host "ERROR: Flow control is not enabled for adapter $qosAdapterName" -ForegroundColor Red
            return            
        }
    }
    if ($OutputLevel -gt 0)
    {
        Write-Host "VERBOSE: QoS/DCB/PFC configuration is correct."
    }
} 

if ($RdmaAdapterType -eq "vmNIC")
{
    Write-Host "CAUTION: Guest Virtual NIC being tested, Guest can't check host adapter settings." -ForegroundColor Yellow
}
elseif ($OutputLevel -gt 0)
{
    Write-Host "VERBOSE: RDMA configuration is correct."
}

if ($RemoteIpAddress -ne '')
{
    if ($OutputLevel -eq 2)
    {
        Write-Host "DEBUG: Checking if remote IP address, $RemoteIpAddress, is reachable."
    }
    $canPing = Test-Connection $RemoteIpAddress -Quiet
    if ($canPing -eq $false)
    {
        Write-Host "ERROR: Cannot reach remote IP $RemoteIpAddress" -ForegroundColor Red
        return          
    }
    elseif ($OutputLevel -gt 0)
    {
        Write-Host "VERBOSE: Remote IP $RemoteIpAddress is reachable."
    }
}
else
{
    Write-Host "ERROR: Remote IP address was not provided."    
}

if ($OutputLevel -gt 0)
{
    Write-Host "VERBOSE: Disabling RDMA on adapters that are not part of this test. RDMA will be enabled on them later."
}
$adapters = Get-NetAdapterRdma 
$InstanceIds = $rdmaAdapters.InstanceID;

$adaptersToEnableRdma = @()
foreach ($adapter in $adapters)
{
    if ($adapter.Enabled -eq $true)
    {
        if (($adapter.InstanceID -notin $InstanceIds) -and 
		($adapter.InstanceID -ne $rdmaAdapter.InstanceID) -and
		($adapter.InstanceID -ne $VFAdapter.InstanceID))
        {
            $adaptersToEnableRdma += $adapter
            Disable-NetAdapterRdma -Name $adapter.Name
            if ($OutputLevel -eq 2)
            {
                Write-Host "DEBUG: RDMA disabled on Adapter " $adapter.Name
            }
        } 
        elseif ($OutputLevel -eq 2)
	{
            Write-Host "DEBUG: RDMA not disabled on Adapter " $adapter.Name
	}
    }
}

if ($OutputLevel -ne 0)
{
    Write-Host "VERBOSE: Testing RDMA traffic. Traffic will be sent in a background job. Job details:"
}

# PseudoRandomize the target file name so two copies of this script can execute at the same time against the same destination
$TargetFileName = "\\$RemoteIpAddress\C$\testfile$IfIndex.dat"
if ($OutputLevel -eq 2)
{
    Write-Host "DEBUG: TargetFileName is $TargetFileName"
}

$ScriptBlock = {
    param($RemoteIpAddress, $PathToDiskspd, $TargetFileName) 
    cd $PathToDiskspd
    .\diskspd.exe -b4K -c10G -t4 -o16 -d100000 -L -Sr -d30 $TargetFileName
}
      
$thisJob = Start-Job $ScriptBlock -ArgumentList $RemoteIpAddress,$PathToDiskspd,$TargetFileName
$RdmaTrafficDetected = $false
# Check Perfmon counters while the job is running
While ((Get-Job -id $($thisJob).Id).state -eq "Running")
{
    $written = Get-Counter -Counter "\SMB Direct Connection(_Total)\Bytes RDMA Written/sec" -ErrorAction Ignore
    $sent = Get-Counter -Counter "\SMB Direct Connection(_Total)\Bytes Sent/sec" -ErrorAction Ignore
    if ($written -ne $null)
    {
        $RdmaWriteBytesPerSecond = [uint64]($written.Readings.split(":")[1])
        if ($RdmaWriteBytesPerSecond -gt 0)
        {
            $RdmaTrafficDetected = $true
        }
        if ($OutputLevel -gt 0)
        {
            Write-Host "VERBOSE:" $RdmaWriteBytesPerSecond "RDMA bytes written per second"
        }
    } 
    if ($sent -ne $null)
    {
        $RdmaWriteBytesPerSecond = [uint64]($sent.Readings.split(":")[1])
        if ($RdmaWriteBytesPerSecond -gt 0)
        {
            $RdmaTrafficDetected = $true
        }
        if ($OutputLevel -gt 0)
        {
            Write-Host "VERBOSE:" $RdmaWriteBytesPerSecond "RDMA bytes sent per second"
        }            
    } 
}

del $TargetFileName

if ($OutputLevel -gt 0)
{
    Write-Host "VERBOSE: Enabling RDMA on adapters that are not part of this test. RDMA was disabled on them prior to sending RDMA traffic."
}

foreach ($adapter in $adaptersToEnableRdma)
{
    Enable-NetAdapterRdma -Name $adapter.Name
    if ($OutputLevel -eq 2)
    {
        Write-Host "DEBUG: RDMA enabled on Adapter " $adapter.Name
    }
}

if($NDKPingReady -ne 'No')
{
    Write-Host "Starting NDKPing test:"
    $localip = get-netipconfiguration -ifindex $IfIndex | select IPv4Address
    $localip = $localip.ipv4address.ipaddress

    $ipWithPort = $RemoteIpAddress + ":" + $port

    $codeblock = {
        param($ipWithPort, $RemoteIpAddress, $NDKPingReady, $NDKPingPath)

        $remoteif = get-netipaddress | where-object{($_.ipv4address -eq $RemoteIpAddress)}
        $remoteif = $remoteif.Interfaceindex

        if($NDKPingReady -eq 'Not Native')
        {
            if(-not (get-service 'NDKPing' -ErrorAction SilentlyContinue))
            {
                cmd /c "sc create NDKPing type=kernel binpath=$NDKPingPath\NDKPing.sys"
            }
            cmd /c "$NDKPingPath\NDKPing.exe -S -ServerAddr $ipWithPort -ServerIf $remoteif -TestType rping -W 5"

        } else {
            NDKPing -S -ServerAddr $ipWithPort -ServerIf $remoteif -TestType rping -W 10
        }
    }
    $session = New-PSSession -ComputerName $RemoteName

    if($NDKPingReady = 'Not Native')
    {
        #Assuming that C: exists, an assumption aready made by previous test
        $remotePath = ("\\$RemoteName\C$\{0}" -f $NDKPingPath.Substring(3, $NDKPingPath.Length-3))

        #Create the NDKPing directory on the remote path in case it isn't there
        New-Item -ItemType Directory -Path $remotePath -Force -ErrorAction SilentlyContinue

        Copy-Item "$NDKPingPath\NDKPing.sys" -Destination $remotePath -ErrorAction SilentlyContinue
        Copy-Item "$NDKPingPath\NDKPing.exe" -Destination $remotePath -ErrorAction SilentlyContinue
    }

    $output = invoke-command -asjob -session $session -scriptblock $codeblock -ArgumentList $ipWithPort, $RemoteIpAddress, $NDKPingReady, $NDKPingPath

    $retries = 40 #equivalent to ~20 seconds with 500 ms wait
    $result = receive-job $output 2>&1
    while(-not ($result -like '*NDKPing Server starts test*') -and $retries -gt 0)
    {
        $result = receive-job $output 2>&1
        $retries -= 1
        start-sleep -Milliseconds 500
        write-host "Waiting for remote to create server..."
    }

    if($retries -eq 0)
    {
        write-host "Timed out waiting for remote to create server"
    }

    if($NDKPingReady -eq 'Not Native')
    {
        cmd /c "$NDKPingPath\NDKPing.exe -C -ServerAddr $ipWithPort -ClientAddr $localip -ClientIf $IfIndex -TestType rping -LogFilename $LogFileName"
    } else {
        NDKPing -C -ServerAddr $ipWithPort -ClientAddr $localip -ClientIf $IfIndex -TestType rping -LogFilename $LogFileName

    }
}
else
{
    Write-Host "VERBOSE: skipping NDKPing since it's not supported"
    if($padapter.InterfaceDescription -like '*QLogic*')
    {
        Write-Host 'Disabled for QLogic'
    }
}

if(($NDKPingReady -eq 'No' -or (Test-Path $LogFileName) -eq $true) -and $RdmaTrafficDetected)
{
     #All success conditions must be met for this string to print since dependencies match against it to determine success.
     Write-Host "SUCCESS: RDMA traffic test SUCCESSFUL: RDMA traffic was sent to" $RemoteIpAddress -ForegroundColor Green
}
else
{
    if((Test-Path $LogFileName) -eq $false -and $NDKPingReady -ne "No")
    {
        Write-Host "NDKPing failed" -ForegroundColor Yellow
    }
    Write-Host "ERROR: RDMA traffic test FAILED: Please check " -ForegroundColor Yellow
    Write-Host "ERROR: a) physical switch port configuration for Priorty Flow Control." -ForegroundColor Yellow
    Write-Host "ERROR: b) job owner has write permission at " $RemoteIpAddress "\C$" -ForegroundColor Yellow
}