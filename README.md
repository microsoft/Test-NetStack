[![Build status](https://ci.appveyor.com/api/projects/status/28dr5irvwqc34ftf?svg=true)](https://ci.appveyor.com/project/MSFTCoreNet/Test-NetStack)
[![downloads](https://img.shields.io/powershellgallery/dt/Test-NetStack.svg?label=downloads)](https://www.powershellgallery.com/packages/Test-NetStack)

# Test-NetStack: A network integration testing tool

## Synopsis

Test-NetStack is a PowerShell-based testing tool that performs ICMP, TCP, and RDMA traffic testing of networks.

leverages stress-testing utilities to identify potential network (fabric and host) instability.

Specifically, Test-NetStack can help you test native, synthetic, and hardware offloaded (RDMA) data paths for issues with:

- Connectivity
- Packet fragmention
- Low throughput
- Congestion

## Test Details

Test-NetStack first performs connectivity mapping across a cluster, specific nodes, or IP targets then tests:

    - Stage1: ICMP Connectivity, Reliability, and PMTUD
    - Stage2: TCP Stress 1:1
    - Stage3: RDMA Connectivity
    - Stage4: RDMA Stress 1:1
    - Stage5: RDMA Stress N:1
    - Stage6: RDMA Stress N:N

For more information, run:

```PowerShell
help Test-NetStack
```

## Install the Tool

```PowerShell
Install-Module Test-NetStack
```

### Run the Tool

```PowerShell
$NetStackResults = Test-NetStack

$NetStackResults = Test-Netstack -Nodes 'Node1', 'Node2', 'NodeN'

$NetStackResults = Test-Netstack -IPTarget '192.168.1.1', '192.168.1.2', '192.168.1.3', '192.168.1.4'
```

### Testable vs Disqualified Networks

Test-NetStack will identify networks that can and cannot be tested. To review the Test-NetStack networks that will be tested, use:

```PowerShell
$NetStack.TestableNetworks
```

To review the Test-NetStack networks that cannot be tested.

```PowerShell
$NetStack.DisqualifiedNetworks
```

###

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
