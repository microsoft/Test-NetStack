# Copy all the local files to all the remote nodes.

# Add prerequisite tester here
        #TODO: Add check, If Stage contains '2', it must contain '1' as it builds on it.


#region Get-Connectivity Prerequisites

<#
Remoting requirements
 - Fail if DNS resolution not available - This is required for remoting without a
 - Ensure remoting works (Test-NetConnection or New-PSSession then dispose) - Don't do in parallel; should not require creds
 #>

#endregion Get-Connectivity Prerequisites

#region Stage1 Prerequisites

#endregion Stage1 Prerequisites

#region Stage2 Prerequisites
    <#
    OS Version test
    NDKPerf Version test

    #>
#endregion Stage2 Prerequisites