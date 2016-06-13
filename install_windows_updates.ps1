 <#
    .SYNOPSIS 
        Installs Windows Updates by using VmWare PowerCli API (https://www.vmware.com/support/developer/PowerCLI/) and PSWindowsUpdate module (https://gallery.technet.microsoft.com/scriptcenter/2d191bcd-3308-4edd-9de2-88dff796b0bc). 
    .NOTES
        The target machine must have PSWindowsUpdate (https://gallery.technet.microsoft.com/scriptcenter/2d191bcd-3308-4edd-9de2-88dff796b0bc) module installed. You can install it by executing "choco install pswindowsupdate -y". 
        See http://chocolatey.org.
    .DESCRIPTION
        This cmdlet connects to $VIServerName and perform Invoke-VMScript on $virtual_machine_name. Before installing the updates it creates a snapshot. 
        If installation was successful(VMWare Tools available) it removes the snapshot. 
    .EXAMPLE
        Install_windows_updates.ps1 -virtual_machine_name "windows_2008" -VMGuestUsername "Administrator" -VMGuestPassword "GuestPassword" -VIServerName "somevServer.YourCompany.com" -VIServerUsername "Administrator" -VIServerPassword "ViServerPassword"
     
  #>
  param (

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$virtual_machine_name = "windows_machine_name_as_in_vserver",

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$VMGuestUsername = "Administrator",

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$VMGuestPassword = "GuestPassword",

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$VIServerName="vserver.YourCompany.com",

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$VIServerUsername = "Administrator",

    [Parameter(Mandatory=$True)]
    [ValidateNotNullOrEmpty()]
    [string]$VIServerPassword = "ServerPassword"

 )

function Wait-For-VM-Tools-Ready($vmToCheck, $timeoutSeconds)
{
    Write-Host "Waiting for VM Tools to be ready..."
    Wait-Tools -VM $vmToCheck -TimeoutSeconds $timeoutSeconds 
}

function Remove-Snapshots($vmname, $snapshotprefix)
{
    Write-Host "Remove snapshots with prefix: " + $snapshotprefix
    $snapshotwildcard = $snapshotprefix+="*"
    $snapshotsToRemove = Get-Snapshot -VM $vmname -Name $snapshotwildcard;
    Foreach ($snapshotToRemove in $snapshotsToRemove) 
    { 
        Write-Host "Removing snapshot: " $snapshotToRemove 
        Remove-Snapshot -Snapshot $snapshotToRemove -Confirm:$False 
    }
}

function Make-New-Snapshot($vmname, $snapshotprefix)
{
    $now = Get-Date -Format "o"
    $snapshot = $snapshotprefix + $now
    Write-Host "Making a new snapshot " + $snapshot
    New-Snapshot -VM $vmname -Name $snapshot
}

function PendingWindowsUpdates($computerName, $credentials)
{
    Write-Host "Check for pending updates on " $computerName
    $pendingUpdates = Invoke-VMScript -ScriptType PowerShell -ScriptText "Get-WUList -NotCategory 'Language packs'" -VM $computerName -GuestCredential $credentials

    Write-Host "remote script returned: " $pendingUpdates -ForegroundColor Gray

    if ($pendingUpdates.ScriptOutput.Contains("is not recognized as the name of a cmdlet"))
    {
        Write-Host "Please make sure that machine " $virtual_machine_name " has PSWindowsUpdate module" -ForegroundColor Yellow
        Write-Host "Before running this script execute: choco install pswindowsupdate -y" -ForegroundColor Yellow
        Write-Host "Exiting with code 1" 
        exit 1
    }

    if ($pendingUpdates.ScriptOutput.Contains("KB") -or $pendingUpdates.Contains("MB") -or $pendingUpdates.Contains("GB") )
    {
        Write-Host "Updates found !!!" -ForegroundColor Green
        return $true
    }
    else
    {
        Write-Host "No updates found." -ForegroundColor Gray
        return $false
    }
}

$ErrorActionPreference="Stop"

trap
{
    Write-Host "Error " -ForegroundColor Red
    Write-Host $_
    Write-Host ""
    Write-Host "Exiting with code 2"
    exit 2
}

Add-PSSnapin VMware.VimAutomation.Core
$VMGuestPasswordSecureString = convertto-securestring $VMGuestPassword -asplaintext -force

Connect-VIServer $VIServerName -User $VIServerUsername -Password $VIServerPassword

$Invocation = (Get-Variable MyInvocation).Value
push-location (Split-Path $Invocation.MyCommand.Path)

$vm = Get-VM $virtual_machine_name
Write-Host "Virtual Machine Power State: " $vm.PowerState 
$virtual_machine_was_powered_on = ($vm.PowerState -eq "PoweredOn")
if (!$virtual_machine_was_powered_on)
{
  Write-Host "Starting the VM " $virtual_machine_name
  Start-VM -VM $virtual_machine_name -Confirm:$false 
}

Wait-For-VM-Tools-Ready $virtual_machine_name 300

$cred = new-object -typename System.Management.Automation.PSCredential -argumentlist $VMGuestUsername, $VMGuestPasswordSecureString
$pendingUpdates = PendingWindowsUpdates $virtual_machine_name $cred
if($pendingUpdates -eq $True)
{    
    Make-New-Snapshot $virtual_machine_name "beforewindowsupdate"

    Write-Host "Running windows update on the VM..."
    Invoke-VMScript -ScriptType PowerShell -ScriptText "Get-WUInstall -Verbose –WindowsUpdate –AcceptAll –AutoReboot" -VM $virtual_machine_name -GuestCredential $cred -Confirm:$False | Out-file -Filepath WindowsUpdateResults.log

    Write-Host "Restarting VM one more time in case Windows Update requires it and for whatever reason the –AutoReboot switch didn’t complete it..." 
    Restart-VMGuest -VM $virtual_machine_name -Confirm:$False
    Start-Sleep -Seconds 60 # give some time for vCenter to initiate shutdown

    Wait-For-VM-Tools-Ready $virtual_machine_name 600

    Write-Host "Machine is ready. Will remove temporary snapshots."
    Remove-Snapshots $virtual_machine_name "beforewindowsupdate"
    Write-Host "Done"
}

if ($virtual_machine_was_powered_on -eq $False)
{
    Write-Host "Virtual Machine was not powered on. Will set machine to powered off state..."
    Shutdown-VMGuest –VM $virtual_machine_name -Confirm:$False

    Start-sleep -s 60
}

pop-location

Write-Host "Done updating the VM " $virtual_machine_name
