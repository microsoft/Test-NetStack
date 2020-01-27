
# Test-NetStack: A network integration testing tool

## Synopsis

Test-NetStack is a powershell-based testing tool that leverages stress-testing utilities to identify potential network (fabric and host) instability.

Specifically, Test-NetStack can help you test native, synthetic, and hardware offloaded (RDMA) data paths for issues with:

- Connectivity
- Packet fragmention
- Low throughput
- Congestion

This tool will be updated over time to provide enhanced recommendations

## Description

Network diagnosis poses a challenge for Windows Administrators as there are a number of configuration points on (e.g. Windows) and off-box (e.g. physical network infrastructure). This can be compounded by separate data paths (e.g. RDMA vs synthetic) and the fact that Windows Administrators do not always control the physical network.

In addition, traditional testing has relied on tools that leverage upper-layer protocols (e.g. DiskSpd and SMB) to test and validate functionality which adds additional complexity to testing as more variables are added to the test.

Using this tool along with other Network testing and diagnosis tools such as PacketMon and Validate-DCB, Software-defined Data Center customers (e.g. Azure Stack HCI including SDN and S2D) can isolate complex network failure scenarios.

## Test Details

Test-NetStack first runs networking tools (e.g. ping, CTSTraffic) with the intent of confirming upper-layer infrastructure for native or synthetic traffic. 

Given a set or cluster of machines, Test-NetStack will identify the NICs that are on the same subnet and vlan. These networking tools are then run across every permutation of NIC pairs within each subnet and vlan in the following order by Test-NetStack: 

- ping (checking for connectivity)
- ping -f -l (checking for fragmentation)
- CTS Traffic (stressing 1:N and many:1)

If the above tests pass, we will attempt to perform the same validation for RDMA. To do this, Test-NetStack runs the following network tools across every permutation of NIC pairs within each subnet and vlan: 
- NDK Ping (testing RDMA connectivity)
- NDK Perf (stressing 1:1 and congesting with many:1)

## Run the tool

In order to run Test-NetStack, a few short steps are necessary to setup and enable each individual stage within the tool itself. A script has been provided that completes most of the setup, however, there are still a number of required manual steps. 

First and foremost, it is necessary to clone this repository to a domain-joined host's C:\ drive. Specifically, clone the repo to a new directory called "Test-NetStack." The setup script depends on the repository's location being in C:\Test-NetStack. 

Once the repository is cloned, navigate to .\Test-NetStack\scripts and run setup.ps1. At the top of setup.ps1, it is necessary to enter the machine names that you plan to run Test-NetStack amongst. Specifically, edit the $MachineList variable to be a series of machine names in quotations ("") separated by commas.
`Ex. "Machine One", "Machine Two", "Machine Three" etc.` 
The setup script does the following:
- Creates a new parent directory on each machine called C:\Test-NetStack. It then creates subdirectories for NDK Perf and CTS-Traffic. These subdirectories are C:\Test-NetStack\tools\NDK-Perf and C:\Test-NetStack\tools\CTS-Traffic. 
- Next, the script copies over the relevant .sys and .exe files for NDK Perf and CTS-Traffic to their respective directories. 
- After copying over the files, setup.ps1 runs `sc create NDKPerf type=kernel binpath=C:\Test-NetStack\tools\NDKPerf.sys` to allow the new driver to be run on each remote system. 
- Finally, a new Firewall rule is created to allow inbound CTS-Traffic communcication on each remote system. 

After running setup.ps1, run the Test-NetStack.unit.test.ps1 or Assert-RDMA.ps1 to run the full suite of Test-NetStack pester tests. 


(below are notes, disregard)

- Machine Set - Preferably within Cluster
    - If no cluster present, user must go into Test-NetStack.ps1 script and edit 'machine list.' This will be an editable in command in the future
- CTS Traffic must be allowed through the firewall on all machhines
    - Including script file to copy over from repo to each machine in set (given user enters in machines)
    - must create c:\cmd\tools\CTS-Traffic on each machine - Script and Test-NetStack looks for c:\cmd\tools\CTS-Traffic on each machine for exe
    - .exe and .sys files currently packaged in with repo in \tools\CTS-Traffic
    - Must allow CTS-Traffic through machine firewalls 
- NDK Perf must be installed on all machines and the machines configured properly
    - Including script file to copy over from repo to each machine in set (given user enters in machines)
    - Must create c:\perf\ and c:\perf\driver on each machine - Script and Test-NetStack looks for the ndkperf .exe and .sys in the following directory on each machine C:\perf\
    - Run sc create NDKPerf type=kernel binpath=C:\perf\NDKPerf.sys to allow driver **assumes folder c:\perf**
    - This will not be hard-coded in the long run 
    - .exe and .sys files currently packaged in with repo in \tools\NDKPerf
- Once the above is complete, user can run ./Test-NetStack

## Test-NetStack Stage 0: Network Discovery
Before testing the network infrastructure, Test-NetStack attempts to 'construct' a local image of the network by querying information about each machine's NICs. This process entails collecting information on each NICs subnet, VLAN, Ip Address, RDMA Capability, etc. A copy of this local image is output in the Test-NetStack-Network-Info text file during a run of Test-NetStack. This construct is used for the remainder of the script to construct networking tool queries and track success/failure information. 

## Test-NetStack Stage 1 & 2: Ping
Test-NetStack executes ping in two different stages amongst NIC pairs within the same Subnet and VLAN. The first stage's intent is to verify basic upper-layer connectivity. A simple ping is sent and then checked for success. 
The second stage of Test-NetStack uses ping with the -l and -f commands enabled. The -l command dictates the size of the send buffer and -f represents the "Don't Fragment" flag. In short, the second stage attempts to find the Maximum Transmission Unit (MTU) via ping. 

## Test-NetStack Stage 3: CTS Traffic
Test-NetStack executes the network performance and reliability tool -- CTS Traffic -- to stress the synthetic connection amongst NIC pairs within the same Subnet and VLAN. This stage's intent is to verify that a TCP connection over, for example, two 40 Gbs NICs can reach a reasonable percentage (50%) of the configured throughput. 

## Test-NetStack Stage 4: NDK Ping 
Test-NetStack executes its first RDMA-based network tool -- NDK Ping -- to verify that a basic connection between NIC pairs within the same subnet and VLAN can be established and tested with RDMA traffic. Here, the Network Direct Kernel Provider Interface (NDKPI) is used to send a small message (analogous to a ping) via the RDMA protocol. NDK Ping is an in-box driver that can be natively run from the command line. 

## Test-NetStack Stage 5 & 6: NDK Perf
The final two stages of Test-NetStack invoke another RDMA-based network tool called NDK Perf. This driver attempts to establish a connection between NIC pairs within the same subnet and VLAN and consequently stress the connection to its limit with RDMA traffic. Stage 5 attempts to congest the connection between only two nodes -- one client and one server. Stage 6, however, attempts a many-to-one stress test, where multiple client NICs output maximum throughput to a single server NIC. The intent of these two stages is to isolate and identify software- or hardware-based rdma configuration issues. Physical wire bottle-necks, for example, can be better identified via RDMA stress than more traditional upper-layer stress. 

# Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
