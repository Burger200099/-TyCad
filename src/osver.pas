// SPDX-License-Identifier: LGPL-2.1-or-later
unit osver;

{$mode ObjFPC}{$H+}

interface

//uses FMX.StdCtrls, System.Classes;
uses  Graphics, Types {$IFDEF WINDOWS}, Windows{$ENDIF};

//const

{$IFDEF LINUX}
const LINUX_OS_VER_FILENAME = '/etc/os-release';

type
  L_VER_R = record
    VerType: byte;
    VerText: AnsiString;
    VerValue: AnsiString;
  end;

var  L_VER: array[0..8] of L_VER_R = (
      (VerType: 0; VerText: 'PRETTY_NAME='; VerValue: ''),
      (VerType: 1; VerText: 'NAME='; VerValue: ''),
      (VerType: 2; VerText: 'VERSION_ID='; VerValue: ''),
      (VerType: 3; VerText: 'VERSION='; VerValue: ''),
      (VerTYpe: 4; VerText: 'VERSION_CODENAME='; VerValue: ''),
      (VerType: 5; VerText: 'ID='; VerValue: ''),
      (VerType: 6; VerText: 'HOME_URL='; VerValue: ''),
      (VerType: 7; VerText: 'SUPPORT_URL='; VerValue: ''),
      (VerType: 8; VerText: 'BUG_REPORT_URL='; VerValue: ''));


{$ENDIF}



{$IFDEF MSWINDOWS}
  // winver shit

type
  W_VER_R = record
    Build: dword;
    WinText: array[0..24] of char;
  end;


const
  W_VER: array[0..27] of W_VER_R = (
    (Build: 26300; WinText: ' 11 (26H2)'),
    (Build: 28000; WinText: ' 11 (26H1)'),
    (Build: 26200; WinText: ' 11 (25H2)'),
    (Build: 26100; WinText: ' 11 (24H2)'),
    (Build: 22631; WinText: ' 11 (23H2)'),
    (Build: 22621; WinText: ' 11 (22H2)'),
    (Build: 22000; WinText: ' 11 (21H1)'),
    (Build: 19044; WinText: ' 10 (21H2)'),
    (Build: 19043; WinText: ' 10 (21H1)'),
    (Build: 19042; WinText: ' 10 (20H2)'),
    (Build: 19041; WinText: ' 10 (2004)'),
    (Build: 18363; WinText: ' 10 (1909)'),
    (Build: 18362; WinText: ' 10 (1903)'),
    (Build: 17763; WinText: ' 10 (1809)'),
    (Build: 17134; WinText: ' 10 (1803)'),
    (Build: 16299; WinText: ' 10 (1709)'),
    (Build: 15063; WinText: ' 10 (1703)'),
    (Build: 14393; WinText: ' 10 (1607)'),
    (Build: 10586; WinText: ' 10 (1511)'),
    (Build: 10240; WinText: ' 10'),
    (Build: 9600; WinText: ' 8.1 (Update 1)'),
    (Build: 9200; WinText: ' 8'),
    (Build: 7601; WinText: ' 7 SP1'),
    (Build: 7600; WinText: ' 7'),
    (Build: 6002; WinText: ' Vista SP2'),
    (Build: 6001; WinText: ' Vista SP1'),
    (Build: 6000; WinText: ' Vista'),
    (Build: 26003; WinText: ' XP'));

{$ENDIF}


function GetVer(lVerMajor, lVerMinor, lVerRev: integer): string;
function GetVerEx(lVerMajor, lVerMinor, lVerRev: integer): string;
function GetOsVer: string;

{$IFDEF WINDOWS}
const
   HCBT_ACTIVATE = 5;

function PrinterCBTHook(nCode: integer; Wparam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
function SetWindowsHookExWrap(idHook: Integer; lpfn: HOOKPROC; hMod: HINST; dwThreadId: DWORD): HHOOK;
function UnhookWindowsHookExWrap(hhk: HHOOK): BOOL;
procedure BeginPrinterDlgPlacement(const OwnerRect: TRect; OwnerWnd: HWND);
procedure EndPrinterDlgPlacement;
procedure BeginColorDlgPlacement(const AnchorRect: TRect; OwnerWnd: HWND);
{$ENDIF}

implementation

uses sysutils, classes, consts;

{ ===========================================================================
  GetVer  (function)
  Parameters:
    lVerMajor: integer - major version (the year)
    lVerMinor: integer - minor version (the month)
    lVerRev: integer - revision (the day)
  Returns:
    string - for example "v 26.10" or "v 26.10d"
  Notes:
    The program's version as text: "v major.minor", plus a letter when the revision is not 0 (1
    = a, 2 = b ...).
  =========================================================================== }
