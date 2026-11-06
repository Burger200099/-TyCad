// SPDX-License-Identifier: LGPL-2.1-or-later
{ The list that drops down from the arrow of a table cell: the texts of the sheet a cell can show. A click, Enter or a double click chooses; Esc or a click elsewhere closes it. }
unit FtablePick;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, StdCtrls, LCLType, Math;

type

  { TfrmTablePick }

  TfrmTablePick = class(TForm)
    lbItems: TListBox;
    procedure FormDeactivate(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormShow(Sender: TObject);
    procedure lbItemsClick(Sender: TObject);
  private
    FChosen: Integer;
    FWantX, FWantY: Integer;
  public
    { shows the list with its top left corner at ScreenX, ScreenY; returns the number of the item chosen or -1 }
    function Pick(Items: TStrings; ScreenX, ScreenY, AWidth, CellH: Integer): Integer;
  end;

var
  TablePickAuto: Integer = -2;      // the self-test script: >= -1 is answered without showing the list (the item number, -1 = none)
  TablePickX: Integer = 0;          // where the last list was put (screen)
  TablePickY: Integer = 0;
  TablePickShown: Integer = 0;      // how many times a list was asked for

implementation

{$R *.lfm}

function TfrmTablePick.Pick(Items: TStrings; ScreenX, ScreenY, AWidth, CellH: Integer): Integer;
var
  WA: TRect;
begin
  FChosen := -1;
  lbItems.Items.Assign(Items);
  Width := AWidth;
  Height := Round(Min(Items.Count, 12) * 18) + 6;
  Position := poDesigned;
  { kept inside the screen: below the cell, or above it when there is no room
    (no 'with' here: a TRect has a Width and a Height of its own, which would hide this window's) }
  WA := Screen.MonitorFromPoint(Point(ScreenX, ScreenY)).WorkareaRect;
  if ScreenY + Self.Height > WA.Bottom then
    ScreenY := Max(WA.Top, ScreenY - Self.Height - CellH);
  ScreenX := Max(WA.Left, Min(ScreenX, WA.Right - Self.Width));
  FWantX := ScreenX; FWantY := ScreenY;
  SetBounds(ScreenX, ScreenY, Width, Height);
  TablePickX := Left; TablePickY := Top;
  Inc(TablePickShown);
  if TablePickAuto >= -1 then
  begin
    Result := TablePickAuto;
    Exit;
  end;
  ShowModal;
  Result := FChosen;
end;

procedure TfrmTablePick.FormShow(Sender: TObject);
begin
  SetBounds(FWantX, FWantY, Width, Height);      { (once the window exists: some systems place it themselves before that) }
  if lbItems.Items.Count > 0 then
    lbItems.ItemIndex := 0;
end;

procedure TfrmTablePick.lbItemsClick(Sender: TObject);
begin
  if lbItems.ItemIndex >= 0 then
  begin
    FChosen := lbItems.ItemIndex;
    ModalResult := mrOK;
  end;
end;

procedure TfrmTablePick.FormDeactivate(Sender: TObject);
begin
  if ModalResult = mrNone then
    ModalResult := mrCancel;
end;

procedure TfrmTablePick.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
    ModalResult := mrCancel
  else if Key = VK_RETURN then
  begin
    lbItemsClick(Self);
    Key := 0;
  end;
end;

end.
