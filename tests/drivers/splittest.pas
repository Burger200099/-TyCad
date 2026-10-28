{ Driver for tests/run_splitbutton.py: makes a TSplitButton on a form and drives it with real mouse and key events (the control's own handlers),
  printing what happened. Needs the LCL (see the README for the build line). }
program splittest;
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF} Interfaces, Classes, SysUtils, Forms, Controls, Menus, LCLType, Graphics, CSplitButton;
type
  TProbe = class(TSplitButton)
  public
    procedure Down(X: Integer);
    procedure Up(X: Integer);
    procedure Move(X: Integer);
  end;
  THandlers = class
    Clicks, Drops, Items, DropClicks: Integer;
    procedure OnClk(Sender: TObject);
    procedure OnDrop(Sender: TObject);
    procedure OnDropClk(Sender: TObject);
    procedure OnItem(Sender: TObject);
  end;
procedure TProbe.Down(X: Integer); begin MouseDown(mbLeft, [], X, 5); end;
procedure TProbe.Up(X: Integer); begin MouseUp(mbLeft, [], X, 5); end;
procedure TProbe.Move(X: Integer); begin MouseMove([], X, 5); end;
procedure THandlers.OnClk(Sender: TObject); begin Inc(Clicks); end;
procedure THandlers.OnDrop(Sender: TObject); begin Inc(Drops); end;
procedure THandlers.OnDropClk(Sender: TObject); begin Inc(DropClicks); end;
procedure THandlers.OnItem(Sender: TObject); begin Inc(Items); end;
var
  IL, L1, L2: TImageList; Bm: TBitmap; Mode: String;
  F: TForm; B: TProbe; M: TPopupMenu; H: THandlers; I: TMenuItem;
begin
  Application.Initialize;
  H := THandlers.Create;
  F := TForm.CreateNew(Application); F.SetBounds(0, 0, 300, 100);
  M := TPopupMenu.Create(F); I := TMenuItem.Create(M); I.Caption := 'one'; I.OnClick := @H.OnItem; M.Items.Add(I);
  B := TProbe.Create(F); B.Parent := F; B.SetBounds(10, 10, 120, 28); B.Caption := 'Parts'; B.OnClick := @H.OnClk; B.OnDropDown := @H.OnDrop;
  F.Show; Application.ProcessMessages;
  { main part: down and up inside = one click, no drop down }
  B.Down(20); B.Up(20);
  WriteLn('MAIN clicks=', H.Clicks, ' drops=', H.Drops);
  { main part: down inside, up outside (over the arrow) = no click }
  B.Down(20); B.Up(115);
  WriteLn('SLIDEOFF clicks=', H.Clicks, ' drops=', H.Drops);
  { AutoCheck: a click on the main part turns Checked over, a slide off does not, the arrow does not }
  B.AutoCheck := True;
  B.Down(20); B.Up(20); WriteLn('AUTO1 checked=', Ord(B.Checked), ' clicks=', H.Clicks);
  B.Down(20); B.Up(115); WriteLn('AUTO2 checked=', Ord(B.Checked));
  B.Down(115); B.Up(115); WriteLn('AUTO3 checked=', Ord(B.Checked));
  B.Down(20); B.Up(20); WriteLn('AUTO4 checked=', Ord(B.Checked));
  B.AutoCheck := False; H.Clicks := 1;
  { arrow part without a menu: the event fires, no click }
  B.Down(115); B.Up(115);
  WriteLn('ARROWNOMENU clicks=', H.Clicks, ' drops=', H.Drops, ' down=', Ord(B.DownPart));
  { OnDropDownClick: only the arrow fires it (after OnDrop); the main part does not }
  B.OnDropDownClick := @H.OnDropClk;
  B.Down(20); B.Up(20);
  WriteLn('DDCMAIN dropclicks=', H.DropClicks);
  B.Down(115); B.Up(115);
  WriteLn('DDCARROW dropclicks=', H.DropClicks, ' drops=', H.Drops, ' clicks=', H.Clicks);
  B.OnDropDownClick := nil;
  B.Enabled := False; B.Down(20); B.Up(20);
  WriteLn('DISABLED clicks=', H.Clicks);
  WriteLn('PART at 5=', Ord(B.HotPart));
  B.Enabled := True;
  Mode := '';
  if ParamCount > 1 then Mode := ParamStr(2);
  if Mode = 'flat' then B.Flat := True;
  if Mode = 'checked' then begin B.Flat := True; B.Checked := True; end;
  if Mode = 'colortrans' then begin B.Flat := True; B.Color := TColor($0000FF); end;
  if Mode = 'color' then begin B.Flat := True; B.Transparent := False; B.Color := TColor($0000FF); end;
  if (Mode = 'img24') or (Mode = 'img32') then
  begin
    { a list with two sizes: 24 x 24 all red, 32 x 32 all blue }
    L1 := TImageList.Create(F); L1.Width := 24; L1.Height := 24;
    Bm := TBitmap.Create; Bm.SetSize(24, 24); Bm.Canvas.Brush.Color := clRed; Bm.Canvas.FillRect(0, 0, 24, 24); L1.Add(Bm, nil); Bm.Free;
    L2 := TImageList.Create(F); L2.Width := 32; L2.Height := 32;
    Bm := TBitmap.Create; Bm.SetSize(32, 32); Bm.Canvas.Brush.Color := clBlue; Bm.Canvas.FillRect(0, 0, 32, 32); L2.Add(Bm, nil); Bm.Free;
    IL := TImageList.Create(F); IL.Width := 24; IL.Height := 24; IL.AddImages(L1); IL.AddImages(L2);
    B.Height := 40; B.Images := IL; B.ImageIndex := 0; B.Caption := ''; B.ImageWidth := StrToInt(Copy(Mode, 4, 2));
    WriteLn('IMG res=', IL.ResolutionCount, ' count=', IL.Count);
  end;
  if (ParamCount > 2) and (ParamStr(3) = 'hot') then B.Move(20);
  B.Repaint; Application.ProcessMessages;
  if ParamCount > 0 then F.GetFormImage.SaveToFile(ParamStr(1));
  WriteLn('DROPPT ', B.DropDownPoint.X, ',', B.DropDownPoint.Y, ' w=', B.Width, ' h=', B.Height, ' arrow=', B.ArrowWidth);
  WriteLn('DONE');
end.