function GetVer(lVerMajor, lVerMinor, lVerRev: integer): string;
begin
  Result := 'v ' + inttostr(lVerMajor) + '.' + inttostr(lVerMinor);
  if lVerRev > 0 then
    Result := Result + char(96 + lVerRev);
end;

{ ===========================================================================
  GetVerEx  (function)
  Parameters:
    lVerMajor: integer - major version (the year)
    lVerMinor: integer - minor version (the month)
    lVerRev: integer - revision (the day)
  Returns:
    string - for example "v 26.10.4"
  Notes:
    The program's version as "v major.minor.revision".
  =========================================================================== }
function GetVerEx(lVerMajor, lVerMinor, lVerRev: integer): string;
begin
  Result := 'v ' + inttostr(lVerMajor) + '.' + inttostr(lVerMinor) + '.' + inttostr(lVerRev);
end;

{ ===========================================================================
  GetOsVer  (function)
  Parameters:  none
  Returns:
    string - the operating system description
  Notes:
    Describes the operating system: on Windows "Microsoft Windows" and the release name that
    matches the build number (from the W_VER table); on Linux the values read from /etc/os-
    release (pretty name, version, and so on) with their quotation marks removed. Other systems
    give an empty string.
  =========================================================================== }
function GetOsVer: string;
var OSString: string;
  i: integer;
{$IFDEF MSWINDOWS}
  pOSVERSIONINFOA: ^OSVERSIONINFOA;
{$ENDIF}
{$IFDEF LINUX}
  OsFileList: TStringList;
  s: string;
  j, k: integer;
  a: WideChar;

{$ENDIF}

begin
  OSString := '';
  {$IFDEF MSWINDOWS}
  try
    GetMem(pOSVERSIONINFOA, SizeOf(pOSVERSIONINFOA^));
    FillChar(pOSVERSIONINFOA^, SizeOf(pOSVERSIONINFOA^), 0);
    pOSVERSIONINFOA^.dwOSVersionInfoSize := SizeOf(pOSVERSIONINFOA^);
    if GetVersionEx(pOSVERSIONINFOA) then
      begin
        OSString := 'Microsoft Windows';
        for i := 0 to Length(W_VER) - 1 do
          begin
            if pOSVERSIONINFOA^.dwBuildNumber = W_VER[i].Build then
              begin
                OSString := OSString + strpas(W_VER[i].WinText);
                break;
              end;
          end;
      end;
  finally
    FreeMem(pOSVERSIONINFOA);
  end;
  {$ENDIF}
  {$IFDEF LINUX}
  try
    OsFileList := TStringList.Create;
    OsFileList.LoadFromFile(LINUX_OS_VER_FILENAME);
   for i := 0 to OsFileList.Count - 1 do
      begin
        for j := 0 to Length(L_VER) - 1 do
          begin
            s := copy(OsFileList[i], 0, Length(L_VER[j].VerText));
            if CompareStr(s, L_VER[j].VerText) = 0 then  // compared successfully
            begin
              L_VER[j].VerValue := copy(OsFileList[i], (Length(L_VER[j].VerText) + 1), (Length(OsFileList[i]) - Length(L_VER[j].VerText)));
              for k := Length(L_VER[j].VerValue) downto 1 do
                begin
                  if L_VER[j].VerValue[k] = '"' then
                    Delete(L_VER[j].VerValue, k, 1);
                end;
            end;
          end;
      end;
  finally
    OsFileList.Free;
  end;
  if Length(L_VER[0].VerValue) > 0 then
    OsString := L_VER[0].VerValue;  // "Pretty Name"

  {$ENDIF}
  Result := OSString;
end;

{$IFDEF WINDOWS}

const
  EVENT_OBJECT_SHOW = $8002;
  WINEVENT_OUTOFCONTEXT = 0;

type
  TWinEventProcLocal = procedure(hWinEventHook: THandle; event: DWORD; hwnd: HWND; idObject, idChild: LONG; idEventThread, dwmsEventTime: DWORD); stdcall;

