// SPDX-License-Identifier: LGPL-2.1-or-later
{ Port of DPoint.h (CDPoint) - TinyCAD to Free Pascal / Lazarus.
  Original: Copyright 1994-2004 Matt Pyne, LGPL 2.1+. This port keeps that licence. }
unit UDPoint;

{$mode objfpc}{$H+}

interface

uses
  Math;

const
  PIXELSPERMM = 5; // Revision.h: how many pixels in each millimetre

type
  TDPoint = record
    x, y: Double;
  end;

function DPoint(AX, AY: Double): TDPoint;
{ C++ default constructor: both coordinates NaN ("no value"). }
function DPointInvalid: TDPoint;
function DPointHasValue(const P: TDPoint): Boolean;

{ Internal pixel units <-> XML millimetre units }
function MakeXMLUnits(A: Double): Double;
function UnmakeXMLUnits(A: Double): Double;

implementation

{ ===========================================================================
  DPoint  (function)
  Parameters:
    AX: Double - x coordinate
    AY: Double - y coordinate
  Returns:
    TDPoint - the point
  Notes:
    Makes a point from two coordinates.
  =========================================================================== }
function DPoint(AX, AY: Double): TDPoint;
begin
  Result.x := AX;
  Result.y := AY;
end;

{ ===========================================================================
  DPointInvalid  (function)
  Parameters:  none
  Returns:
    TDPoint - an invalid point
  Notes:
    The "no point" value (both coordinates NaN) that stands for CDPoint() having no value, e.g.
    for hidden power pins.
  =========================================================================== }
function DPointInvalid: TDPoint;
begin
  Result.x := NaN;
  Result.y := NaN;
end;

{ ===========================================================================
  DPointHasValue  (function)
  Parameters:
    const P: TDPoint - the point
  Returns:
    Boolean - False when either coordinate is NaN
  Notes:
    Tests for the "no point" value.
  =========================================================================== }
function DPointHasValue(const P: TDPoint): Boolean;
begin
  Result := not (IsNan(P.x) or IsNan(P.y));
end;

{ ===========================================================================
  MakeXMLUnits  (function)
  Parameters:
    A: Double - value in internal units
  Returns:
    Double - millimetres
  Notes:
    Converts internal units (0.2 mm) to the millimetres written in XML files.
  =========================================================================== }
function MakeXMLUnits(A: Double): Double;
begin
  Result := A / PIXELSPERMM;
end;

{ ===========================================================================
  UnmakeXMLUnits  (function)
  Parameters:
    A: Double - value in millimetres
  Returns:
    Double - internal units
  Notes:
    Converts millimetres read from an XML file to internal units.
  =========================================================================== }
function UnmakeXMLUnits(A: Double): Double;
begin
  Result := A * PIXELSPERMM;
end;

end.
