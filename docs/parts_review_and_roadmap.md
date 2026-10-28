# Parts: review of the current design, how AutoCAD Electrical and EPLAN work, and a proposed order of work

Written 2026-10-27 after reading the parts code (UPartsDb, UPartsSchema, UPartData, QPartsEditor and its forms, ULinks, TDrawRungGrid, TDrawRefText). No code was changed.

## 1. Question: code the part types in Pascal, or keep them in the database?
**Keep them in the database; add a few coded behaviours that read the data.** A Pascal class tree (TPartRelay, TPartVFD, TPartPLCCard ...) would need a new release for every new kind of device, could not be extended by users, and would duplicate what the database already does. The database already has the tree.

## 2. What exists today
**Parts database (docs/parts_schema.sql, 44 tables/views/triggers):**
- `PartClass` is a tree with inherited fields (`ClassFields` view): Part > ActivePart > ControlModule > IOModule > AnalogInputModule / DigitalIOModule; ActivePart > PowerSupply, Sensor; Part > PassivePart > SwitchingDevice > Contactor / Relay / Breaker, TerminalBlock. This is the hierarchy you sketched.
- `ObjectKind` is a second tree for the things inside a part: Coil, PowerInput, Load, Terminal, Pole, Contact (field `Form`: NO / NC / CO / make-before-break / latching), Channel, SensorIO, NetworkPort, InternalLink.
- `ClassAllowsKind` says what a class may contain (a SwitchingDevice must have at least one Pole and may have Contacts and Coils; an IOModule at least one Channel). A trigger refuses anything else.
- `Link` relations inside a part: `driven_by`, `switches`, `bridged`, `powers`, `isolated_from`, `shares_return`. So "this contact is driven by that coil" can already be stored.
- `Product` (manufacturer, MPN) is separate from `Part` (generic function and required ratings). Ratings, a fit check (ProductFit), 2D outlines, 3D models with terminal positions, datasheets, approvals, offers, substitutes.
- `Symbol` rows per part (standard IEC/ANSI, purpose schematic / oneline / panel / block) and `SymbolPin`, which maps each pin of a symbol to one of the part's child objects.

**Editor:** seven tabs (Parts, Classes, Objects, Ratings, Values, Symbols, Products). It exposes the whole schema, which is why it feels enigmatic: a person who only wants to add a relay has to understand classes, kinds, objects, ratings and values.

**Schematic side (what a placed symbol knows):**
- It keeps a copy of its part (PartInfo: UID, library UID, name, class, required ratings) and optionally the chosen product. This feeds the fit check and the BoM.
- It does NOT know which object of the part it shows. Nothing in the placement code uses `PartObject`, `SymbolPin` or `Link`. A relay's coil and its contacts are separate placed symbols tied together only by sharing the same reference text (K1).
- Cross-references exist: `TDrawRefText` shows either the ladder line of its target or the lines of the other symbols that share the target's reference (the contacts of a coil, or the coil of a contact). It cannot say NO or NC, count poles or warn when contacts are used up.
- Ladder awareness exists: `TDrawRungGrid.LineNumberAt` finds the rung from the symbol's reference point anywhere across the area (not only over the number column). What is missing is a rule for a symbol that spans several rungs, and a way to override.

## 3. How the commercial tools work (what is relevant to speed)
AutoCAD Electrical:
- A device with several symbols uses one **parent** (the coil) and **child** symbols (contacts). On inserting a child you pick its parent (from the drawing, from the project, or by clicking a related symbol) and it takes the parent's tag, location and description. Components can be inserted from a catalog by part number, and the catalog data is placed on the symbol.
- Ladders are inserted with width, rung spacing, first line reference and one-phase or three-phase; the rung is placed at the nearest line reference. Generated PLC I/O modules adapt to the rung spacing and can stretch or split. A Multiple Bus tool draws an n-wire bus and 3-pole fuses, starters and motors are placed on it. (I could not confirm from the help pages whether the connection to every phase is automatic; the Autodesk page only shows them placed on the bus.)
- Renumbering a ladder does not update tags or wire numbers by itself; you run Retag and Wire Numbers afterwards.

