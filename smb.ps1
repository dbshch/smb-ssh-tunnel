# Usage: Start Powershell with Admin priviledge, execute:
# ./smb.ps1 "<user>@<ip> -p <Port> -i <private_key>"

$Arguments = $args[0] + " -L 10.255.255.1:44445:127.0.0.1:445"

function Add-TaskScheduler
{
    param
    (
        [Parameter(
            Mandatory = $true,
            Position = 0)]
        [string]
        $Arguments
    )
    Import-Module ScheduledTasks
    $A = New-ScheduledTaskAction -Execute "ssh.exe" -Argument $Arguments
    $T = New-ScheduledTaskTrigger -AtLogon
    $P = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType S4U
    $S = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -AllowStartIfOnBatteries -Hidden -DontStopIfGoingOnBatteries -ExecutionTimeLimit '00:00:00' # -ExecutionTimeLimit ([timespan]::MaxValue)
    $D = New-ScheduledTask -Action $A -Principal $P -Trigger $T -Settings $S
    Register-ScheduledTask -TaskName "sshtunnel" -Trigger $T -Action $A -Settings $S -Principal $P
}

<#
.SYNOPSIS
   Install a new Loopback Network Adapter.
.DESCRIPTION
   Uses Chocolatey to download the DevCon (Windows Device Console) package and
   uses it to install a new Loopback Network Adapter with the name specified.
   The Loopback Adapter will need to be configured like any other adapter (e.g. configure IP and DNS)
.PARAMETER Name
   The name of the Loopback Adapter to create.
.PARAMETER Force
   Force the install of Chocolatey and the Devcon.portable pacakge if not already installed, without confirming with the user.
.EXAMPLE
    $Adapter = New-LoopbackAdapter -Name 'MyNewLoopback'
   Creates a new Loopback Adapter called MyNewLoopback.
.OUTPUTS
   Returns the newly created Loopback Adapter.
.COMPONENT
   LoopbackAdapter
#>
function New-LoopbackAdapter
{
    [OutputType([Microsoft.Management.Infrastructure.CimInstance])]
    [CmdLetBinding()]
    param
    (
        [Parameter(
            Mandatory=$true,
            Position=0)]
        [string]
        $Name,
        
        [switch]
        $Force
    )
    $null = $PSBoundParameters.Remove('Name')

    # Check for the existing Loopback Adapter
    $Adapter = Get-NetAdapter `
        -Name $Name `
        -ErrorAction SilentlyContinue

    # Is the loopback adapter installed?
    if ($Adapter)
    {
        Throw "A Network Adapter $Name is already installed."
    } # if

    # Make sure DevCon is installed.
    $DevConExe = (Install-Devcon @PSBoundParameters).Name

    # Get a list of existing Loopback adapters
    # This will be used to figure out which adapter was just added
    $ExistingAdapters = (Get-LoopbackAdapter).PnPDeviceID

    # Use Devcon.exe to install the Microsoft Loopback adapter
    # Requires local Admin privs.
    $null = & $DevConExe @('install',"$($ENV:SystemRoot)\inf\netloop.inf",'*MSLOOP')

    # Find the newly added Loopback Adapter
    $Adapter = Get-NetAdapter `
        | Where-Object {
            ($_.PnPDeviceID -notin $ExistingAdapters ) -and `
            ($_.DriverDescription -eq 'Microsoft KM-TEST Loopback Adapter')
        }
    if (-not $Adapter)
    {
        Throw "The new Loopback Adapter was not found."
    } # if

    # Rename the new Loopback adapter
    $Adapter | Rename-NetAdapter `
        -NewName $Name `
        -ErrorAction Stop
    Disable-NetAdapterBinding -Name $Name -AllBindings
    Enable-NetAdapterBinding -Name $Name -DisplayName "Inter* (TCP/IPv4)"
    New-NetIPAddress -InterfaceAlias $Name -IPAddress 10.255.255.1
    Set-NetIPInterface `
        -InterfaceAlias $Name `
        -InterfaceMetric 9999 `
        -ErrorAction Stop

    # Wait till IP address binding has registered in the CIM subsystem.
    # if after 30 seconds it has not been registered then throw an exception.
    [Boolean] $AdapterBindingReady = $false
    [DateTime] $StartTime = Get-Date
    while (-not $AdapterBindingReady `
        -and (((Get-Date) - $StartTime).TotalSeconds) -lt 30)
    {
        try
        {
            $IPAddress = Get-CimInstance `
                -ClassName MSFT_NetIPAddress `
                -Namespace ROOT/StandardCimv2 `
                -Filter "((InterfaceAlias = '$Name') AND (AddressFamily = 2))" `
                -ErrorAction Stop
            if ($IPAddress)
            {
                $AdapterBindingReady = $true
            } # if
            Start-Sleep -Seconds 1
        }
        catch
        {
        }
    } # while

    if (-not $IPAddress)
    {
        Throw "The New Loopback Adapter was not found in the CIM subsystem."
    }

    # Pull the newly named adapter (to be safe)
    $Adapter = Get-NetAdapter `
        -Name $Name `
        -ErrorAction Stop

    Return $Adapter
} # function New-LoopbackAdapter


