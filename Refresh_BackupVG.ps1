# Script to refresh Backup VG for Reporting Restore
# Can be run from anywhere
# Requries Nutanix CMDLets to be installed
# Backup VG must be connected via Native Attachment in AHV not iSCSI
# ------------------------------------------------------------------------

# Parameters For Cluster Connectivity
[string]$prism_ip = '192.168.1.200'
[string]$prism_user = 'admin'
[string]$prism_pass = 'mypass'

# Parameters to Identify VG and Clone Info
[string]$Reporting_VM_Name = 'Reporting'
[string]$Source_VG = 'ProdBackupVG'
[string]$Target_VG = 'ReportingBackupVG'

# ------------------------------------------------------------------------

function Get-TimeStamp {
    
    return "[{0:MM/dd/yy} {0:HH:mm:ss}]" -f (Get-Date)
    
}

function Log-Output {
    param (
        $String
    )

    Write-Output "$(Get-Timestamp) $($String)"
}

function Check-Status {
    param (
        $task
    )

    $status = Get-NTNXTask -Taskid $task.taskUuid
    while ($status.progressStatus -eq "Running") {
        Log-Output " Task Running: $($task.taskUuid)"
        Start-Sleep -Seconds 1
        $status = Get-NTNXTask -Taskid $task.taskUuid
    }
    Log-Output "$($status.progressStatus)"

}


# Import Nutanix Modules
& 'C:\Program Files (x86)\Nutanix Inc\NutanixCmdlets\powershell\import_modules\ImportModules.PS1'

# Convert our Password
$secure_pass = ConvertTo-SecureString -String $prism_pass -AsPlainText -Force

# Connect to the cluster
Log-Output "Connecting to Nutanix Cluster at: $prism_ip"
Connect-NutanixCluster -Server $prism_ip -UserName $prism_user -Password $secure_pass -AcceptInvalidSSLCerts

# Collect UUIDs for our named objects
$VGs = Get-NTNXVolumeGroups
$Source = $VGs | Where-Object {$_.name -eq $Source_VG} 
$Target = $VGs | Where-Object {$_.name -eq $Target_VG}
$VM = Get-NTNXVM | Where-Object {$_.vmname -eq $Reporting_VM_Name}

# Detach Reporting VG from the Backup Volume Group
# -------------------------------------------------------
Log-Output "Detaching VM: $($VM.vmName) From VG: $($Target.name)"

$task = DetachVm-NTNXVolumeGroup -Uuid $Target.uuid -VmUuid $VM.uuid
Check-Status $task

# Drop Cloned Reporting VG to prepare for refresh
# -------------------------------------------------------
Log-Output "Dropping VG: $($Target.name)"

$task = Delete-NTNXVolumeGroup -Uuid $Target.uuid
Check-Status $task

# Clone Backup VG to Reporting VG
# -------------------------------------------------------
Log-Output "Cloning Source VG: $($Source.name) to Target VG: $($Target.name)"

$task = Clone-NTNXVolumeGroup -SourceVolumeGroupUuid $Source.uuid -Name $Target_VG
Check-Status $task

$new_VG = Get-NTNXVolumeGroups | Where-Object {$_.name -eq $Target_VG}

# Attach Reporting VG to the Backup Volume Group
# -------------------------------------------------------
Log-Output "Attaching VM: $($VM.vmName) To VG: $($new_VG.name)"

$task = AttachVm-NTNXVolumeGroup -Uuid $new_VG.uuid -VmUuid $VM.uuid
Check-Status $task

# Complete
Log-Output "Complete"




