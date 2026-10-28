// SPDX-License-Identifier: LGPL-2.1-or-later
unit Fabout;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Fbase, consts, osver, Types, UTextMetrics;

type

  { TfrmAbout }

  TfrmAbout = class(TfrmBase)
    imgAppIcon: TImage;
    Image2: TImage;
    Label1: TLabel;
    Label10: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Label6: TLabel;
    Label7: TLabel;
    Label8: TLabel;
    Label9: TLabel;
    lbAppName: TLabel;
    lbCopyright: TLabel;
    lbOS: TLabel;
    lbVer: TLabel;
    pcAbout: TPageControl;
    pnlMain: TPanel;
    tsOne: TTabSheet;
    tsTwo: TTabSheet;
    procedure FormActivate(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Image2Click(Sender: TObject);
    procedure imgAppIconClick(Sender: TObject);
    procedure pcAboutChange(Sender: TObject);
  private

  public

  end;

var
  frmAbout: TfrmAbout;

implementation

{$R *.lfm}

{ ===========================================================================
  TfrmAbout.FormActivate  (procedure)
  Parameters:
    Sender: TObject - the component that raised the event
  Notes:
    TfrmAbout
  =========================================================================== }
procedure TfrmAbout.FormActivate(Sender: TObject);
begin
  SetButtons([fcbOK]);
end;

{ ===========================================================================
  TfrmAbout.FormCreate  (procedure)
  Parameters:
    Sender: TObject - the form
  Notes:
    OnCreate handler: fills in the copyright text, the application name with its target (x86 or
    x64), the version and the operating system description.
  =========================================================================== }
procedure TfrmAbout.FormCreate(Sender: TObject);
var
  LargeIcon: TIcon;
  IconSize: TSize;
  Index: Integer;
begin
  lbCopyright.Caption := lCopyright;
  lbAppName.Caption := lAppName + ' ' + lTarget;
  lbVer.Caption := GetVerEx(lVerMajor, lVerMinor, lVerRev);
  lbOS.Caption := GetOsVer;

  LargeIcon := TIcon.Create;
  try
    LargeIcon.Assign(Application.Icon);

    IconSize.cx := 256;
    IconSize.cy := 256;
    Index := LargeIcon.GetBestIndexForSize(IconSize);
    if Index >= 0 then
      LargeIcon.Current := Index;

    imgAppIcon.AutoSize := False;
    imgAppIcon.SetBounds(imgAppIcon.Left, imgAppIcon.Top, 72, 72);
    imgAppIcon.Stretch := True;
    imgAppIcon.Proportional := True;
    imgAppIcon.Center := True;
    imgAppIcon.Picture.Assign(LargeIcon);
  finally
    LargeIcon.Free;
  end;
end;

{ ===========================================================================
  TfrmAbout.Image2Click  (procedure)
  Parameters:
    Sender: TObject - the picture
  Notes:
    Click handler of the second picture on the About box; nothing to do.
  =========================================================================== }
procedure TfrmAbout.Image2Click(Sender: TObject);
begin

end;

{ ===========================================================================
  TfrmAbout.imgAppIconClick  (procedure)
  Parameters:
    Sender: TObject - the picture
  Notes:
    Click handler of the application icon on the About box; nothing to do.
  =========================================================================== }
procedure TfrmAbout.imgAppIconClick(Sender: TObject);
begin

end;

{ ===========================================================================
  TfrmAbout.pcAboutChange  (procedure)
  Parameters:
    Sender: TObject - the page control
  Notes:
    Handler for a change of page on the About box; nothing to do.
  =========================================================================== }
procedure TfrmAbout.pcAboutChange(Sender: TObject);
begin

end;

end.

