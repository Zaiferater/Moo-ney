param([string]$OutputPath)

$ErrorActionPreference = 'Stop'
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$compiler = Join-Path $framework 'csc.exe'
$wpf = Join-Path $framework 'WPF'
$programName = ([string][char]0x725B) + [char]0x9A6C + [char]0x6253 + [char]0x6C14 + [char]0x673A
$destination = if ($OutputPath) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
} else {
    Join-Path $PSScriptRoot ($programName + '.exe')
}
$sources = @('Appearance.cs', 'Payroll.cs', 'Program.cs', 'SettingsChoices.cs', 'TimerWindow.cs', 'TypingCow.cs', 'WorkdayCalendar.cs') | ForEach-Object { Join-Path $PSScriptRoot $_ }
$icon = Join-Path $PSScriptRoot 'app.ico'
$sprites = @('panda', 'cat', 'penguin') | ForEach-Object {
    $path = Join-Path $PSScriptRoot "Mascots\$_.png"
    "/resource:$path,WorkdayTimer.Mascots.$_.png"
}

& $compiler /nologo /target:winexe /optimize+ /codepage:65001 "/out:$destination" `
    "/win32icon:$icon" "/resource:$icon,WorkdayTimer.App.ico" $sprites `
    "/reference:$wpf\PresentationCore.dll" "/reference:$wpf\PresentationFramework.dll" `
    "/reference:$wpf\WindowsBase.dll" "/reference:$framework\System.Xaml.dll" `
    "/reference:$framework\System.Windows.Forms.dll" "/reference:$framework\System.Drawing.dll" $sources
if ($LASTEXITCODE -ne 0) {
    throw 'The build failed.'
}

Write-Output $destination
