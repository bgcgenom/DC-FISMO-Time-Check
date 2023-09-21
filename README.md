# DC-FISMO-Time-Check
Get all domain controllers, locate all FISMO roles and check date and time sync with NTP server

To Run:
Enter your NTP server's IP address in line 48 and 65.
Run as Adminsistrator in PowerShell.

This script does the following:
Search Active Directory for all Domain Controllers.

Get Domain Domain Forest Mode and Functional.
Lists FISMO role owners.
Checks each Domain Controller against an NTP source and displays the time shift warning if it is out or synchronization more than 5 minutes.
