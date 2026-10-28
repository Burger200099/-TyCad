// SPDX-License-Identifier: LGPL-2.1-or-later
{ Undo and redo.

  Each undo step is a snapshot of the whole design (as the same text a save would write) taken just
  before a change, together with which objects were selected. Restoring a step reloads the design in
  place. Objects keep their stable ids, so the selection can be found again afterwards and links
  (which refer to ids) survive.

  Snapshots are simple and cannot get out of step with the model. The cost is memory proportional to
  the design size per step; the depth is limited.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UUndo;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, UDesign;

type
  TIntArray = array of Integer;

  TUndoManager = class
  private
    type
      TSnap = record
        Text: String;
        Sel: TIntArray;
        Sheet: Integer;
        Caption: String;
      end;
  private
    FDesign: TDesignFile;
    FUndo, FRedo: array of TSnap;
    FMaxDepth: Integer;
    FPending: TSnap;
    FHasPending: Boolean;
    function Take(const ACaption: String; const ASel: TIntArray; ASheet: Integer): TSnap;
    procedure Restore(const S: TSnap; out ASel: TIntArray; out ASheet: Integer);
  public
    constructor Create(ADesign: TDesignFile);
    procedure SetDesign(ADesign: TDesignFile);
    procedure Reset;
    { Call BEFORE making a change. Clears the redo history. }
    procedure Push(const ACaption: String; const ASel: TIntArray; ASheet: Integer);
    { The same in two halves, for actions that might turn out to change nothing: Begin takes the
      snapshot, Commit keeps it as an undo step, Discard throws it away. }
    procedure BeginChange(const ACaption: String; const ASel: TIntArray; ASheet: Integer);
    procedure CommitChange;
    procedure DiscardChange;
    { put the design back as it was when the pending change began and forget that change: nothing is added to the undo or redo
      history. False if there is no pending change. }
    function Rollback(out ASel: TIntArray; out ASheet: Integer): Boolean;
    function HasPending: Boolean;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    function UndoCaption: String;
    function RedoCaption: String;
    function UndoCount: Integer;
    function RedoCount: Integer;
    { Undo / Redo give back the selection and sheet to show. CurSel/CurSheet describe the state being left. }
    function Undo(const CurSel: TIntArray; CurSheet: Integer; out ASel: TIntArray; out ASheet: Integer): Boolean;
    function Redo(const CurSel: TIntArray; CurSheet: Integer; out ASel: TIntArray; out ASheet: Integer): Boolean;
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
  end;

implementation

{ ===========================================================================
  TUndoManager.Create  (constructor)
  Parameters:
    ADesign: TDesignFile - the design whose history is kept
  Notes:
    Creates an undo manager for a design with a depth limit of 100 steps and empty history.
  =========================================================================== }
constructor TUndoManager.Create(ADesign: TDesignFile);
begin
  inherited Create;
  FMaxDepth := 100;
  SetDesign(ADesign);
end;

{ ===========================================================================
  TUndoManager.SetDesign  (procedure)
  Parameters:
    ADesign: TDesignFile - the new design
  Notes:
    Points the manager at a different design (or none), allows empty sheets on it, and clears
    the history.
  =========================================================================== }
procedure TUndoManager.SetDesign(ADesign: TDesignFile);
begin
  FDesign := ADesign;
  if FDesign <> nil then
    FDesign.AllowEmptySheets := True;
  Reset;
end;

{ ===========================================================================
  TUndoManager.Reset  (procedure)
  Parameters:  none
  Notes:
    Clears the undo and redo history and any change in progress.
  =========================================================================== }
procedure TUndoManager.Reset;
begin
  SetLength(FUndo, 0);
  SetLength(FRedo, 0);
  FHasPending := False;
end;

{ ===========================================================================
  TUndoManager.BeginChange  (procedure)
  Parameters:
    const ACaption: String - name of the action, shown for Undo
    const ASel: TIntArray - ids of the selected objects before the change
    ASheet: Integer - the sheet being shown before the change
  Notes:
    First half of a change that might turn out to do nothing: takes the snapshot now but does
    not put it on the undo stack yet.
  =========================================================================== }
procedure TUndoManager.BeginChange(const ACaption: String; const ASel: TIntArray; ASheet: Integer);
begin
  if FDesign = nil then
    Exit;
  FPending := Take(ACaption, ASel, ASheet);
  FHasPending := True;
end;

{ ===========================================================================
  TUndoManager.Rollback  (function)
  Parameters:
    out ASel: TIntArray - out: set by the call
    out ASheet: Integer - the sheet (out: set by the call)
  Returns:
    Boolean
  Notes:
    For a change that is abandoned half way (a pasted or imported block that is cancelled): the
    design is put back exactly as it was when the change began, which is more than taking away
    the objects that were added, because other things may have been touched meanwhile (a
    junction added beside the block, a wire joined). The change is forgotten: it is not an undo
    step and there is nothing to redo.
  =========================================================================== }
function TUndoManager.Rollback(out ASel: TIntArray; out ASheet: Integer): Boolean;
begin
  Result := FHasPending;
  SetLength(ASel, 0);
  ASheet := 0;
  if not Result then
    Exit;
  Restore(FPending, ASel, ASheet);
  FHasPending := False;
end;

{ ===========================================================================
  TUndoManager.HasPending  (function)
  Parameters:  none
  Returns:
    Boolean - True while a snapshot is waiting
  Notes:
    Says whether BeginChange has been called without a matching Commit or Discard.
  =========================================================================== }
function TUndoManager.HasPending: Boolean;
begin
  Result := FHasPending;
end;

{ ===========================================================================
  TUndoManager.DiscardChange  (procedure)
  Parameters:  none
  Notes:
    Throws away the pending snapshot because nothing changed, so no undo step is created.
  =========================================================================== }
procedure TUndoManager.DiscardChange;
begin
  FHasPending := False;
end;

{ ===========================================================================
  TUndoManager.CommitChange  (procedure)
  Parameters:  none
  Notes:
    Keeps the pending snapshot as an undo step (dropping the oldest when over the limit) and
    clears the redo history, since a new change has been made.
  =========================================================================== }
procedure TUndoManager.CommitChange;
var
  i: Integer;
begin
  if not FHasPending then
    Exit;
  FHasPending := False;
  if Length(FUndo) >= FMaxDepth then
  begin
    for i := 1 to High(FUndo) do FUndo[i - 1] := FUndo[i];
    SetLength(FUndo, Length(FUndo) - 1);
  end;
  SetLength(FUndo, Length(FUndo) + 1);
  FUndo[High(FUndo)] := FPending;
  SetLength(FRedo, 0);
end;

{ ===========================================================================
  TUndoManager.Take  (function)
  Parameters:
    const ACaption: String - name of the action
    const ASel: TIntArray - ids of the selected objects
    ASheet: Integer - current sheet index
  Returns:
    TSnap - the snapshot
  Notes:
    Captures the whole design as the text a save would write, together with the selection and
    sheet to restore.
  =========================================================================== }
function TUndoManager.Take(const ACaption: String; const ASel: TIntArray; ASheet: Integer): TSnap;
var
  MS: TStringStream;
begin
  MS := TStringStream.Create('');
  try
    FDesign.SaveToStream(MS);
    Result.Text := MS.DataString;
  finally
    MS.Free;
  end;
  Result.Sel := Copy(ASel, 0, Length(ASel));
  Result.Sheet := ASheet;
  Result.Caption := ACaption;
end;

{ ===========================================================================
  TUndoManager.Restore  (procedure)
  Parameters:
    const S: TSnap - the snapshot to restore
    out ASel: TIntArray - set to the ids to select afterwards
    out ASheet: Integer - set to the sheet to show afterwards
  Notes:
    Reloads the design in place from a snapshot. Object ids only ever go up across a restore, so
    ids of deleted objects are not reused; the file name is kept.
  =========================================================================== }
procedure TUndoManager.Restore(const S: TSnap; out ASel: TIntArray; out ASheet: Integer);
var
  MS: TStringStream;
  Keep: Integer;
  Name: String;
begin
  Keep := FDesign.LastAssignedId;   // ids only ever go up, even across undo
  Name := FDesign.FileName;
  MS := TStringStream.Create(S.Text);
  try
    MS.Position := 0;
    FDesign.LoadFromStream(MS);
  finally
    MS.Free;
  end;
  FDesign.FileName := Name;
  if FDesign.LastAssignedId < Keep then
    FDesign.LastAssignedId := Keep;
  ASel := Copy(S.Sel, 0, Length(S.Sel));
  ASheet := S.Sheet;
end;

{ ===========================================================================
  TUndoManager.Push  (procedure)
  Parameters:
    const ACaption: String - name of the action
    const ASel: TIntArray - ids of the selected objects
    ASheet: Integer - current sheet index
  Notes:
    Takes a snapshot immediately and puts it on the undo stack (the one-step form of BeginChange
    plus CommitChange). Call before making a change.
  =========================================================================== }
procedure TUndoManager.Push(const ACaption: String; const ASel: TIntArray; ASheet: Integer);
var
  N: Integer;
begin
  if FDesign = nil then
    Exit;
  N := Length(FUndo);
  if N >= FMaxDepth then
  begin
    for N := 1 to High(FUndo) do FUndo[N - 1] := FUndo[N];
    SetLength(FUndo, Length(FUndo) - 1);
  end;
  SetLength(FUndo, Length(FUndo) + 1);
  FUndo[High(FUndo)] := Take(ACaption, ASel, ASheet);
  SetLength(FRedo, 0);
end;

{ ===========================================================================
  TUndoManager.CanUndo  (function)
  Parameters:  none
  Returns:
    Boolean - True if the undo stack is not empty
  Notes:
    Whether there is anything to undo.
  =========================================================================== }
function TUndoManager.CanUndo: Boolean; begin Result := Length(FUndo) > 0; end;

{ ===========================================================================
  TUndoManager.CanRedo  (function)
  Parameters:  none
  Returns:
    Boolean - True if the redo stack is not empty
  Notes:
    Whether there is anything to redo.
  =========================================================================== }
function TUndoManager.CanRedo: Boolean; begin Result := Length(FRedo) > 0; end;

{ ===========================================================================
  TUndoManager.UndoCount  (function)
  Parameters:  none
  Returns:
    Integer - size of the undo stack
  Notes:
    How many steps can be undone.
  =========================================================================== }
function TUndoManager.UndoCount: Integer; begin Result := Length(FUndo); end;

{ ===========================================================================
  TUndoManager.RedoCount  (function)
  Parameters:  none
  Returns:
    Integer - size of the redo stack
  Notes:
    How many steps can be redone.
  =========================================================================== }
function TUndoManager.RedoCount: Integer; begin Result := Length(FRedo); end;

{ ===========================================================================
  TUndoManager.UndoCaption  (function)
  Parameters:  none
  Returns:
    String - the caption, or empty when nothing can be undone
  Notes:
    The name of the action Undo would reverse, for a menu or hint.
  =========================================================================== }
function TUndoManager.UndoCaption: String;
begin
  if CanUndo then
    Result := FUndo[High(FUndo)].Caption
  else
    Result := '';
end;

{ ===========================================================================
  TUndoManager.RedoCaption  (function)
  Parameters:  none
  Returns:
    String - the caption, or empty when nothing can be redone
  Notes:
    The name of the action Redo would repeat, for a menu or hint.
  =========================================================================== }
function TUndoManager.RedoCaption: String;
begin
  if CanRedo then
    Result := FRedo[High(FRedo)].Caption
  else
    Result := '';
end;

{ ===========================================================================
  TUndoManager.Undo  (function)
  Parameters:
    const CurSel: TIntArray - ids selected now (kept for Redo)
    CurSheet: Integer - sheet shown now (kept for Redo)
    out ASel: TIntArray - set to the ids to select after the undo
    out ASheet: Integer - set to the sheet to show after the undo
  Returns:
    Boolean - True if a step was undone
  Notes:
    Undoes the last step: saves the current state on the redo stack, then restores the previous
    snapshot. Gives back what to select and which sheet to show.
  =========================================================================== }
function TUndoManager.Undo(const CurSel: TIntArray; CurSheet: Integer; out ASel: TIntArray; out ASheet: Integer): Boolean;
var
  S: TSnap;
begin
  Result := CanUndo;
  SetLength(ASel, 0);
  ASheet := CurSheet;
  if not Result then
    Exit;
  S := FUndo[High(FUndo)];
  SetLength(FUndo, Length(FUndo) - 1);
  SetLength(FRedo, Length(FRedo) + 1);
  FRedo[High(FRedo)] := Take(S.Caption, CurSel, CurSheet);   // so Redo can come back here
  Restore(S, ASel, ASheet);
end;

{ ===========================================================================
  TUndoManager.Redo  (function)
  Parameters:
    const CurSel: TIntArray - ids selected now
    CurSheet: Integer - sheet shown now
    out ASel: TIntArray - set to the ids to select afterwards
    out ASheet: Integer - set to the sheet to show afterwards
  Returns:
    Boolean - True if a step was redone
  Notes:
    Repeats the last undone step: saves the current state on the undo stack, then restores the
    redo snapshot.
  =========================================================================== }
function TUndoManager.Redo(const CurSel: TIntArray; CurSheet: Integer; out ASel: TIntArray; out ASheet: Integer): Boolean;
var
  S: TSnap;
begin
  Result := CanRedo;
  SetLength(ASel, 0);
  ASheet := CurSheet;
  if not Result then
    Exit;
  S := FRedo[High(FRedo)];
  SetLength(FRedo, Length(FRedo) - 1);
  SetLength(FUndo, Length(FUndo) + 1);
  FUndo[High(FUndo)] := Take(S.Caption, CurSel, CurSheet);
  Restore(S, ASel, ASheet);
end;

end.
