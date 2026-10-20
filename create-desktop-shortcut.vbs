Option Explicit
' Create only the game shortcut. Resolve the Desktop through Windows, not a fixed path.
Dim fs, shell, project, launcher, desktop, title, shortcutPath, link, existing
Dim engine, candidate, engineNames, folder, folders, name
Set fs = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
project = fs.GetParentFolderName(WScript.ScriptFullName)
launcher = fs.BuildPath(project, "play.bat")
If Not fs.FileExists(fs.BuildPath(project, "project.godot")) Then Fail "project.godot is missing beside this script.", 1
If Not fs.FileExists(launcher) Then Fail "play.bat is missing beside this script.", 1
desktop = shell.SpecialFolders("Desktop")
If Len(desktop) = 0 Or Not fs.FolderExists(desktop) Then Fail "Windows did not provide an available Desktop directory.", 1
' U+542F U+52A8 U+6E38 U+620F: the Chinese name works under any Windows code page.
title = "S.S.Agency " & ChrW(&H542F) & ChrW(&H52A8) & ChrW(&H6E38) & ChrW(&H620F)
shortcutPath = fs.BuildPath(desktop, title & ".lnk")
If fs.FileExists(shortcutPath) Then
    Set existing = shell.CreateShortcut(shortcutPath)
    If LCase(existing.TargetPath) = LCase(launcher) And LCase(existing.WorkingDirectory) = LCase(project) And existing.Arguments = "" Then
        WScript.Echo "ALREADY_PRESENT: " & shortcutPath
        WScript.Quit 0
    End If
    Fail "An existing Desktop item has a different target; it was preserved: " & shortcutPath, 2
End If
If fs.FolderExists(shortcutPath) Then Fail "An existing Desktop folder was preserved: " & shortcutPath, 2
engine = ""
engineNames = Array("Godot_v4.7.2-stable_win64.exe", "Godot_v4.7.2-stable_win64_console.exe")
folders = Array(project, fs.GetParentFolderName(project))
For Each folder In folders
    For Each name In engineNames
        candidate = fs.BuildPath(folder, name)
        If engine = "" And fs.FileExists(candidate) Then engine = candidate
    Next
Next
On Error Resume Next
Set link = shell.CreateShortcut(shortcutPath)
link.TargetPath = launcher
link.WorkingDirectory = project
link.Arguments = ""
link.Description = "Launch the S.S.Agency game title, not the Godot editor."
link.WindowStyle = 1
If engine <> "" Then link.IconLocation = engine & ",0"
link.Save
If Err.Number <> 0 Then
    Dim detail
    detail = Err.Description
    On Error GoTo 0
    Fail "Could not create the Desktop shortcut: " & detail, 3
End If
On Error GoTo 0
If Not fs.FileExists(shortcutPath) Then Fail "The Desktop shortcut was not saved.", 3
WScript.Echo "CREATED: " & shortcutPath

Sub Fail(message, code)
    WScript.Echo "ERROR: " & message
    WScript.Quit code
End Sub
