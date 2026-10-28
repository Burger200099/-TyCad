{ UPartData - what a design keeps of a part from a parts library (docs/parts_design_storage.md), and the fit check that needs only that.

  A design must open and be checked without the parts library, so the .dsn holds copies:
    - on the symbol (the generic part): its GUID and the library's, its name and class, and its REQUIRED ratings (NEED);
    - on each placed part: the chosen product (GUID, manufacturer, model number) and the product's ratings (HAVE).
  CheckFit compares them by the same rules as the views ProductFit and ProductFitSummary of docs/parts_schema.sql (tests/run_partsfit.py checks the two give the same
  verdicts): for every requirement the product rating with the same quantity and condition, on the same object (by name; a rating on 'kind:X' covers every object that
  is of kind X) is looked up; the value compared is the Max, else the Typ, else the Min; a quantity is judged 'min' (the product must have at least as much), 'max' (at
  most) or 'match' (equal). Bigger than needed is fine; undersized, missing and mismatched are reported.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UPartData;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, UXMLWriter, UXMLReader;

type
  { one rating: a requirement of a part (NEED) or a rating of a product (HAVE) }
  TRatingData = record
    Quantity, Unit_, Condition, Sense: String;     // Sense: min, max or match (a requirement carries it, so the check needs no library)
    AppliesTo: String;                             // requirement: the object's name, '' = the whole part; product rating: '', an object's name, or 'kind:Contact'
    Kinds: String;                                 // requirement: the kinds of the object, its own and its ancestors, comma separated ('Contact,PassiveObject,PartObject')
    HasMin, HasTyp, HasMax: Boolean;
    Min, Typ, Max: Double;
  end;
  TRatingDataArray = array of TRatingData;

  TFitStatus = (fsOk, fsOversized, fsUndersized, fsMissing, fsMismatch);

  TFitLine = record
    Need: TRatingData;
    NeedValue, HaveValue: Double;
    HaveFound: Boolean;
    Status: TFitStatus;
  end;
  TFitLineArray = array of TFitLine;

  { what a symbol (the generic part) keeps }
  TPartCopy = record
    UID, LibraryUID, Name, ClassName: String;
    Needs: TRatingDataArray;
    function IsEmpty: Boolean;
  end;

  { what a placed part keeps of its chosen product }
  TProductChoice = record
    UID, Manufacturer, MPN: String;               // UID '' for a product typed by hand (it is in no library)
    Haves: TRatingDataArray;
    function IsEmpty: Boolean;
  end;

{ the value a rating is judged by: Max, else Typ, else Min (0 when none is given) }
function RatingValue(const R: TRatingData): Double;
function CheckFit(const Needs, Haves: TRatingDataArray): TFitLineArray;
{ does_not_fit (anything undersized, missing or mismatched), fits_oversized, fits, or no_requirements }
function FitVerdict(const Lines: TFitLineArray): String;
function FitStatusName(S: TFitStatus): String;
{ the verdict as a person reads it: 'Fits', 'Fits (oversized)', 'Does not fit: 1 undersized, 2 missing', 'No requirements' }
function FitSummaryText(const Lines: TFitLineArray): String;
{ one line for each requirement that is not simply met: quantity, where, need and have }
function FitDetailText(const Lines: TFitLineArray): String;

procedure SaveRatingXml(W: TXMLWriter; const Tag: String; const R: TRatingData);
function LoadRatingXml(R: TXMLReader): TRatingData;
procedure SavePartCopyXml(W: TXMLWriter; const P: TPartCopy);
{ reads the PART element the reader is on }
procedure LoadPartCopyXml(R: TXMLReader; out P: TPartCopy);
procedure SaveProductXml(W: TXMLWriter; const P: TProductChoice);
procedure LoadProductXml(R: TXMLReader; out P: TProductChoice);

implementation


uses UStrings;

function TPartCopy.IsEmpty: Boolean;
begin
  Result := (UID = '') and (Name = '') and (Length(Needs) = 0);
end;

function TProductChoice.IsEmpty: Boolean;
begin
  Result := (UID = '') and (Manufacturer = '') and (MPN = '') and (Length(Haves) = 0);
end;

{ ===========================================================================
  RatingValue  (function)
  Parameters:
    const R: TRatingData - the rating
  Returns:
    Double - the value it is judged by
  Notes:
    Max when given, else Typ, else Min; 0 when none is given.
  =========================================================================== }
function RatingValue(const R: TRatingData): Double;
begin
  if R.HasMax then
    Result := R.Max
  else if R.HasTyp then
    Result := R.Typ
  else if R.HasMin then
    Result := R.Min
  else
    Result := 0;
end;

{ ===========================================================================
  KindMatches  (function)
  Parameters:
    const AppliesTo: String - the AppliesTo of a product rating
    const Need: TRatingData - the requirement
  Returns:
    Integer - 2 when it names the requirement's object, 1 when it is 'kind:X' for a kind of that object, 0 when it does not apply
  Notes:
    A requirement on the whole part (no object) is only met by a product rating on the whole product.
  =========================================================================== }
function KindMatches(const AppliesTo: String; const Need: TRatingData): Integer;
var
  L: TStringList;
begin
  Result := 0;
  if Need.AppliesTo = '' then
  begin
    if AppliesTo = '' then
      Result := 2;
    Exit;
  end;
  if AppliesTo = '' then
    Exit;
  if AppliesTo = Need.AppliesTo then
    Exit(2);
  if Copy(AppliesTo, 1, 5) = 'kind:' then
  begin
    L := TStringList.Create;
    try
      L.Delimiter := ',';
      L.StrictDelimiter := True;
      L.DelimitedText := Need.Kinds;
      if L.IndexOf(Copy(AppliesTo, 6, MaxInt)) >= 0 then
        Result := 1;
    finally
      L.Free;
    end;
  end;
end;

{ ===========================================================================
  CheckFit  (function)
  Parameters:
    const Needs: TRatingDataArray - the requirements of the generic part
    const Haves: TRatingDataArray - the ratings of the chosen product
  Returns:
    TFitLineArray - one line per requirement, in the order of Needs
  Notes:
    The rules are those at the top of the unit. A requirement that gives no value at all is ok (nothing is asked). When several product ratings apply, the one on
    the object's own name wins over one on its kind; of equals the first is used.
  =========================================================================== }
function CheckFit(const Needs, Haves: TRatingDataArray): TFitLineArray;
var
  i, j, Best, Rank: Integer;
  Nv, Hv: Double;
begin
  SetLength(Result, Length(Needs));
  for i := 0 to High(Needs) do
  begin
    Result[i].Need := Needs[i];
    Nv := RatingValue(Needs[i]);
    Result[i].NeedValue := Nv;
    Best := -1;
    Rank := 0;
    for j := 0 to High(Haves) do
      if (Haves[j].Quantity = Needs[i].Quantity) and (Haves[j].Condition = Needs[i].Condition) and (KindMatches(Haves[j].AppliesTo, Needs[i]) > Rank) then
      begin
        Best := j;
        Rank := KindMatches(Haves[j].AppliesTo, Needs[i]);
      end;
    Result[i].HaveFound := Best >= 0;
    if Best < 0 then
    begin
      Result[i].HaveValue := 0;
      Result[i].Status := fsMissing;
      Continue;
    end;
    Hv := RatingValue(Haves[Best]);
    Result[i].HaveValue := Hv;
    if Needs[i].Sense = 'match' then
    begin
      if Hv = Nv then
        Result[i].Status := fsOk
      else
        Result[i].Status := fsMismatch;
    end
    else if Hv = Nv then
      Result[i].Status := fsOk
    else if ((Needs[i].Sense = 'min') and (Hv > Nv)) or ((Needs[i].Sense = 'max') and (Hv < Nv)) then
      Result[i].Status := fsOversized
    else
      Result[i].Status := fsUndersized;
  end;
end;

function FitStatusName(S: TFitStatus): String;
begin
  case S of
    fsOk: Result := 'ok';
    fsOversized: Result := 'oversized';
    fsUndersized: Result := 'undersized';
    fsMissing: Result := 'missing';
  else
    Result := 'mismatch';
  end;
end;

{ ===========================================================================
  FitVerdict  (function)
  Parameters:
    const Lines: TFitLineArray - the result of CheckFit
  Returns:
    String - does_not_fit, fits_oversized, fits or no_requirements
  Notes:
    Anything undersized, missing or mismatched does not fit; oversized only is acceptable.
  =========================================================================== }
function FitVerdict(const Lines: TFitLineArray): String;
var
  i: Integer;
  Over: Boolean;
begin
  if Length(Lines) = 0 then
    Exit('no_requirements');
  Over := False;
  for i := 0 to High(Lines) do
    case Lines[i].Status of
      fsUndersized, fsMissing, fsMismatch: Exit('does_not_fit');
      fsOversized: Over := True;
    end;
  if Over then
    Result := 'fits_oversized'
  else
    Result := 'fits';
end;

{ ===========================================================================
  SaveRatingXml  (procedure)
  Parameters:
    W: TXMLWriter - the writer
    const Tag: String - NEED or HAVE
    const R: TRatingData - the rating
  Notes:
    Writes one rating as an element with attributes; only what is set is written.
  =========================================================================== }
procedure SaveRatingXml(W: TXMLWriter; const Tag: String; const R: TRatingData);
begin
  W.AddTag(Tag);
  W.AddAttribute('quantity', R.Quantity);
  if R.AppliesTo <> '' then
    W.AddAttribute('on', R.AppliesTo);
  if R.Kinds <> '' then
    W.AddAttribute('kinds', R.Kinds);
  if R.Sense <> '' then
    W.AddAttribute('sense', R.Sense);
  if R.HasMin then
    W.AddAttribute('min', R.Min);
  if R.HasTyp then
    W.AddAttribute('typ', R.Typ);
  if R.HasMax then
    W.AddAttribute('max', R.Max);
  W.AddAttribute('unit', R.Unit_);
  if R.Condition <> '' then
    W.AddAttribute('condition', R.Condition);
  W.CloseTag;
end;

{ ===========================================================================
  LoadRatingXml  (function)
  Parameters:
    R: TXMLReader - the reader, on a NEED or HAVE element
  Returns:
    TRatingData - the rating
  Notes:
    Reads the attributes SaveRatingXml wrote; a missing one is empty.
  =========================================================================== }
function LoadRatingXml(R: TXMLReader): TRatingData;
begin
  Result.Quantity := ''; Result.Unit_ := ''; Result.Condition := ''; Result.Sense := ''; Result.AppliesTo := ''; Result.Kinds := '';
  Result.Min := 0; Result.Typ := 0; Result.Max := 0;
  R.GetAttribute('quantity', Result.Quantity);
  R.GetAttribute('on', Result.AppliesTo);
  R.GetAttribute('kinds', Result.Kinds);
  R.GetAttribute('sense', Result.Sense);
  R.GetAttribute('unit', Result.Unit_);
  R.GetAttribute('condition', Result.Condition);
  Result.HasMin := R.GetAttribute('min', Result.Min);
  Result.HasTyp := R.GetAttribute('typ', Result.Typ);
  Result.HasMax := R.GetAttribute('max', Result.Max);
end;

procedure SavePartCopyXml(W: TXMLWriter; const P: TPartCopy);
var
  i: Integer;
begin
  W.AddTag('PART');
  W.AddAttribute('uid', P.UID);
  W.AddAttribute('library', P.LibraryUID);
  W.AddAttribute('name', P.Name);
  W.AddAttribute('class', P.ClassName);
  for i := 0 to High(P.Needs) do
    SaveRatingXml(W, 'NEED', P.Needs[i]);
  W.CloseTag;
end;

procedure LoadPartCopyXml(R: TXMLReader; out P: TPartCopy);
var
  Tag: String;
begin
  P.UID := ''; P.LibraryUID := ''; P.Name := ''; P.ClassName := '';
  SetLength(P.Needs, 0);
  R.GetAttribute('uid', P.UID);
  R.GetAttribute('library', P.LibraryUID);
  R.GetAttribute('name', P.Name);
  R.GetAttribute('class', P.ClassName);
  R.IntoTag;
  while R.NextTag(Tag) do
    if Tag = 'NEED' then
    begin
      SetLength(P.Needs, Length(P.Needs) + 1);
      P.Needs[High(P.Needs)] := LoadRatingXml(R);
    end;
  R.OutOfTag;
end;

procedure SaveProductXml(W: TXMLWriter; const P: TProductChoice);
var
  i: Integer;
begin
  W.AddTag('PRODUCT');
  W.AddAttribute('uid', P.UID);
  W.AddAttribute('manufacturer', P.Manufacturer);
  W.AddAttribute('mpn', P.MPN);
  for i := 0 to High(P.Haves) do
    SaveRatingXml(W, 'HAVE', P.Haves[i]);
  W.CloseTag;
end;

procedure LoadProductXml(R: TXMLReader; out P: TProductChoice);
var
  Tag: String;
begin
  P.UID := ''; P.Manufacturer := ''; P.MPN := '';
  SetLength(P.Haves, 0);
  R.GetAttribute('uid', P.UID);
  R.GetAttribute('manufacturer', P.Manufacturer);
  R.GetAttribute('mpn', P.MPN);
  R.IntoTag;
  while R.NextTag(Tag) do
    if Tag = 'HAVE' then
    begin
      SetLength(P.Haves, Length(P.Haves) + 1);
      P.Haves[High(P.Haves)] := LoadRatingXml(R);
    end;
  R.OutOfTag;
end;


{ ===========================================================================
  FitSummaryText  (function)
  Parameters:
    Lines: TFitLineArray - the result of CheckFit
  Returns:
    String - the verdict in words
  Notes:
    'No requirements' when there is nothing to judge, 'Fits', 'Fits (oversized)', or 'Does not fit: ' followed by the counts of undersized, missing and mismatched lines (those
    that are not zero).
  =========================================================================== }
function FitSummaryText(const Lines: TFitLineArray): String;
var
  i, U, M, X: Integer;
  V: String;
begin
  V := FitVerdict(Lines);
  if V = 'no_requirements' then
    Exit(rsNoRequirements);
  if V = 'fits' then
    Exit(rsFits);
  if V = 'fits_oversized' then
    Exit(rsFitsOversized);
  U := 0; M := 0; X := 0;
  for i := 0 to High(Lines) do
    case Lines[i].Status of
      fsUndersized: Inc(U);
      fsMissing: Inc(M);
      fsMismatch: Inc(X);
    end;
  Result := rsDoesNotFit;
  if U > 0 then
    Result := Format(rsUndersized, [Result, U]);
  if M > 0 then
    Result := Format(rsMissing, [Result, M]);
  if X > 0 then
    Result := Format(rsMismatched, [Result, X]);
  Result := Copy(Result, 1, Length(Result) - 1);
end;

{ ===========================================================================
  FitDetailText  (function)
  Parameters:
    Lines: TFitLineArray - the result of CheckFit
  Returns:
    String - the lines that are not met (or oversized), one per line of text
  Notes:
    Each is 'quantity (where): status, need N, have M' ('have -' when the product gives none). Empty when everything fits exactly.
  =========================================================================== }
function FitDetailText(const Lines: TFitLineArray): String;
var
  i: Integer;
  S, Where: String;
begin
  Result := '';
  for i := 0 to High(Lines) do
    if Lines[i].Status <> fsOk then
    begin
      Where := Lines[i].Need.AppliesTo;
      if Where <> '' then
        Where := ' (' + Where + ')';
      if Lines[i].HaveFound then
        S := FloatToStr(Lines[i].HaveValue)
      else
        S := '-';
      if Result <> '' then
        Result := Result + LineEnding;
      Result := Result + Lines[i].Need.Quantity + Where + ': ' + FitStatusName(Lines[i].Status) + ', need ' + FloatToStr(Lines[i].NeedValue) + ', have ' + S;
    end;
end;

end.
