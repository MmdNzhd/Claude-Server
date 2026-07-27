' Claude Connect - relaunch connect.bat with no window (WScript.Shell style 0).
' Used by connect.bat BAT_INNER so Explorer double-click never leaves a
' minimized/taskbar console. Child inherits CLAUDE_CONNECT_BAT_INNER=1.
Option Explicit
Dim sh, fso, dir, bat, args, i
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
bat = dir & "\connect.bat"
If Not fso.FileExists(bat) Then
  MsgBox "Missing connect.bat in:" & vbCrLf & dir, vbCritical, "Claude Connect"
  WScript.Quit 1
End If
sh.Environment("PROCESS")("CLAUDE_CONNECT_BAT_INNER") = "1"
args = ""
If WScript.Arguments.Count > 0 Then
  For i = 0 To WScript.Arguments.Count - 1
    args = args & " " & WScript.Arguments(i)
  Next
End If
sh.CurrentDirectory = dir
' style 0 = hidden (not minimized); False = do not wait
sh.Run "cmd.exe /d /c """ & bat & """" & args, 0, False
