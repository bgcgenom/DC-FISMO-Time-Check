# Get all domain controllers
$DomainControllers = Get-ADDomainController -Filter * | select hostname, IPv4Address, OperatingSystem
$DomainContollersCount = $DomainControllers.Count
Write-Host `n$DomainContollersCount "Domain Controllers`n------------------"
foreach ($DomainController in $DomainControllers){
  Write-Host $DomainController.hostname ` "--" $DomainController.OperatingSystem
}

# Get FSMO roles
$FSMOTable = @()
$FSMOTable += @(
  [PSCustomObject]@{
    InfrastructureMaster = Get-ADDomain | Select-Object InfrastructureMaster;
    RIDMaster = Get-ADDomain | Select-Object RIDMaster;
    PDCEmulator = Get-ADDomain | Select-Object PDCEmulator;
    DomainNamingMaster = Get-ADForest | Select-Object DomainNamingMaster;
    SchemaMaster = Get-ADForest | Select-Object SchemaMaster
  }
)

# Clean up and seperate FSMO output just owner of role
$InfrastructureMaster = $FSMOTable.InfrastructureMaster.InfrastructureMaster
$RIDMaster = $FSMOTable.RIDMaster.RIDMaster
$PDCEmulator = $FSMOTable.PDCEmulator.PDCEmulator
$DomainNamingMaster = $FSMOTable.DomainNamingMaster.DomainNamingMaster
$SchemaMaster = $FSMOTable.SchemaMaster.SchemaMaster

$FSMOData = @{
  "Infrastructure Master" = $InfrastructureMaster
  "RID Master" = $RIDMaster
  "PDC Emulator" = $PDCEmulator
  "Domain Naming Master" = $DomainNamingMaster
  "Schema Master" = $SchemaMaster
}

# Get Forest Mode
$ForestMode = Get-ADForest | Select-Object ForestMode
Write-Host `n"Forest Mode`n-----------------------`n" $ForestMode.ForestMode `n

# Get Domain Mode
$DomainMode = Get-ADDomain | Select-Object DomainMode
Write-Host `n"Domain Functional Level`n-----------------------`n" $DomainMode.DomainMode `n
# Display fsmo role owners
Write-Host "`nFSMO Roles and Owner`n--------------------"
$FSMOData | Format-Table -HideTableHeaders

# Get Stratum 2 from local NTP server
$LocalNTPTime = w32tm /stripchart /computer:172.16.16.43 /dataonly /samples:0

# Strip NTP output and split into date and time
$StripNTP = $LocalNTPTime[2]
$StripNTPDateTime = $StripNTP.Trim("The current time is . AM PM")
$StripNTPDateTime = $StripNTPDateTime -split " ",2
$StripNTPDate = $StripNTPDateTime[0]
$StripNTPTime = $StripNTPDateTime[1]
Write-Host `n"NTP server Date/Time:" $StripNTPDate, $StripNTPTime

Write-Host "Kerberos maximum time drift allowance is 5 minutes." `n

# Get time for each DC and form table output
$DCTable = @()
$IncrementCount = 0
foreach ($DomainController in $DomainControllers.hostname) {
  # Get Stratum 2 from local NTP server
  $LocalNTPTime = w32tm /stripchart /computer:172.16.16.43 /dataonly /samples:0
  
  # Strip NTP output and split into date and time
  $StripNTP = $LocalNTPTime[2]
  $StripNTPDateTime = $StripNTP.Trim("The current time is . AM PM")
  $StripNTPDateTime = $StripNTPDateTime -split " ",2
  $StripNTPDate = $StripNTPDateTime[0]
  $StripNTPTime = $StripNTPDateTime[1]

  $DCDateTime = invoke-command -ComputerName $DomainController -ScriptBlock {get-date -Format G}
  
  # Split get-date into date and time
  $SplitDCDateTime = $DCDateTime -split " "
  #$SplitDCDateTime
  $DCDate = $SplitDCDateTime[0]
  $DCTime = $SplitDCDateTime[1]

  # Create table contents
  $DCTable += @(
    [PSCustomObject]@{
      Domain_Controller = $DomainController;
      IPv4_Address = $DomainControllers.IPv4Address[$IncrementCount]
      DC_Date = $DCDate;
      DC_Time = $DCTime;
      NTP_Date = $StripNTPDate;
      NTP_Time = $StripNTPTime
    }
  )

  $IncrementCount = $IncrementCount + 1
}

# Output list of DCs, IP, local date, local time, NPT date, NTP time
#$DCTable | Format-Table

# Hashtable for DCs that are found in error
$DomainControllerError = @()

# Compare date and time for each DC list time differance
foreach ($DC in $DCTable) {
  # Check NTP time and date against DC time and date
  # Test if date differance is greater than 1 day
  if ($DC.DC_Date -ne $DC.NTP_Date){
    Write-Host -ForegroundColor DarkRed -BackgroundColor Gray "WARNING!!!" $DC.Domain_Controller "date is incorrect!  Please take appropiate actions!" 
  }
  if ($DC.DC_Time -ne $DC.NTP_Time){
    $TimeDiff = New-TimeSpan -Start $DC.NTP_Time -End $DC.DC_Time
    if ($TimeDiff.TotalMinutes -ge -0.3 -and $TimeDiff.TotalMinutes -le 0.3){
      Write-Host -ForegroundColor Green -BackgroundColor DarkGreen $DC.Domain_Controller "time is within 30 seconds of NTP server." 
    }
    elseif ($TimeDiff.TotalMinutes -ge -2.0 -and $TimeDiff.TotalMinutes -le 2){
      $DomainControllerError += @($DC.Domain_Controller, $TimeDiff.TotalMinutes)
      Write-Host -ForegroundColor Yellow $DC.Domain_Controller $DC.IPv4_Address "time is within 2 minutes of NTP server." 
    }
    elseif ($TimeDiff.TotalMinutes -ge -1440 -and $TimeDiff.TotalMinutes -le 1440){
      $DomainControllerError += @($DC.Domain_Controller, $TimeDiff.TotalMinutes)
      Write-Host -ForegroundColor Red -BackgroundColor Black $DC.Domain_Controller $DC.IPv4_Address "time is" $TimeDiff.TotalMinutes"minutes or more of NTP server." 
    }
  }
  if ($DC.DC_Time -eq $DC.NTP_Time){
    Write-Host -ForegroundColor Green $DC.Domain_Controller "time is synced exactly with NTP server."
  }
}

#$DomainControllerError

# Check domain controller for last successful sync time
$TimeSyncCheck = @()
foreach ($DCE in $DomainControllerError[0]) {
  Write-Host `n"Checking out-of-sync Domain Controllers"
  Write-Host "Getting last known time sync and source from:"`n$DCE
  $TimeSyncCheck += invoke-command -ComputerName $DCE -ScriptBlock {w32tm /query /status}

  # Split out TymeSyncCheck
  $TimeErrorDC = $TimeSyncCheck[6,7]
  $TimeErrorDCTime = $TimeErrorDC[0]
  $TimeErrorDCSource = $TimeErrorDC[1]
  
  # Strip TimeErrorDCTime and TimeErrorDCSource down to time and source
  $TimeErrorDCTime = $TimeErrorDCTime.Substring(27)
  if ($TimeErrorDCTime = "unspecified") {
    $TimeErrorDCTime = "Time sync: unknown"
  }
  $TimeErrorDCSource = $TimeErrorDCSource.Substring(8)
  if ($TimeErrorDCSource = "Free-running System Clock") {
    $TimeErrorDCSource = "Time source: BIOS"
  }
  Write-Host `t $TimeErrorDCTime
  Write-Host `t $TimeErrorDCSource `n
}
