# windows-update-powercli  
PowerShell script that installs Windows Updates by using [PowerCLI](https://www.vmware.com/support/developer/PowerCLI/) and [VmWare vCenter Server](http://www.vmware.com/products/vcenter-server). 
Target machine should have [PSWindowsUpdates](https://gallery.technet.microsoft.com/scriptcenter/2d191bcd-3308-4edd-9de2-88dff796b0bc) module installed.

##### Example
.\install_windows_updates.ps1 -virtual_machine_name:Windows_2008_r2 -VMGuestUsername:Administrator -VMGuestPassword:123456 -VIServerName:vServer.yourcompany.com -VIServerUsername:Administrator -VIServerPassword:123456
