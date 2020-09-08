# smb-ssh-tunnel
Connect samba server through ssh tunnel on Windows

In Windows, smb is only supported with port 445, which is commonly blocked by firewalls. Use ssh tunnel to avoid port 445 being blocked.

This Powershell script creates a loopback network adapter and a task scheduler to create a ssh tunnel to connect 10.255.255.1:445 to the samba server, then we can connect to smb server with \\10.255.255.1\<location> to access the smb behind firewalls.

Need:

- smb server with ssh server
- private and public keys to connect ssh (since openssh doesn't support password in command line).

Usage:

```
.\smb.ps1 "<user>@<ip> -p <Port> -i <private_key>"
```

Then reboot.

To test the result, execute the two commands:

```
netstat -an | find ":445 "
netsh interface portproxy show v4tov4
```

The results should be like

![test](test.png)

The line

```
TCP    10.255.255.1:445       0.0.0.0:0              LISTENING
```

should exists.

Then you can access smb server with locations like \\10.255.255.1\<location>