EPLAN Electric P8:
- Every function of a device (coil on one page, contacts on others) gets the same **device tag**. EPLAN then adds a cross-reference to every component with that tag. How the cross-reference looks (contact image) is a project setting. Giving a multi-line and a single-line symbol the same tag links those two representations too.
- Parts come from a master data catalogue; macros place whole circuits.

What both do, and what matters to you: ONE device identity, many symbols, each symbol knows which function of the device it is; cross-references and numbering are computed from that, never typed. They do not hard-code device types in the drawing layer; the catalogue carries the data.

(The help pages I could fetch were partial. I did not see the contact-mirror or auto-connect details and have not used either product, so treat anything beyond the above as unverified.)

## 4. Recommendation
1. **Keep parts in data.** The schema already models what you described. Do not add a Pascal class tree.
2. **Add a thin coded layer** that gives behaviour to a few kinds only: Coil, Pole/Contact, Channel. Everything else stays plain data.
3. **Make the placed symbol aware of its function** (the missing link). Store on the placed symbol: PartUID (exists), which child object it represents (Coil, Pole 2, Contact 1 NO ...), and the reference of the device. This is the `SymbolPin`/`PartObject` mapping the schema already has, brought into the schematic.
4. **Do the busy-work removers first** (the speed you asked for), then the UI.

## 5. Proposed order
| # | Step | What the user gets | Size |
|---|------|--------------------|------|
| 1 (done) | Placed symbol records the part object it shows (Coil / Pole n / Contact m) | the basis for everything below | medium |
| 2 (done) | "Insert contact of K1": choose a coil, the contact takes the reference and the next unused NO/NC contact of that relay; warn when a relay has none left | no typing of references, no counting poles | medium |
| 3 | Rung assignment: default = the rung where the symbol's connection points sit; when it spans several rungs, the one it overlaps most; if still ambiguous a small picker; the choice is stored on the symbol | line numbers right without work | small |
| 4 | Cross-reference text with contact type ("5 NO  7 NC") and "Add Rung Reference" on right click (coil -> its contacts, contact -> its coil) | what you described, EPLAN style | small (extends TDrawRefText) |
| 5 | Poles as data on the part (rows: coil, pole, contact form NO/NC, delayed on/off) | relays and timers described once | small (schema has it) |
| 6 | Multi-pole snapping onto the existing Bus object (given a conductor count and spacing; right click a wire > Change to bus): part pole pitch and an n-conductor bus; placing a 3-pole device snaps all poles onto a 3-wire bus (2 on a 2-wire bus) | the SkyCAD behaviour you liked | larger |
| 7 | Simplify "Add part": a wizard (pick class -> only that class's fields; presets such as "relay with 3 NO + 1 NC", "contactor 3-pole + aux"), tabs for products / 3D / outlines hidden under Advanced | adding a part in seconds; custom parts possible | medium |
| 8 | "Make part from this symbol" (right click a drawn symbol) and a starter library of common electrical parts | rarely need to create parts | medium |

Do 1 to 4 first: they remove the most repetition and do not depend on the parts editor. Product data, 2D outlines and 3D models stay out of the way until the BoM / panel stage (they hang off Product and are optional).

## 6. Risks and open questions
- Where the rung is stored: on the symbol (survives moving), or recomputed from position (always right but cannot be overridden). Suggest recompute by default with an optional stored override.
- Contact numbering across several sheets and a coil with more contacts than poles: needs a clear rule and a warning.
- Existing TinyCAD designs have no part data; everything must keep working for a plain symbol that shares a reference.
- **Decided (user, 2026-10-27): the existing Bus object is the thing multi-pole devices snap to.** It needs a conductor count (2, 3, ...) and a spacing, a right-click **Change to bus** on a wire (and back to wire), and the snapping rule: a device with N poles snaps its poles onto the N conductors of a bus of N conductors (a 3-pole device on a 2-conductor bus uses 2, as SkyCAD did). A bus then means the same in a circuit and in an electrical drawing.
- SkyCAD: I could not test it; its custom-part story was not visible to you either, so this design should not copy it blindly.

Sources: Autodesk help (Schematic Components; To Work With Ladders; Create a three-phase circuit); EPLAN Infoportal (cross-reference generation).
