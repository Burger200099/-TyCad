{ The property frames the program knows: add a frame's unit to the uses clause and register it in RegisterAllPropFrames (see QPropFrame for how a frame is made
  and how its editors are named). A kind of tool or object that is not registered gets the editors the program makes by itself.

  Licence: LGPL 2.1 or later, as the rest of this port. }
unit QPropFrameList;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, QPropFrame,
  QPropWire, QPropText, QPropWireLabel, QPropNote, QRectCircle, QPolygon, QArc, QBus, QCloudNote, QPowerSym, QMeasure, QLadder, QRungs, qsymbols, QPin;      // the frames; a new one is added here

procedure RegisterAllPropFrames;

implementation

{ ===========================================================================
  RegisterAllPropFrames  (procedure)
  Parameters:  none
  Notes:
    Registers the property frames; called once when the main window is made.
  =========================================================================== }
procedure RegisterAllPropFrames;
const
  { The controls of these frames that are not named after the property they edit (QPropFrame): 'control=property'; 'control=property:caption' also hides the caption
    with the control when the tool or object has no such property. A control named after its property (edText, cbFillType, seLineWidth) needs no line. }
  BusLinks: array[0..4] of String = ('cbWireColor=line.color', 'seWireSize=line.width', 'cbWireType=line.style', 'cbAngle=wire.angle', 'bbPhase=bus.phases');
  WireLinks: array[0..3] of String = ('cbWireColor=line.color', 'seWireSize=line.width', 'cbWireType=line.style', 'cbAngle=wire.angle');
  RectLinks: array[0..3] of String = ('cbWireColor=line.color', 'seWireSize=line.width', 'cbWireType=line.style', 'sbFill=fill.type');
  PolyLinks: array[0..4] of String = ('cbClosed=poly.closed', 'cbWireColor=line.color', 'seWidth=line.width:lbWidth', 'cbWireType=line.style', 'bbFill=fill.type');
  ArcLinks: array[0..5] of String = ('cbWireColor=line.color', 'seWidth=line.width:lbWidth', 'cbWireType=line.style', 'bbFill=fill.type', 'rbArcIn=arc.type:lbArcType', 'rbArcOut=arc.type');
  CloudLinks: array[0..3] of String = ('cbWireColor=line.color', 'seWireSize=line.width', 'cbWireType=line.style', 'fseScallop=cloud.bump:lbScallop');
  TextLinks: array[0..7] of String = ('edText=text', 'cbTextDirection=dir', 'cbTextDirection1=label.style:lbType', 'cbFont=font.face', 'cbFontSize=font.height', 'sbBold=font.bold', 'sbItalic=font.italic', 'cbTextColor=font.color');
  NoteLinks: array[0..11] of String = ('edText=text', 'cbTextDirection=dir', 'cbTextDirection1=label.style:lbType', 'cbFont=font.face', 'cbFontSize=font.height', 'sbBold=font.bold', 'sbItalic=font.italic',
    'cbTextColor=font.color', 'cbTextColor1=line.color', 'seFrameWidth=line.width', 'cbWireType=line.style', 'bbFill=fill.type');
  PowerLinks: array[0..2] of String = ('cbTextDirection=power.type', 'edText=text', 'sbOrientation=dir');
  MeasureLinks: array[0..8] of String = ('cbFont=font.face', 'cbFontSize=font.height', 'sbBold=font.bold', 'sbItalic=font.italic', 'cbFontColor=font.color', 'cbLineColor=line.color',
    'seLineWidth=line.width', 'cbUnits=measure.unit', 'cbGrads=measure.ticks');
  LadderLinks: array[0..8] of String = ('cbFont=font.face', 'cbFontSize=font.height', 'sbBold=font.bold', 'sbItalic=font.italic', 'cbFontColor=font.color', 'cbLineColor=line.color',
    'seLineWidth=line.width', 'edLeft=ladder.left', 'edRight=ladder.right');
  RungLinks: array[0..10] of String = ('cbFont=font.face', 'cbFontSize=font.height', 'sbBold=font.bold', 'sbItalic=font.italic', 'cbFontColor=font.color', 'seRows=rungs.rows',
    'seStart=rungs.start', 'fseMargin=rungs.margin', 'cbPages=rungs.pages', 'cbContinue=rungs.continue', 'cbShowHeight=rungs.showheight'); 
  SymbolLinks: array[0..6] of String = ('edRef=sym.ref', 'edSymbolText=symtext.text', 'sbShowRef=sym.showref', 'sbShowPowerPins=sym.showpower', 'sbAllowResize=sym.canscale', 'sbRotateSymbol=', 'sbParameterList=');
begin
  RegisterPropFrame('wire', TfmPropRibbonWire, WireLinks);
  RegisterPropFrame('bus', TfmBus, BusLinks);
  RegisterPropFrame('line', TfmPropRibbonWire, WireLinks);
  RegisterPropFrame('rect', TfmRectCircle, RectLinks);
  RegisterPropFrame('circle', TfmRectCircle, RectLinks);
  RegisterPropFrame('polygon', TfmPolygon, PolyLinks);
  RegisterPropFrame('arc', TfmArc, ArcLinks);
  RegisterPropFrame('cloud', TfmCloudRect, CloudLinks);
  RegisterPropFrame('text', TfmPropText, TextLinks);
  RegisterPropFrame('label', TfmPropWireLabel, TextLinks);
  RegisterPropFrame('note', TfmPropNote, NoteLinks);
  RegisterPropFrame('power', TfmPower, PowerLinks);
  RegisterPropFrame('measure', TfmMeasure, MeasureLinks);
  RegisterPropFrame('ladder', TfmLadder, LadderLinks);
  RegisterPropFrame('runggrid', TfmRungs, RungLinks);
  RegisterPropFrame('method', TfmSymbols, SymbolLinks);
  RegisterPropFrame('symboltext', TfmSymbols, SymbolLinks);
  RegisterPropFrame('pin', TfmPin);      // (its editors are all named after their properties)
end;

end.