<#
.SYNOPSIS
   Returns a specified Loopback Network Adapter or all Loopback Adapters.
.DESCRIPTION
   This function will return either the Loopback Adapter specified in the $Name parameter
   or all Loopback Adapters. It will only return adapters that use the Microsoft KM-TEST Loopback Adapter
   driver.

   This function does not use Chocolatey or the DevCon (Device Console) application, so does not
   require administrator access.
.PARAMETER Name
   The name of the Loopback Adapter to return. If not specified will return all Loopback Adapters.
.EXAMPLE
    $Adapter = Get-LoopbackAdapter -Name 'MyNewLoopback'
   Returns the Loopback Adapter called MyNewLoopback. If this Loopback Adapter does not exist or does not use the
   Microsoft KM-TEST Loopback Adapter driver then an exception will be thrown.
.OUTPUTS
   Returns a specific Loopback Adapter or all Loopback adapters.
.COMPONENT
   LoopbackAdapter
#>
function Get-LoopbackAdapter
{
    [OutputType([Microsoft.Management.Infrastructure.CimInstance[]])]
    [CmdLetBinding()]
    param
    (
        [Parameter(
            Position=0)]
        [string]
        $Name
    )
    # Check for the existing Loopback Adapter
    if ($Name)
    {
        $Adapter = Get-NetAdapter `
            -Name $Name `
            -ErrorAction Stop
        if ($Adapter.DriverDescription -ne 'Microsoft KM-TEST Loopback Adapter')
        {
            Throw "The Network Adapter $Name exists but it is not a Microsoft KM-TEST Loopback Adapter."
        } # if
        return $Adapter
    }
    else
    {
        Get-NetAdapter | Where-Object -Property DriverDescription -eq 'Microsoft KM-TEST Loopback Adapter'
    } # if
} # function Get-LoopbackAdapter


<#
.SYNOPSIS
   Uninstall an existing Loopback Network Adapter.
.DESCRIPTION
   Uses Chocolatey to download the DevCon (Windows Device Console) package and
   uses it to uninstall a new Loopback Network Adapter with the name specified.
.PARAMETER Name
   The name of the Loopback Adapter to uninstall.
.PARAMETER Force
   Force the install of Chocolatey and the Devcon.portable pacakge if not already installed, without confirming with the user.
.EXAMPLE
    Remove-LoopbackAdapter -Name 'MyNewLoopback'
   Removes an existing Loopback Adapter called MyNewLoopback.
.OUTPUTS
   None
.COMPONENT
   LoopbackAdapter
#>
function Remove-LoopbackAdapter
{
    [CmdLetBinding()]
    param
    (
        [Parameter(
            Mandatory=$true,
            Position=0)]
        [string]
        $Name,
        
        [switch]
        $Force
    )
    $null = $PSBoundParameters.Remove('Name')

    # Check for the existing Loopback Adapter
    $Adapter = Get-NetAdapter `
        -Name $Name `
        -ErrorAction SilentlyContinue

    # Is the loopback adapter installed?
    if (! $Adapter)
    {
        # Adapter doesn't exist
        Throw "Loopback Adapter $Name is not found."
    }

    # Is the adapter Loopback adapter?
    if ($Adapter.DriverDescription -ne 'Microsoft KM-TEST Loopback Adapter')
    {
        # Not a loopback adapter - don't uninstall this!
        Throw "Network Adapter $Name is not a Microsoft KM-TEST Loopback Adapter."
    } # if

    # Make sure DevCon is installed.
    $DevConExe = (Install-Devcon @PSBoundParameters).Name

    # Use Devcon.exe to remove the Microsoft Loopback adapter using the PnPDeviceID.
    # Requires local Admin privs.
    $null = & $DevConExe @('remove',"@$($Adapter.PnPDeviceID)")
} # function Remove-LoopbackAdapter


# Support functions - not exposed

<#
.SYNOPSIS
   Install the DevCon.Portable (Windows Device Console) pacakge using Chocolatey.
.DESCRIPTION
   Installs Chocolatey from the internet if it is not installed, then uses
   it to download the DevCon.Portable (Windows Device Console) package.
   The devcon.portable Chocolatey package can be found here and installed manually
   if no internet connection is available:
   https://chocolatey.org/packages/devcon.portable/
   
   Chocolatey will remain installed after this function is called.
.PARAMETER Force
   Force the install of Chocolatey and the Devcon.portable pacakge if not already installed, without confirming with the user.
