# AzurermVmRevertToSnapshot
Revert an Azure VM to the specified snapshot OS Disk

Steps:
1. Get the orginal VM details
2. Get the snapshot details
3. Remove the original VM
4. Create a new OS managed disk from the specified snapshot - with the same configuration than the original OS disk (storage size, type)
5. Create a new VM with the new managed disk and apply all the parameters of the original VM (network cards, data disks, availability sets, tags, size, name)
5. Delete the original OS managed disk