{ ===========================================================================
  SetWinEventHook  (function)
  Parameters:
    eventMin: DWORD
    eventMax: DWORD
    hmodWinEventProc: HMODULE
    pfnWinEventProc: TWinEventProcLocal
    idProcess: DWORD
    idThread: DWORD
    dwFlags: DWORD
  Returns:
    THandle
  Notes:
    TODO: describe.
  =========================================================================== }
function SetWinEventHook(eventMin, eventMax: DWORD; hmodWinEventProc: HMODULE; pfnWinEventProc: TWinEventProcLocal; idProcess, idThread, dwFlags: DWORD): THandle;
  stdcall; external 'user32.dll' name 'SetWinEventHook';

{ ===========================================================================
  UnhookWinEvent  (function)
  Parameters:
    hWinEventHook: THandle
  Returns:
    BOOL
  Notes:
    TODO: describe.
  =========================================================================== }
function UnhookWinEvent(hWinEventHook: THandle): BOOL; stdcall; external 'user32.dll' name 'UnhookWinEvent';

const
  MONITOR_DEFAULTTONEAREST = 2;

type
  TMonitorInfoLocal = record
    cbSize: DWORD;
    rcMonitor: TRect;
    rcWork: TRect;
    dwFlags: DWORD;
  end;

{ ===========================================================================
  MonitorFromRectLocal  (function)
  Parameters:
    lprc: PRect
    dwFlags: DWORD
  Returns:
    THandle
  Notes:
    TODO: describe.
  =========================================================================== }
function MonitorFromRectLocal(lprc: PRect; dwFlags: DWORD): THandle; stdcall; external 'user32.dll' name 'MonitorFromRect';

{ ===========================================================================
  GetMonitorInfoLocal  (function)
  Parameters:
    hMonitor: THandle
    lpmi: Pointer
  Returns:
    BOOL
  Notes:
    TODO: describe.
  =========================================================================== }
function GetMonitorInfoLocal(hMonitor: THandle; lpmi: Pointer): BOOL; stdcall; external 'user32.dll' name 'GetMonitorInfoA';

var
  PrinterDlgHook: HHOOK = 0;         // WH_CBT hook: sees the windows made on this thread
  PrinterDlgEvent: THandle = 0;      // WinEvent hook: sees the windows made on any thread of the program (a driver may use its own)
  PrinterDlgOwner: TRect;            // screen rectangle of the form the printer window belongs to
  PrinterDlgOwnerWnd: HWND = 0;      // that form
  PrinterDlgPlaced: Boolean = False; // the window has been moved already
  PrinterDlgTimer: UINT_PTR = 0;     // thread timer that looks at the foreground window while the printer window is up
  PrinterDlgBelow: Boolean = False;  // the window is put below the rectangle PrinterDlgOwner (a color dialog under its button) instead of inside it; the hooks then end by themselves
  PrinterDlgTicks: Integer = 0;      // how many times the timer has looked

{ ===========================================================================
  PrinterDlgTryPlace  (procedure)
  Parameters:
    Wnd: HWND
  Notes:
    Moves the window to the owner's top left corner plus PrinterPropertiesOffsetLeft,
    PrinterPropertiesOffsetTop (consts.pas), or as near that as keeps it inside the owner's
    right and bottom edges, if it is the printer window: a top-level window with a title bar
    that is neither the owner form nor a window the owner form belongs to (the program's own
    forms are activated again when the printer window closes, and are never moved). Only the
    first such window is moved. With PrinterDlgBelow the owner rectangle is a color button's,
    and the window goes to the button's left edge and its bottom (see BeginColorDlgPlacement).
  =========================================================================== }
procedure PrinterDlgTryPlace(Wnd: HWND);
var
  R: TRect;
  W, H, X, Y: Integer;
  Anc: HWND;
  Mon: THandle;
  Info: TMonitorInfoLocal;
