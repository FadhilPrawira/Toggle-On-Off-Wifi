<#
.SYNOPSIS
    Toggles the state (enable/disable) of a specific WLAN adapter.
    Automatically requests elevated privileges if not already running as administrator.

.DESCRIPTION
    This script is designed to enable or disable a particular Wi-Fi adapter based on its
    exact Interface Description. It provides clear feedback on the operation's outcome,
    including the initial and final status of the adapter.

    If not run as administrator, it will attempt to re-launch itself with elevated privileges,
    triggering a User Account Control (UAC) prompt.

    It treats "Up" (connected) and "Disconnected" (enabled but not connected) states
    the same, prompting the script to disable the adapter if it's in either of these states.
    If the adapter is "Disabled", the script will attempt to enable it.

.NOTES
    Requires administrative privileges to run the network commands successfully.
    The WLAN adapter's Interface Description is hardcoded within the script for simplicity.
    Uses 'Get-NetAdapter', 'Disable-NetAdapter', and 'Enable-NetAdapter' cmdlets.
#>

# --- Configuration ---
# IMPORTANT: Replace this with the exact Interface Description of your Wi-Fi adapter.
# You can find it by running 'Get-NetAdapter' in PowerShell.
$TargetInterfaceDescription = "Intel(R) Wi-Fi 6 AX201 160MHz"

# --- Function to Check for Administrator Privileges ---
function Test-IsAdministrator {
    # Checks if the script is running with administrative privileges.
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Automatic Elevation Request ---
if (-not (Test-IsAdministrator)) {
    Write-Host "Not running as administrator. Attempting to elevate privileges..." -ForegroundColor Yellow

    # Get the path to the current script
    $scriptPath = $MyInvocation.MyCommand.Path

    # Construct the argument list for the new PowerShell process
    # -NoProfile: Prevents loading of current user's PowerShell profile (optional, but good for clean re-launch)
    # -ExecutionPolicy Bypass: Temporarily allows script execution for this session (optional, but good if default is too restrictive)
    # -File: Specifies the script to run
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""

    # Re-launch the script with elevated privileges
    # -Verb RunAs: This is what triggers the UAC prompt
    try {
        Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $arguments -Wait
    }
    catch {
        Write-Error "Failed to re-launch with administrator privileges. Error: $($_.Exception.Message)"
        Write-Error "Please run PowerShell as an administrator manually."
        Read-Host -Prompt "Press Enter to exit..."
        Exit 1
    }

    # Exit the current non-elevated script instance
    Exit 0
}

# --- Main Script Logic (This part only runs if the script is already elevated) ---

Write-Host "Running with administrator privileges. Attempting to manage WLAN adapter: '$TargetInterfaceDescription'..." -ForegroundColor Cyan

# Get the network adapter using its Interface Description
try {
    $wifiAdapter = Get-NetAdapter -InterfaceDescription $TargetInterfaceDescription -ErrorAction Stop
}
catch {
    Write-Error "Error: WLAN adapter with description '$TargetInterfaceDescription' not found or could not be accessed."
    Write-Error "Details: $($_.Exception.Message)"
    Read-Host -Prompt "Press Enter to exit..."
    Exit 1 # Exit the script if the adapter isn't found
}

# Display initial status
Write-Host "Status Awal: $($wifiAdapter.Status)"

if ($wifiAdapter) {
    $initialStatus = $wifiAdapter.Status # Store initial status for comparison

    # If the adapter is Up OR Disconnected, attempt to disable it
    if ($initialStatus -eq "Up" -or $initialStatus -eq "Disconnected") {
        Write-Host "Disabling Wi-Fi adapter: $($wifiAdapter.Name)..."
        try {
            # Attempt to disable the adapter
            Disable-NetAdapter -Name $wifiAdapter.Name -Confirm:$false -ErrorAction Stop
            # Give the system a moment to apply the change
            Start-Sleep -Milliseconds 500
            # Re-query the adapter to get its current (updated) status
            $updatedAdapter = Get-NetAdapter -InterfaceDescription $TargetInterfaceDescription -ErrorAction SilentlyContinue
            if ($updatedAdapter.Status -eq "Disabled") {
                Write-Host "Wi-Fi adapter successfully disabled." -ForegroundColor Green
            } else {
                Write-Warning "Failed to disable '$($wifiAdapter.Name)'. Current status: $($updatedAdapter.Status)"
            }
        }
        catch {
            Write-Error "Failed to disable '$($wifiAdapter.Name)'. Error: $($_.Exception.Message)"
            Write-Error "Even with elevation, something prevented the command from executing."
        }
    }
    # If the adapter is Disabled, attempt to enable it
    elseif ($initialStatus -eq "Disabled") {
        Write-Host "Enabling Wi-Fi adapter: $($wifiAdapter.Name)..."
        try {
            # Attempt to enable the adapter
            Enable-NetAdapter -Name $wifiAdapter.Name -Confirm:$false -ErrorAction Stop
            # Give the system a moment to apply the change
            Start-Sleep -Milliseconds 500
            # Re-query the adapter to get its current (updated) status
            $updatedAdapter = Get-NetAdapter -InterfaceDescription $TargetInterfaceDescription -ErrorAction SilentlyContinue
            if ($updatedAdapter.Status -eq "Up" -or $updatedAdapter.Status -eq "Disconnected") {
                Write-Host "Wi-Fi adapter successfully enabled." -ForegroundColor Green
            } else {
                Write-Warning "Failed to enable '$($wifiAdapter.Name)'. Current status: $($updatedAdapter.Status)"
            }
        }
        catch {
            Write-Error "Failed to enable '$($wifiAdapter.Name)'. Error: $($_.Exception.Message)"
            Write-Error "Even with elevation, something prevented the command from executing."
        }
    }
    # For any other unexpected states (e.g., "Not Operable")
    else {
        Write-Warning "Adapter '$($wifiAdapter.Name)' is in an unexpected state: '$initialStatus'. Skipping toggle."
        Write-Warning "Only 'Up'/'Disconnected' (to disable) or 'Disabled' (to enable) states are handled by this script."
    }

    # Get and display the final status of the adapter, ensuring it's the most current.
    $finalAdapterState = Get-NetAdapter -InterfaceDescription $TargetInterfaceDescription -ErrorAction SilentlyContinue
    if ($finalAdapterState) {
        Write-Host "Status Akhir: $($finalAdapterState.Status)"
    } else {
        Write-Error "Could not retrieve final status of the adapter."
    }

} else {
    # This block should ideally not be reached if Get-NetAdapter with -ErrorAction Stop is used
    # But it remains for defensive programming if -ErrorAction was changed or ignored.
    Write-Warning "Wi-Fi adapter with description '$TargetInterfaceDescription' was not found after initial check."
}

# Keep the console window open until the user presses Enter
Read-Host -Prompt "Press Enter to exit..."