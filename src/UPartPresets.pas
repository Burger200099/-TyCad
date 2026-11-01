// SPDX-License-Identifier: LGPL-2.1-or-later
unit UPartPresets;

{$mode ObjFPC}{$H+}

{ Presets of the Add Part wizard (parts plan step 7): a relay with 3 NO + 1 NC, a 3 pole contactor with auxiliary contacts, a timer relay, a breaker ... Each preset names the
  class of the part, its reference letters and which counts the wizard asks for; BuildPresetPart makes the part and its coil, poles and contacts (with the terminal numbers of the
  usual practice: A1 / A2 for the coil, 1/2 3/4 5/6 for main poles, 13/14 21/22 ... for auxiliary contacts) in the library, or nothing when anything is refused.

  The presets are data (PartPresets), so adding one is a line there. Licence: LGPL 2.1 or later, as the rest of this port. }

interface

uses
  Classes, SysUtils, UPartsDb;

type
  TPresetParams = record
    Poles: Integer;       // main poles (contactor, breaker), each with a normally open contact
    NO, NC: Integer;      // normally open / closed (auxiliary) contacts
    Coil: Boolean;        // a coil is made (a preset with no coil never makes one)
    Delay: String;        // none, on-delay, off-delay (for the contacts of a timer relay)
    DelaySecs: Double;
  end;

  TPartPreset = record
    Key, Title: String;           // the Title is what the wizard lists
    ClassName: String;            // '' = the person chooses the class
    RefPrefix: String;
    AskPoles, AskNO, AskNC, AskCoil, AskDelay: Boolean;      // which entries the preset uses
    Defaults: TPresetParams;
    Hint: String;
  end;
  TPartPresetArray = array of TPartPreset;

