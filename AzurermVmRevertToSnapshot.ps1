<#
 .SYNOPSIS
    Delete the VM and recreate the VM from Snapshot

 .DESCRIPTION
    Delete the VM and recreate the VM from Snapshot

 .PARAMETER subscriptionId
    The subscription id where the template will be deployed.
    To retrieve souscription id :
        Login-AzureRmAccount
        Get-AzureRmSubscription

 .PARAMETER resourceGroupName
    The resource group where to deploy.

 .PARAMETER resourceGroupLocation
    A resource group location.

 .PARAMETER KeepAzureRMProfile
    Avoid to authenticate each time. Keep AzureRM Profile file in the current folder. It will be not removed at the end of the script and avoid the authenticate again

 .PARAMETER VMName
    Name of the VM to restore

 .PARAMETER SnapshotName
    Name of the snapshot to use to restore the VM

 .EXAMPLE
    .\AzurermVmRevertToSnapshot.ps1 -subscriptionId mysubidhere -resourceGroupName ECMS-HUB-TEST -resourceGroupLocation westeurope -KeepAzureRMProfile -VmName test01 -SnapshotName test01-snap1
#>


param(
 [Parameter(Mandatory=$True)]
 [string]
 $subscriptionId,

 [Parameter(Mandatory=$True)]
 [string]
 $resourceGroupName,

 [Parameter(Mandatory=$True)]
 $resourceGroupLocation,

 [Parameter(Mandatory=$True)]
 $VMName,

 [Parameter(Mandatory=$True)]
 $SnapshotName,

 [SWITCH]$KeepAzureRMProfile
)

#Variables
$ScriptPath = Get-Location
$credentialsPath = "$ScriptPath\azureprofile.json"

$RandomNumber = Get-Random -min 10000000000 -Maximum 99999999999999
$OSDiskName = ("$VMName-OSDisk-$RandomNumber")

#******************************************************************************
# Script body
# Execution begins here
#******************************************************************************
import-module AzureRM

# sign in
Write-Host "Logging in...";
if (!(Test-Path $credentialsPath)){
    Login-AzureRmAccount;
    # select subscription
    Get-AzureRmSubscription
    Write-Host "Selecting subscription '$subscriptionId'";
    Select-AzureRmSubscription -SubscriptionID $subscriptionId;
    Save-AzureRmProfile -Path $credentialsPath -Force
}
else{
    Select-AzureRmProfile -Path $credentialsPath
}

#Get VM Details
$OriginalVM = get-azurermvm -ResourceGroupName $ResourceGroupName -Name $vmName -ErrorAction SilentlyContinue
if (!$OriginalVM)
    {
        write-host "No VM named $VMName"
        break
    }

#Get Snapshot
$Snapshot = Get-AzureRmSnapshot -ResourceGroupName $ResourceGroupName -SnapshotName $snapshotName -ErrorAction SilentlyContinue
if (!$Snapshot)
    {
        write-host "No Snapshot named $SnapshotName"
        break
    }

#Remove the original VM
Remove-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $vmName -Force

#Create new managed disk from Snapshot
$diskConfig = New-AzureRmDiskConfig -SkuName $OriginalVM.StorageProfile.OsDisk.ManagedDisk.StorageAccountType -Location $resourceGroupLocation -CreateOption Copy -SourceResourceId $snapshot.Id -DiskSizeGB $Snapshot.DiskSizeGB
$Disk = New-AzureRmDisk -Disk $diskConfig -ResourceGroupName $resourceGroupName -DiskName $OSDiskName

#Initialize virtual machine configuration
if($OriginalVM.AvailabilitySetReference.Id -and $OriginalVM.Tags)
    {
        $VirtualMachine = New-AzureRmVMConfig -VMName $OriginalVM.Name -VMSize $OriginalVM.HardwareProfile.VmSize -AvailabilitySetId $OriginalVM.AvailabilitySetReference.Id -Tags $OriginalVM.Tags
    }
else 
    {
        if($OriginalVM.AvailabilitySetReference.Id)
            {
                $VirtualMachine = New-AzureRmVMConfig -VMName $OriginalVM.Name -VMSize $OriginalVM.HardwareProfile.VmSize -AvailabilitySetId $OriginalVM.AvailabilitySetReference.Id
            }
        elseif($OriginalVM.Tags)
            {
                $VirtualMachine = New-AzureRmVMConfig -VMName $OriginalVM.Name -VMSize $OriginalVM.HardwareProfile.VmSize -Tags $OriginalVM.Tags
            }
        else
            {
                $VirtualMachine = New-AzureRmVMConfig -VMName $OriginalVM.Name -VMSize $OriginalVM.HardwareProfile.VmSize
            }
    }

#Use the Managed Disk Resource Id to attach it to the virtual machine.
$VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -ManagedDiskId $disk.Id -CreateOption Attach -Windows

#Add NIC(s)
foreach ($nic in $OriginalVM.NetworkProfile.NetworkInterfaces) {
    Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $nic.Id
}

#Create the virtual machine with Managed Disk
New-AzureRmVM -VM $VirtualMachine -ResourceGroupName $resourceGroupName -Location $OriginalVM.Location

#Delete old managed disk
Remove-AzureRmDisk -ResourceGroupName $resourceGroupName -DiskName $OriginalVM.StorageProfile.OsDisk.name -Force

write-host ("Old disk removed" + $OriginalVM.StorageProfile.OsDisk.name) -ForegroundColor Gray
write-host "VM $VMName successfully restored from $SnapshotName" -ForegroundColor Green

#Remove the AzureRM Profile file
if(!$KeepAzureRMProfile){
    write-host "deleting the AzureRMProfile file"
    Remove-Item $credentialsPath
}