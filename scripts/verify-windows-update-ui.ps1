param(
    [Parameter(Mandatory=$true)][string]$AppPath,
    [Parameter(Mandatory=$true)][string]$ExpectedVersion,
    [Parameter(Mandatory=$true)][string]$ProofPath
)
$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Run this desktop test only on an isolated GitHub Actions Windows runner.' }
if ([IO.Path]::GetFileName($AppPath) -ne 'Nashi.exe' -or !(Test-Path $AppPath)) { throw 'Choose the extracted Nashi test app.' }
if ($ExpectedVersion -notmatch '^\d+\.\d+\.\d+(\.\d+)?$') { throw 'Choose a numeric update version.' }
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class NashiIsolatedUpdateUi {
    private delegate bool WindowVisitor(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(WindowVisitor visitor, IntPtr parameter);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int capacity);
    [DllImport("user32.dll")] private static extern IntPtr GetDlgItem(IntPtr window, int id);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool IsWindowEnabled(IntPtr window);
    [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    public static bool Confirm(int processId) {
        bool confirmed = false;
        EnumWindows(delegate(IntPtr window, IntPtr ignored) {
            uint owner; GetWindowThreadProcessId(window, out owner);
            if (owner != (uint)processId || !IsWindowVisible(window)) return true;
            var title = new StringBuilder(256); GetWindowText(window, title, title.Capacity);
            if (title.ToString() != "Nashi update") return true;
            var button = GetDlgItem(window, 1); // Native IDOK, only in this app's exact update dialog.
            if (button == IntPtr.Zero || !IsWindowVisible(button) || !IsWindowEnabled(button)) return true;
            var name = new StringBuilder(64); GetWindowText(button, name, name.Capacity);
            if (name.ToString().Replace("&", "").Trim() != "OK") return true;
            confirmed = PostMessage(button, 0x00F5, IntPtr.Zero, IntPtr.Zero); // BM_CLICK
            return !confirmed;
        }, IntPtr.Zero);
        return confirmed;
    }
}
'@

function Find-Element($Root, $Scope, $Conditions) {
    $condition = New-Object System.Windows.Automation.AndCondition -ArgumentList (,$Conditions)
    return $Root.FindFirst($Scope, $condition)
}
function Property-Equals($Property, $Value) {
    return New-Object System.Windows.Automation.PropertyCondition -ArgumentList $Property,$Value
}
try {
    $app = Start-Process -FilePath $AppPath -WorkingDirectory ([IO.Path]::GetDirectoryName($AppPath)) -PassThru
    $appHandle = $app.Handle # Keep the OS handle so a fast exit still exposes its real status.
    $processCondition = Property-Equals ([System.Windows.Automation.AutomationElement]::ProcessIdProperty) $app.Id
    $button = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while ([DateTime]::UtcNow -lt $deadline) {
        $app.Refresh()
        if ($app.HasExited) { throw 'The original app exited before showing its update.' }
        if ($app.MainWindowHandle -ne [IntPtr]::Zero) {
            $root = [System.Windows.Automation.AutomationElement]::FromHandle($app.MainWindowHandle)
            $button = Find-Element $root ([System.Windows.Automation.TreeScope]::Descendants) @(
                (Property-Equals ([System.Windows.Automation.AutomationElement]::NameProperty) ('Update to '+$ExpectedVersion)),
                (Property-Equals ([System.Windows.Automation.AutomationElement]::ControlTypeProperty) ([System.Windows.Automation.ControlType]::Button))
            )
            if ($null -ne $button -and $button.Current.IsEnabled) { break }
        }
        Start-Sleep -Milliseconds 500
    }
    if ($null -eq $button) { throw 'The real app never displayed its available-update button.' }
    $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    $dialog = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $deadline) {
        $dialog = Find-Element ([System.Windows.Automation.AutomationElement]::RootElement) ([System.Windows.Automation.TreeScope]::Children) @(
            $processCondition,
            (Property-Equals ([System.Windows.Automation.AutomationElement]::NameProperty) 'Nashi update')
        )
        if ($null -eq $dialog) { $dialog = Find-Element $root ([System.Windows.Automation.TreeScope]::Descendants) @($processCondition,(Property-Equals ([System.Windows.Automation.AutomationElement]::NameProperty) 'Nashi update')) }
        if ($null -ne $dialog) { break }
        Start-Sleep -Milliseconds 200
    }
    if ($null -eq $dialog) { throw 'The update confirmation did not appear.' }
    $confirm = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    $observed = @()
    while ([DateTime]::UtcNow -lt $deadline) {
        $buttons = $dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, (Property-Equals ([System.Windows.Automation.AutomationElement]::ControlTypeProperty) ([System.Windows.Automation.ControlType]::Button)))
        $observed = @()
        foreach ($candidate in $buttons) {
            $info = $candidate.Current
            $observed += @{ name=$info.Name; id=$info.AutomationId; enabled=$info.IsEnabled }
            if ($info.IsEnabled -and ($info.AutomationId -eq '1' -or $info.Name.Replace('&','').Trim() -eq 'OK')) { $confirm = $candidate; break }
        }
        if ($null -ne $confirm) { break }
        Start-Sleep -Milliseconds 200
    }
    $confirmationMethod = 'UI Automation InvokePattern'
    if ($null -ne $confirm) {
        $confirm.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    } elseif ([NashiIsolatedUpdateUi]::Confirm($app.Id)) {
        # Some hosted desktop providers expose the dialog title but omit its native buttons.
        $confirmationMethod = 'Native visible IDOK button'
    } else { throw ('The update confirmation had no visible OK action. Buttons: '+($observed | ConvertTo-Json -Compress)) }
    if (!$app.WaitForExit(120000)) { throw 'The real update did not close the original app within two minutes.' }
    if ($app.ExitCode -ne 0) { throw 'The original app exited with an update error.' }
    # An upgrade may legitimately offer the new first-run tools dialog. Close
    # only this exact app's setup window before the caller tests normal quit.
    # Never download tools, change preferences or kill the restarted process.
    $setupObserved = $false
    $setupClosed = $false
    $readySince = $null
    $deadline = [DateTime]::UtcNow.AddSeconds(90)
    while ([DateTime]::UtcNow -lt $deadline) {
        $reopened = Get-Process -Name Nashi -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $app.Id -and $_.Path -eq $AppPath -and $_.MainWindowHandle -ne 0 } | Select-Object -First 1
        if ($null -ne $reopened) {
            $installed = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path ([IO.Path]::GetDirectoryName($AppPath)) 'Nashi.dll')).FileVersion
            if (([version]$installed).ToString(3) -eq ([version]$ExpectedVersion).ToString(3)) {
                $root = [System.Windows.Automation.AutomationElement]::FromHandle($reopened.MainWindowHandle)
                $owner = Property-Equals ([System.Windows.Automation.AutomationElement]::ProcessIdProperty) $reopened.Id
                $setup = Find-Element ([System.Windows.Automation.AutomationElement]::RootElement) ([System.Windows.Automation.TreeScope]::Children) @(
                    $owner, (Property-Equals ([System.Windows.Automation.AutomationElement]::NameProperty) 'Set up Nashi tools')
                )
                if ($null -eq $setup) { $setup = Find-Element $root ([System.Windows.Automation.TreeScope]::Descendants) @($owner,(Property-Equals ([System.Windows.Automation.AutomationElement]::NameProperty) 'Set up Nashi tools')) }
                if ($null -ne $setup) {
                    $setupObserved = $true
                    $setup.GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close()
                    $setupClosed = $true
                    $readySince = $null
                } elseif ($root.Current.IsEnabled) {
                    if ($null -eq $readySince) { $readySince = [DateTime]::UtcNow }
                    if (([DateTime]::UtcNow - $readySince).TotalSeconds -ge 1) { break }
                } else { $readySince = $null }
            }
        }
        Start-Sleep -Milliseconds 200
    }
    if ($null -eq $readySince -or ([DateTime]::UtcNow - $readySince).TotalSeconds -lt 1) { throw 'The updated app did not return to an interactive main window.' }
    @{ availableUpdateObserved=$true; updateButtonInvoked=$true; confirmationInvoked=$true; confirmationMethod=$confirmationMethod; originalProcessId=$app.Id; expectedVersion=$ExpectedVersion; postUpdateSetupObserved=$setupObserved; postUpdateSetupClosed=$setupClosed } | ConvertTo-Json | Set-Content -Encoding utf8 $ProofPath
} catch {
    @{ error=$_.Exception.Message } | ConvertTo-Json | Set-Content -Encoding utf8 $ProofPath
    Write-Error $_
    exit 1
}