{ every preset, in the order the wizard lists them (the last is the blank one) }
function PartPresets: TPartPresetArray;
function PresetOfKey(const AKey: String; out APreset: TPartPreset): Boolean;
{ the name a part of the preset with these entries gets: 'Contactor 3-pole + 1 NO + 1 NC' }
function PresetName(const APreset: TPartPreset; const P: TPresetParams): String;
{ what the part will have, in words: 'coil, 3 poles, 1 NO + 1 NC auxiliary contacts' }
function PresetSummary(const APreset: TPartPreset; const P: TPresetParams): String;
{ Makes the part (class of the preset, or AClassID when the preset has none) with its objects as one piece of work: when anything is refused the part is deleted again and the
  EPartsError goes on. Returns the part's PartID. }
function BuildPresetPart(ALib: TPartsLibrary; const APreset: TPartPreset; const P: TPresetParams; const AName, ARef, ADescription: String; AClassID: Int64): Int64;
{ the ClassID of the class with this name in the library, 0 when it has none }
function ClassIDOfName(ALib: TPartsLibrary; const AName: String): Int64;

implementation

uses UStrings;

function Pre(const AKey, ATitle, AClass, ARef: String; APoles, ANO, ANC, ACoil, ADelay: Boolean; const D: TPresetParams; const AHint: String): TPartPreset;
begin
  Result.Key := AKey; Result.Title := ATitle; Result.ClassName := AClass; Result.RefPrefix := ARef;
  Result.AskPoles := APoles; Result.AskNO := ANO; Result.AskNC := ANC; Result.AskCoil := ACoil; Result.AskDelay := ADelay;
  Result.Defaults := D; Result.Hint := AHint;
end;

function Prm(APoles, ANO, ANC: Integer; ACoil: Boolean; const ADelay: String; ASecs: Double): TPresetParams;
begin
  Result.Poles := APoles; Result.NO := ANO; Result.NC := ANC; Result.Coil := ACoil; Result.Delay := ADelay; Result.DelaySecs := ASecs;
end;

function PartPresets: TPartPresetArray;
begin
  SetLength(Result, 6);
  Result[0] := Pre('relay', rsPresetRelay, 'Relay', 'K', False, True, True, True, False, Prm(0, 2, 2, True, 'none', 0), rsPresetRelayHint);
  Result[1] := Pre('contactor', rsPresetContactor, 'Contactor', 'K', True, True, True, True, False, Prm(3, 1, 1, True, 'none', 0), rsPresetContactorHint);
  Result[2] := Pre('timer', rsPresetTimer, 'Relay', 'K', False, True, True, True, True, Prm(0, 1, 1, True, 'on-delay', 5), rsPresetTimerHint);
  Result[3] := Pre('breaker', rsPresetBreaker, 'Breaker', 'Q', True, False, False, False, False, Prm(3, 0, 0, False, 'none', 0), rsPresetBreakerHint);
  Result[4] := Pre('terminal', rsPresetTerminal, 'TerminalBlock', 'X', False, False, False, False, False, Prm(0, 0, 0, False, 'none', 0), rsPresetTerminalHint);
  Result[5] := Pre('other', rsPresetOther, '', '', False, False, False, False, False, Prm(0, 0, 0, False, 'none', 0), rsPresetOtherHint);
end;

function PresetOfKey(const AKey: String; out APreset: TPartPreset): Boolean;
var
  A: TPartPresetArray;
  i: Integer;
begin
  Result := False;
  A := PartPresets;
  for i := 0 to High(A) do
    if SameText(A[i].Key, AKey) then
    begin
      APreset := A[i];
      Exit(True);
    end;
end;

function Contacts(NO, NC: Integer): String;
begin
  Result := '';
  if NO > 0 then
    Result := IntToStr(NO) + ' NO';
  if NC > 0 then
  begin
    if Result <> '' then
      Result := Result + ' + ';
    Result := Result + IntToStr(NC) + ' NC';
  end;
end;

function PresetName(const APreset: TPartPreset; const P: TPresetParams): String;
var
  C: String;
begin
  Result := '';
  C := Contacts(P.NO, P.NC);
  if (APreset.Key = 'relay') then
  begin
    Result := 'Relay';
    if C <> '' then
      Result := Result + ' ' + C;
  end
  else if APreset.Key = 'contactor' then
  begin
    Result := 'Contactor ' + IntToStr(P.Poles) + '-pole';
    if C <> '' then
      Result := Result + ' + ' + C;
  end
  else if APreset.Key = 'timer' then
  begin
    if P.Delay = 'off-delay' then
      Result := 'Off-delay relay'
    else
      Result := 'On-delay relay';
    if C <> '' then
      Result := Result + ' ' + C;
  end
  else if APreset.Key = 'breaker' then
    Result := 'Breaker ' + IntToStr(P.Poles) + '-pole'
  else if APreset.Key = 'terminal' then
    Result := 'Terminal block';
end;

function PresetSummary(const APreset: TPartPreset; const P: TPresetParams): String;
var
  C: String;

  procedure Add(const S: String);
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + S;
  end;

begin
  Result := '';
  if APreset.AskCoil and P.Coil then
    Add(rsCoilWord);
  if APreset.AskPoles and (P.Poles > 0) then
    Add(Format(rsNPolesWord, [P.Poles]));
  C := Contacts(P.NO, P.NC);
  if APreset.AskNO or APreset.AskNC then
    if C <> '' then
    begin
      if APreset.AskPoles then
        Add(C + ' ' + rsAuxiliaryWord)
      else
        Add(C);
    end;
  if APreset.AskDelay and (P.Delay <> 'none') and (C <> '') then
    Add(Format(rsDelayedWord, [P.Delay, P.DelaySecs]));
  if Result = '' then
    Result := rsNoObjectsWord;
end;

function ClassIDOfName(ALib: TPartsLibrary; const AName: String): Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to ALib.ClassCount - 1 do
    if SameText(ALib.Classes[i].Name, AName) then
      Exit(ALib.Classes[i].ID);
end;

function BuildPresetPart(ALib: TPartsLibrary; const APreset: TPartPreset; const P: TPresetParams; const AName, ARef, ADescription: String; AClassID: Int64): Int64;
var
  ClassID, PartID, CoilKind: Int64;
  i, Seq: Integer;
  Pole: Int64;
  Delay: String;
  Secs: Double;

  procedure SetDesignator(PoleObj: Int64; const D: String);
  var
    F: TSwitchRowArray;
    q: Integer;
  begin
    F := ALib.SwitchRows(PartID);
    for q := 0 to High(F) do
      if (F[q].ParentID = PoleObj) and (F[q].Kind = 'Contact') then
        ALib.SetSwitchContact(F[q].ID, D, F[q].Form, F[q].Delay, F[q].DelaySecs);
  end;

begin
  if APreset.ClassName <> '' then
  begin
    ClassID := ClassIDOfName(ALib, APreset.ClassName);
    if ClassID = 0 then
      raise EPartsError.Create(rsChooseAClassForThe2);
  end
  else
    ClassID := AClassID;
  PartID := ALib.AddPart(AName, ClassID, ARef, ADescription);
  Result := PartID;
  try
    if APreset.AskCoil and P.Coil then
    begin
      CoilKind := ALib.KindIDOfName('Coil');
      ALib.AddObject(PartID, 0, CoilKind, 'Coil', 'A1/A2', '', 10);
    end;
    Seq := 0;
    if APreset.AskPoles then
      for i := 1 to P.Poles do
      begin
        Pole := ALib.AddSwitchPole(PartID, 'NO', 'none', 0);
        SetDesignator(Pole, IntToStr(2 * i - 1) + '/' + IntToStr(2 * i));
      end;
    Delay := 'none'; Secs := 0;
    if APreset.AskDelay then
    begin
      Delay := P.Delay; Secs := P.DelaySecs;
    end;
    if APreset.AskNO then
      for i := 1 to P.NO do
      begin
        Inc(Seq);
        Pole := ALib.AddSwitchPole(PartID, 'NO', Delay, Secs);
        SetDesignator(Pole, IntToStr(Seq) + '3/' + IntToStr(Seq) + '4');
      end;
    if APreset.AskNC then
      for i := 1 to P.NC do
      begin
        Inc(Seq);
        Pole := ALib.AddSwitchPole(PartID, 'NC', Delay, Secs);
        SetDesignator(Pole, IntToStr(Seq) + '1/' + IntToStr(Seq) + '2');
      end;
  except
    ALib.DeletePart(PartID);
    raise;
  end;
end;

end.