begin
  if PrinterDlgPlaced or (Wnd = 0) or (Wnd = PrinterDlgOwnerWnd) then
    Exit;
  if (GetWindowLong(Wnd, GWL_STYLE) and WS_CHILD) <> 0 then
    Exit;
  if (GetWindowLong(Wnd, GWL_STYLE) and WS_CAPTION) <> WS_CAPTION then
    Exit;
  Anc := PrinterDlgOwnerWnd;
  while Anc <> 0 do
  begin
    if Anc = Wnd then
      Exit;
    Anc := GetWindow(Anc, GW_OWNER);
  end;
  if not GetWindowRect(Wnd, R) then
    Exit;
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  if PrinterDlgBelow then
  begin
    { under the button: its left edge, and the dialog's top at the button's bottom; kept on the screen the button is on (above the button when it does not fit below) }
    Mon := MonitorFromRectLocal(@PrinterDlgOwner, MONITOR_DEFAULTTONEAREST);
    Info.cbSize := SizeOf(Info);
    if not GetMonitorInfoLocal(Mon, @Info) then
      Info.rcWork := Rect(0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
    X := PrinterDlgOwner.Left;
    Y := PrinterDlgOwner.Bottom;
    if X + W > Info.rcWork.Right then
      X := Info.rcWork.Right - W;
    if X < Info.rcWork.Left then
      X := Info.rcWork.Left;
    if Y + H > Info.rcWork.Bottom then
    begin
      if PrinterDlgOwner.Top - H >= Info.rcWork.Top then
        Y := PrinterDlgOwner.Top - H
      else
        Y := Info.rcWork.Bottom - H;
    end;
    SetWindowPos(Wnd, 0, X, Y, 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
    PrinterDlgPlaced := True;
    Exit;
  end;
  X := PrinterDlgOwner.Left + PrinterPropertiesOffsetLeft;
  Y := PrinterDlgOwner.Top + PrinterPropertiesOffsetTop;
  if X + W > PrinterDlgOwner.Right then
    X := PrinterDlgOwner.Right - W;
  if Y + H > PrinterDlgOwner.Bottom then
    Y := PrinterDlgOwner.Bottom - H;
  if X < PrinterDlgOwner.Left then
    X := PrinterDlgOwner.Left;
  if Y < PrinterDlgOwner.Top then
    Y := PrinterDlgOwner.Top;
  SetWindowPos(Wnd, 0, X, Y, 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  PrinterDlgPlaced := True;
end;

{ ===========================================================================
  PrinterCBTHook  (function)
  Parameters:
    nCode: Integer - whole number
    wParam: WPARAM
    lParam: LPARAM
  Returns:
    LRESULT
  Notes:
    A WH_CBT hook proc (windows made on this thread): the printer window being activated is
    moved by PrinterDlgTryPlace before it is shown.
  =========================================================================== }
function PrinterCBTHook(nCode: Integer; wParam: WPARAM;
  lParam: LPARAM): LRESULT; stdcall;
begin
  if nCode = HCBT_ACTIVATE then
    PrinterDlgTryPlace(HWND(wParam));
  Result := CallNextHookEx(PrinterDlgHook, nCode, wParam, lParam);
end;

{ ===========================================================================
  PrinterWinEvent  (procedure)
  Parameters:
    hWinEventHook: THandle
    event: DWORD
    hwnd: HWND
    idObject: LONG
    idChild: LONG
    idEventThread: DWORD
    dwmsEventTime: DWORD
  Notes:
    The WinEvent hook (windows made on any thread of the program): a window being shown is given
    to PrinterDlgTryPlace. Printer drivers often make their window on a thread of their own,
    which the thread hook above cannot see.
  =========================================================================== }
procedure PrinterWinEvent(hWinEventHook: THandle; event: DWORD; hwnd: HWND; idObject, idChild: LONG; idEventThread, dwmsEventTime: DWORD); stdcall;
begin
  if (event = EVENT_OBJECT_SHOW) and (idObject = 0) and (idChild = 0) then
    PrinterDlgTryPlace(hwnd);
end;

{ ===========================================================================
  PrinterDlgTimerProc  (procedure)
  Parameters:
    Wnd: HWND
    Msg: UINT - the message
    IdEvent: UINT_PTR
    Time: DWORD
  Notes:
    Runs every 25 ms on this thread while the printer window is up (the window's own message
    loop delivers it): the foreground window is given to PrinterDlgTryPlace, which moves it if
    it is the printer window. Stops itself once a window has been moved. This catches a window
    the two hooks do not report.
  =========================================================================== }
procedure PrinterDlgTimerProc(Wnd: HWND; Msg: UINT; IdEvent: UINT_PTR; Time: DWORD); stdcall;
begin
  PrinterDlgTryPlace(GetForegroundWindow);
  Inc(PrinterDlgTicks);
  { a color dialog's hooks end once it is placed (nobody is there to end them: the button's own click runs the dialog), or when it did not come }
  if PrinterDlgBelow and (PrinterDlgPlaced or (PrinterDlgTicks > 240)) then
  begin
    EndPrinterDlgPlacement;
    Exit;
  end;
  if PrinterDlgPlaced and (PrinterDlgTimer <> 0) then
  begin
    KillTimer(0, PrinterDlgTimer);
    PrinterDlgTimer := 0;
  end;
end;

{ ===========================================================================
  BeginPrinterDlgPlacement  (procedure)
  Parameters:
    const OwnerRect: TRect
    OwnerWnd: HWND
  Notes:
    Sets the hooks that move the next printer window to the owner's top left corner plus
    PrinterPropertiesOffsetLeft, PrinterPropertiesOffsetTop (consts.pas). Call
    EndPrinterDlgPlacement in a finally after the window has closed.
  =========================================================================== }
procedure BeginPrinterDlgPlacement(const OwnerRect: TRect; OwnerWnd: HWND);
begin
  EndPrinterDlgPlacement;
  PrinterDlgOwner := OwnerRect;
  PrinterDlgOwnerWnd := OwnerWnd;
  PrinterDlgPlaced := False;
  PrinterDlgBelow := False;
  PrinterDlgTicks := 0;
  PrinterDlgHook := Windows.SetWindowsHookEx(WH_CBT, @PrinterCBTHook, 0, GetCurrentThreadId);
  PrinterDlgEvent := SetWinEventHook(EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW, 0, @PrinterWinEvent, GetCurrentProcessId, 0, WINEVENT_OUTOFCONTEXT);
  PrinterDlgTimer := SetTimer(0, 0, 25, @PrinterDlgTimerProc);
end;

{ ===========================================================================
  EndPrinterDlgPlacement  (procedure)
  Parameters:  none
  Notes:
    Removes the hooks if they are set.
  =========================================================================== }
procedure EndPrinterDlgPlacement;
begin
  if PrinterDlgHook <> 0 then
  begin
    Windows.UnhookWindowsHookEx(PrinterDlgHook);
    PrinterDlgHook := 0;
  end;
  if PrinterDlgEvent <> 0 then
  begin
    UnhookWinEvent(PrinterDlgEvent);
    PrinterDlgEvent := 0;
  end;
  if PrinterDlgTimer <> 0 then
  begin
    KillTimer(0, PrinterDlgTimer);
    PrinterDlgTimer := 0;
  end;
end;

{ ===========================================================================
  BeginColorDlgPlacement  (procedure)
  Parameters:
    const AnchorRect: TRect
    OwnerWnd: HWND
  Notes:
    Sets the hooks that move the next window that appears (the color dialog the button is about
    to show) to the button's left edge and the button's bottom. Call it from the button's
    OnClick, which runs just before the button shows its dialog; there is no matching End call,
    the hooks end by themselves once the window is placed (or after about six seconds if none
    came). Dialogs that are not started from a color button are left where Windows puts them.
  =========================================================================== }
procedure BeginColorDlgPlacement(const AnchorRect: TRect; OwnerWnd: HWND);
begin
  BeginPrinterDlgPlacement(AnchorRect, OwnerWnd);
  PrinterDlgBelow := True;
end;

{ ===========================================================================
  SetWindowsHookExWrap  (function)
  Parameters:
    idHook: Integer - whole number
    lpfn: HOOKPROC
    hMod: HINST
    dwThreadId: DWORD
  Returns:
    HHOOK
  Notes:
    TODO: describe.
  =========================================================================== }
function SetWindowsHookExWrap(idHook: Integer; lpfn: HOOKPROC;
  hMod: HINST; dwThreadId: DWORD): HHOOK;
begin
  Result := Windows.SetWindowsHookEx(idHook, lpfn, hMod, dwThreadId);
end;

{ ===========================================================================
  UnhookWindowsHookExWrap  (function)
  Parameters:
    hhk: HHOOK
  Returns:
    BOOL
  Notes:
    TODO: describe.
  =========================================================================== }
function UnhookWindowsHookExWrap(hhk: HHOOK): BOOL;
begin
  Result := Windows.UnhookWindowsHookEx(hhk);
end;
{$ENDIF}

end.
