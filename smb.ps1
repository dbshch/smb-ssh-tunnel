# Usage: Start Powershell with Admin priviledge, execute:
# ./smb.ps1 "<user>@<ip> -p <Port> -i <private_key>"
param (
    [Parameter(Mandatory=$true)][string]$DEST_IP,
    [string]$DEST_PORT,
    [string]$NIC_IP = "10.255.255.1",
    [string]$NIC_NAME = "Loopback"
)

. ./mods.ps1

New-LoopbackAdapter -Name $NIC_NAME -IP $NIC_IP
Get-WmiObject win32_networkadapter -Property guid, Name | Where-Object { $_.Name -like 'Microsoft KM-TEST Loopback Adapter*' } | Select-Object -ExpandProperty GUID  | foreach { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\Tcpip_$_" -name NetBiosOptions -value 2 }

sc.exe config lanmanserver start= delayed-auto
sc.exe config iphlpsvc start= auto
sc.exe config lanmanserver depend= SamSS/Srv2/iphlpsvc
netsh interface portproxy add v4tov4 listenaddress=$NIC_IP listenport=445 connectaddress=$DEST_IP connectport=$DEST_PORT

Write-Host "Reboot to take effect"
Write-Host "Test after reboot:"
Write-Host 'netstat -an | find ":445 "'
Write-Host "netsh interface portproxy show v4tov4"
