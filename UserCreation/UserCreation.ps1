$username = "Max"
$userfullname = "Max Mustermann"
$groupname = "Coder"
$groupdescription = "Alle Rechte für das Entwickeln von Apps"
$worktime = "Mo-Fr,07:00-19:00"

# Erstellen eines neuen Users namens Peter
New-LocalUser -Name $username -NoPassword -AccountNeverExpires -Description "Praktikant" -FullName $userfullname

# Information zu dem erstellten User
Get-LocalUser -Name $username

# Entsperren des Users
NET USER $username /active:yes
# oder
Enable-LocalUser -Name $username

# Anmeldezeiten festlegen für einen Benutzer nur zwischen 7-11 Uhr
net user $username /times:$worktime

# Entferne eine Gruppe
Remove-LocalGroup $groupname

# Erstelle eine neue Gruppe
New-LocalGroup -Name $groupname -Description $groupdescription

# Füge eine Person einer Gruppe hinzu
Add-LocalGroupMember -Group $groupname -Member $username

# Füge eine Person der User Gruppe hinzu
Add-LocalGroupMember -Group Benutzer -Member $username

# Liste alle Mitglieder einer Gruppe auf
Get-LocalGroupMember -Group $groupname

# Alle Informationen zum Benutzer
Net User $username

# Suche der SID des Benutzers
$objUser = New-Object System.Security.Principal.NTAccount($username)
$sid = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
echo "SID: " $sid.Value

# Auffindbar im Regedit.exe unter:
# HKEY_LOCAL_MACHINE
# └─ SOFTWARE
#    └─ Microsoft
#       └─ Windows NT
#          └─ CurrentVersion
#             └─ ProfileList


# Sperren des Users
#NET USER $username /active:no
# oder
#Disable-LocalUser -Name $username