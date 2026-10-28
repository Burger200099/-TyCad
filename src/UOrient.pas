// SPDX-License-Identifier: LGPL-2.1-or-later
{ The way up of a picture: turned by quarter turns and flipped left to right, or not.

  A picture keeps its own orientation, because the object's two corners only say where the picture is, not which way up it is. Turning or flipping a selection that holds the picture
  (Rotate left, Rotate right, Flip) moves its corners as it moves everything else, and the picture's orientation is changed by the same operation, so that what is shown inside the
  corners is turned with them. The same goes for a picture that is part of a symbol: the symbol's own turn and flip apply to it.

  An orientation is a 2 x 2 matrix of 0, 1 and -1 (x' = A x + B y, y' = C x + D y, with y pointing down the screen) that says where the picture's directions go: (1,0), along the picture,
  and (0,1), down it. The identity is upright. The three operations of the editor are matrices too (CDrawingObject::DoRotate: left is (x,y) -> (y,-x), right is (x,y) -> (-y,x), flip
  is (x,y) -> (-x,y)), and an operation is applied by multiplying: the new orientation is the operation's matrix times the old one. Every orientation is a flip (or none) followed by
  0 to 3 turns to the right, which is how the file keeps it (the attributes rot and mirror).

  A picture drawn in an orientation is an exact rearrangement of its pixels, each one moved and none lost or blurred (the size on the screen is the box's, as before).

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit UOrient;

{$mode ObjFPC}{$H+}

interface

type
  TOrient = record
    A, B, C, D: Integer;     // x' = A * x + B * y ; y' = C * x + D * y
  end;

const
  { the operations of the editor, as in RotatePointAbout }
  OP_LEFT = 2;
  OP_RIGHT = 3;
  OP_FLIP = 4;

{ the upright picture }
function OrientIdentity: TOrient;
{ the matrix of Rotate left (OP_LEFT), Rotate right (OP_RIGHT) or Flip (OP_FLIP); the identity for anything else }
function OrientOfOp(Op: Integer): TOrient;
{ Second after First }
function OrientMul(const Second, First: TOrient): TOrient;
{ the way back (the transpose: these matrices turn without stretching) }
function OrientInverse(const O: TOrient): TOrient;
function OrientSame(const P, Q: TOrient): Boolean;
function OrientIsIdentity(const O: TOrient): Boolean;
{ does it turn the picture a quarter (so that its width and height change places)? }
function OrientSwapsAxes(const O: TOrient): Boolean;
{ a flip (or none) and then Turns turns to the right (0 to 3) }
function OrientFromTurns(Turns: Integer; Mirror: Boolean): TOrient;
{ the other way; False if the matrix is not one of the eight orientations }
function OrientToTurns(const O: TOrient; out Turns: Integer; out Mirror: Boolean): Boolean;
{ the eight orientations numbered 0 to 7 (turns + 4 if flipped), for keeping a picture drawn in each; -1 if the matrix is none of them }
function OrientIndex(const O: TOrient): Integer;
{ the size of a W x H picture once it is in the orientation }
procedure OrientedSize(const O: TOrient; W, H: Integer; out OutW, OutH: Integer);
{ the pixel of a W x H picture that goes to pixel (X, Y) of the oriented picture (whose size is OrientedSize) }
procedure OrientedSource(const O: TOrient; X, Y, W, H: Integer; out SrcX, SrcY: Integer);

implementation

{ ===========================================================================
  OrientIdentity  (function)
  Parameters:  none
  Returns:
    TOrient - the identity orientation
  Notes:
    The upright picture: the identity matrix.
  =========================================================================== }
function OrientIdentity: TOrient;
begin
  Result.A := 1; Result.B := 0; Result.C := 0; Result.D := 1;
end;

{ ===========================================================================
  OrientOfOp  (function)
  Parameters:
    Op: Integer - OP_LEFT, OP_RIGHT or OP_FLIP
  Returns:
    TOrient - the matrix
  Notes:
    The matrix of Rotate left, Rotate right or Flip: the same movement RotatePointAbout gives a
    point about the origin. Any other operation gives the identity.
  =========================================================================== }
function OrientOfOp(Op: Integer): TOrient;
begin
  Result := OrientIdentity;
  case Op of
    OP_LEFT:  begin
      Result.A := 0;
      Result.B := 1;
      Result.C := -1;
      Result.D := 0;
    end;     // (x, y) -> (y, -x)
    OP_RIGHT: begin
      Result.A := 0;
      Result.B := -1;
      Result.C := 1;
      Result.D := 0;
    end;     // (x, y) -> (-y, x)
    OP_FLIP:  begin
      Result.A := -1;
      Result.B := 0;
      Result.C := 0;
      Result.D := 1;
    end;     // (x, y) -> (-x, y)
  end;
end;

{ ===========================================================================
  OrientMul  (function)
  Parameters:
    const Second: TOrient - the operation done last
    const First: TOrient - the operation done first
  Returns:
    TOrient - the combined orientation
  Notes:
    Two orientations one after the other: the matrix of doing First and then Second.
  =========================================================================== }
function OrientMul(const Second, First: TOrient): TOrient;
begin
  Result.A := Second.A * First.A + Second.B * First.C;
  Result.B := Second.A * First.B + Second.B * First.D;
  Result.C := Second.C * First.A + Second.D * First.C;
  Result.D := Second.C * First.B + Second.D * First.D;
end;

{ ===========================================================================
  OrientInverse  (function)
  Parameters:
    const O: TOrient - an orientation
  Returns:
    TOrient - the inverse
  Notes:
    The way back from an orientation (its transpose: these matrices turn and flip without
    stretching).
  =========================================================================== }
function OrientInverse(const O: TOrient): TOrient;
begin
  Result.A := O.A; Result.B := O.C; Result.C := O.B; Result.D := O.D;
end;

{ ===========================================================================
  OrientSame  (function)
  Parameters:
    const P: TOrient - an orientation
    const Q: TOrient - another
  Returns:
    Boolean - True if they are
  Notes:
    Whether two orientations are the same.
  =========================================================================== }
function OrientSame(const P, Q: TOrient): Boolean;
begin
  Result := (P.A = Q.A) and (P.B = Q.B) and (P.C = Q.C) and (P.D = Q.D);
end;

{ ===========================================================================
  OrientIsIdentity  (function)
  Parameters:
    const O: TOrient - an orientation
  Returns:
    Boolean - True if it is
  Notes:
    Whether an orientation is the upright one.
  =========================================================================== }
function OrientIsIdentity(const O: TOrient): Boolean;
begin
  Result := OrientSame(O, OrientIdentity);
end;

{ ===========================================================================
  OrientSwapsAxes  (function)
  Parameters:
    const O: TOrient - an orientation
  Returns:
    Boolean - True if it does
  Notes:
    Whether the orientation turns the picture a quarter, so that its width and height change
    places.
  =========================================================================== }
function OrientSwapsAxes(const O: TOrient): Boolean;
begin
  Result := O.B <> 0;
end;

{ ===========================================================================
  OrientFromTurns  (function)
  Parameters:
    Turns: Integer - how many quarter turns to the right (taken round to 0 to 3)
    Mirror: Boolean - flipped before turning
  Returns:
    TOrient - the orientation
  Notes:
    The orientation that is a flip left to right (or none) followed by some quarter turns to the
    right.
  =========================================================================== }
function OrientFromTurns(Turns: Integer; Mirror: Boolean): TOrient;
var
  i: Integer;
begin
  if Mirror then
    Result := OrientOfOp(OP_FLIP)
  else
    Result := OrientIdentity;
  for i := 1 to ((Turns mod 4) + 4) mod 4 do Result := OrientMul(OrientOfOp(OP_RIGHT), Result);
end;

{ ===========================================================================
  OrientToTurns  (function)
  Parameters:
    const O: TOrient - an orientation
    out Turns: Integer - receives the quarter turns to the right, 0 to 3
    out Mirror: Boolean - receives whether it is flipped first
  Returns:
    Boolean - False if the matrix is none of the eight orientations
  Notes:
    Takes an orientation apart into the flip (or none) and the quarter turns to the right that
    make it, which is how the file keeps it.
  =========================================================================== }
function OrientToTurns(const O: TOrient; out Turns: Integer; out Mirror: Boolean): Boolean;
var
  T: Integer;
  M: Boolean;
begin
  Turns := 0; Mirror := False;
  for M := False to True do
    for T := 0 to 3 do
      if OrientSame(O, OrientFromTurns(T, M)) then
      begin
        Turns := T; Mirror := M;
        Exit(True);
      end;
  Result := False;
end;

{ ===========================================================================
  OrientIndex  (function)
  Parameters:
    const O: TOrient - an orientation
  Returns:
    Integer - the number, or -1 if the matrix is none of the eight
  Notes:
    The orientation as a number 0 to 7 (the quarter turns, plus 4 if flipped), for keeping a
    picture drawn in each of them.
  =========================================================================== }
function OrientIndex(const O: TOrient): Integer;
var
  T: Integer;
  M: Boolean;
begin
  if not OrientToTurns(O, T, M) then
    Exit(-1);
  Result := T;
  if M then
    Result := Result + 4;
end;

{ ===========================================================================
  OrientedSize  (procedure)
  Parameters:
    const O: TOrient - the orientation
    W: Integer - the width of the picture as it is
    H: Integer - its height
    out OutW: Integer - receives the width in the orientation
    out OutH: Integer - receives the height in the orientation
  Notes:
    The size of a picture once it is in an orientation: the same, or width and height changed
    places.
  =========================================================================== }
procedure OrientedSize(const O: TOrient; W, H: Integer; out OutW, OutH: Integer);
begin
  if OrientSwapsAxes(O) then begin
    OutW := H;
    OutH := W;
  end
  else begin
    OutW := W;
    OutH := H;
  end;
end;

{ ===========================================================================
  OrientedSource  (procedure)
  Parameters:
    const O: TOrient
    X: Integer - horizontal position or value
    Y: Integer - vertical position or value
    W: Integer - the XML writer to save into
    H: Integer - whole number
    out SrcX: Integer - whole number (out: set by the call)
    out SrcY: Integer - whole number (out: set by the call)
  Notes:
    The oriented picture's pixel centre, measured from the middle of the picture in halves of a
    pixel and in the shape of the oriented picture, is taken back to the upright picture by the
    transpose of the matrix, and the pixel that contains it is the one. Everything is whole
    numbers: each pixel of the upright picture goes to exactly one pixel.
  =========================================================================== }
procedure OrientedSource(const O: TOrient; X, Y, W, H: Integer; out SrcX, SrcY: Integer);
var
  DW, DH, Cx2, Cy2, Sx2, Sy2: Integer;
  Inv: TOrient;
begin
  OrientedSize(O, W, H, DW, DH);
  Cx2 := 2 * X + 1 - DW;           // the pixel's centre from the middle, in halves of a pixel
  Cy2 := 2 * Y + 1 - DH;
  Inv := OrientInverse(O);
  { the same place in the upright picture, in halves of its own pixels: a step of the oriented picture along an axis is a step of the upright one along the axis it came from }
  if Inv.A <> 0 then
    Sx2 := Inv.A * Cx2
  else
    Sx2 := Inv.B * Cy2;
  if Inv.C <> 0 then
    Sy2 := Inv.C * Cx2
  else
    Sy2 := Inv.D * Cy2;
  SrcX := (W + Sx2) div 2;
  SrcY := (H + Sy2) div 2;
  if SrcX < 0 then
    SrcX := 0;
  if SrcY < 0 then
    SrcY := 0;
  if SrcX > W - 1 then
    SrcX := W - 1;
  if SrcY > H - 1 then
    SrcY := H - 1;
end;

end.
