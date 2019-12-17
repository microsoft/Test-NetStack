
# Test-RDMA -- A Network Congestion Tool

## Introduction
Test-RDMA is a pester-integrated powershell tool that attempts to stress and strain the network fabric in order to isolate RDMA issues and failures. RDMA-based infrastructure is often difficult to properly configure and validate. Enterprise customers working within the realm of Software Defined Data Centers (SDDC), Software Defined Networking (SDN), and Storage Spaces Direct (S2D) find themselves without a tool that may properly allow them to identify network failures -- especially when it comes to the RDMA protocol. When networking failures occur, they can be sourced in one hundred different software/firmware/hardware problems. Thus, we have built a tool that attempts to filter down the networking stack, allowing enterprise customers the ability to hone in on a true RDMA issue by first confirming the more traditional network configurations. 

The tool itself first runs a number of traditional networking tools (e.g. ping) with the intent of confirming upper-layer infrastructure. Given a set or cluster of machines, the Test-RDMA tool identifies the Network Interface Cards (NICs) amongst that set that are on the same subnet and vlan. These traditional networking tools are then run across every permutation of NIC pairs within each subnet and vlan in the following order by Test-RDMA: 
- ping
- CTS Traffic

After running the above tools, we may confirm with some degree of certainty that if there is truly a network failure, then it likely resides within the RDMA-based infrastructure. To confirm this notion, Test-RDMA runs the following RDMA-based network tools across every permutation of NIC pairs within each subnet and vlan: 
- NDK Ping 
- NDK Perf

By running this set of tools across a machine set's network infrastructure, we hope to properly isolate, identify and investigate RDMA-based failures. 

## Setup and Requirements

## Test-RDMA Stage 1 & 2 -- Ping

## Test-RDMA Stage 3 -- CTS Traffic

## Test-RDMA Stage 4 -- NDK Ping 

## Test-RDMA Stage 5 & 6 -- NDK Perf


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
