# Usage: Start Powershell with Admin priviledge, execute:
# ./smb.ps1 "<user>@<ip> -p <Port> -i <private_key>"
param (
    [Parameter(Mandatory=$true)][string]$SSH_OPT,
    [string]$DEST_IP = "127.0.0.1",
    [string]$NIC_IP = "10.255.255.1",
    [string]$NIC_NAME = "Loopback"
)

. ./mods.ps1
$Arguments = $SSH_OPT + " -L " + $NIC_IP + ":44445" + $DEST_PORT + ":" + $DEST_IP + ":445"

echo $Arguments
New-LoopbackAdapter -Name $NIC_NAME -IP $NIC_IP
Get-WmiObject win32_networkadapter -Property guid, Name | Where-Object { $_.Name -like 'Microsoft KM-TEST Loopback Adapter*' } | Select-Object -ExpandProperty GUID  | foreach { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\Tcpip_$_" -name NetBiosOptions -value 2 }

sc.exe config lanmanserver start= delayed-auto
sc.exe config iphlpsvc start= auto
sc.exe config lanmanserver depend= SamSS/Srv2/iphlpsvc
netsh interface portproxy add v4tov4 listenaddress=$NIC_IP listenport=445 connectaddress=$NIC_IP connectport=44445
Add-TaskScheduler $Arguments

Write-Host "Reboot to take effect"
Write-Host "Test after reboot:"
Write-Host 'netstat -an | find ":445 "'
Write-Host "netsh interface portproxy show v4tov4"