.EXAMPLE
    Install-Devcon
.OUTPUTS
   The fileinfo object containing the appropriate DevCon*.exe application that was installed for this architecture.
.COMPONENT
   LoopbackAdapter
#>
function Install-Devcon
{
    [OutputType([System.IO.FileInfo])]
    [CmdLetBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High')]
    param
    (
        [Switch]
        $Force
    )
    Install-Chocolatey @PSBoundParameters

    # Check DevCon installed - if not, install it.
    $DevConInstalled = ((Test-Path -Path "$ENV:ProgramData\Chocolatey\Lib\devcon.portable\Devcon32.exe") `
        -and (Test-Path -Path "$ENV:ProgramData\Chocolatey\Lib\devcon.portable\Devcon64.exe"))
    if (! $DevConInstalled)
    {
        try
        {
            # This will download and install DevCon.exe
            # It will also be automatically placed into the path
            If ($Force -or $PSCmdlet.ShouldProcess('Download and install DevCon (Windows Device Console) using Chocolatey'))
            {
                $null = & choco install -r -y devcon.portable
            }
            else
            {
                Throw 'DevCon (Windows Device Console) was not installed because user declined.'
            }
        }
        catch
        {
            Throw 'An error occured installing DevCon (Windows Device Console) using Chocolatey.'
        }
    }
    if ($ENV:PROCESSOR_ARCHITECTURE -like '*64')
    {
        Get-ChildItem "$ENV:ProgramData\Chocolatey\Lib\devcon.portable\Devcon64.exe"    
    }
    else
    {
        Get-ChildItem "$ENV:ProgramData\Chocolatey\Lib\devcon.portable\Devcon32.exe"    
    }
}


<#
.SYNOPSIS
   Install the DevCon.Portable (Windows Device Console) pacakge using Chocolatey.
.DESCRIPTION
   Installs Chocolatey from the internet if it is not installed, then uses
   it to uninstall the DevCon.Portable (Windows Device Console) package.
   
   Chocolatey will remain installed after this function is called.
.PARAMETER Force
   Force the uninstall of the devcon.portable pacakge if it is installed, without confirming with the user.
.EXAMPLE
    Uninstall-Devcon
.OUTPUTS
   None.
.COMPONENT
   LoopbackAdapter
#>
function Uninstall-Devcon
{
    [CmdLetBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High')]
    param
    (
        [Switch]
        $Force
    )
    Install-Chocolatey @PSBoundParameters
    
    try
    {
        # This will download and install DevCon.exe
        # It will also be automatically placed into the path
        if ($Force -or $PSCmdlet.ShouldProcess('Uninstall DevCon (Windows Device Console) using Chocolatey'))
        {
            $null = & choco uninstall -r -y devcon.portable
        }
        else
        {
            Throw 'DevCon (Windows Device Console) was not uninstalled because user declined.'    
        }
    }
    catch
    {
        Throw 'An error occured uninstalling DevCon (Windows Device Console) using Chocolatey.'
    }
}


<#
.SYNOPSIS
   Install Chocolatey.
.DESCRIPTION
   Installs Chocolatey from the internet if it is not installed.d.
.PARAMETER Force
   Force the install of Chocolatey, without confirming with the user.
.EXAMPLE
    Install-Chocolatey
.OUTPUTS
   None
.COMPONENT
   LoopbackAdapter
#>
function Install-Chocolatey
{
    [CmdLetBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High')]
    param
    (
        [Switch]
        $Force
    )
    # Check chocolatey is installed - if not, install it
    $ChocolateyInstalled = Test-Path -Path (Join-Path -Path $ENV:ProgramData -ChildPath 'Chocolatey\Choco.exe')
    if (! $ChocolateyInstalled)
    {
        If ($Force -or $PSCmdlet.ShouldProcess('Download and install Chocolatey'))
        {
            $null = Invoke-Expression ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))    
        }
        else
        {
            Throw 'Chocolatey could not be installed because user declined installation.'
        }
    }
}

New-LoopbackAdapter -Name 'Loopback'
Get-WmiObject win32_networkadapter -Property guid, Name | Where-Object { $_.Name -like 'Microsoft KM-TEST Loopback Adapter*' } | Select-Object -ExpandProperty GUID  | foreach { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces\Tcpip_$_" -name NetBiosOptions -value 2 }

sc.exe config lanmanserver start= delayed-auto
sc.exe config iphlpsvc start= auto
sc.exe config lanmanserver depend= SamSS/Srv2/iphlpsvc
netsh interface portproxy add v4tov4 listenaddress=10.255.255.1 listenport=445 connectaddress=10.255.255.1 connectport=44445
Add-TaskScheduler $Arguments
Write-Host "Reboot to take effect"
# Test after reboot
# netstat -an | find ":445 "
# netsh interface portproxy show v4tov4
