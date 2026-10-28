# Parts in a design (.dsn): what is stored and what the verify check does

Decided with the user (2026-10-23). Format is not TinyCAD compatible (the user is warned on the first part placed).

## Two levels
- **Part** (generic): class, symbol, terminals / contacts / coils / channels, and the *required* ratings. This is what a sheet places.
- **Product** (catalog item): manufacturer, model number, what it is actually rated for, datasheets, 3D model, footprint, offers. A product is chosen for a placed part; it is never needed to draw or wire the sheet, so a design stays manufacturer-agnostic until the user picks.

## What the .dsn keeps (all of it; a design must open and check without the library)
For every placed part:
1. `PartUID` and `LibraryUID` (GUIDs) - to find the part again and to offer an update when the library has a newer revision.
2. A **copy of the generic part used**: name, class, its objects (names, kinds), its symbol, and its required ratings. (One copy per part per design, shared by every placement, as TinyCAD shares an embedded symbol.)
3. The **chosen product** (optional): `ProductUID` plus a snapshot of manufacturer, model number, description and the product's ratings. The snapshot is what the verify check and the BoM use, so they work with the library missing and do not change when the library changes.
4. The **details typed by the user**, in the placed part's details: manufacturer and model number as free text when the product is not in any library (then ratings may be typed too, or are "unknown" and reported). Choosing a product from a library fills the same fields.
5. A resolved flag is not stored: resolved = a manufacturer and model number are present.

## Rules
- A product that meets or beats every requirement is fine (**oversized is allowed**, shown as information only).
- A product that is **undersized** (rating below the requirement), **missing** a rated quantity the part requires, or **mismatched** on a quantity that must be equal (coil voltage, poles) is reported by the design **verify check**.
- Quantities are judged by `RatingQuantity.Sense` (`min` / `max` / `match`); the value compared is Max, else Typ, else Min; a requirement is matched by quantity and condition (`AC-3 400 V` does not satisfy `AC-15 230 V`); a product rating on `kind:Contact` covers every contact of the part, one on an object's name covers that object.
- The SQL in `parts_schema.sql` (`ProductFit`, `ProductFitSummary`) is the reference; the Pascal check must give the same verdicts on the same rows (tests/run_partsschema.py has the independent oracle).
- BoM: grouped by part, then product; parts without a product are listed as *unresolved* with the requirement; resolved parts show manufacturer, model number and quantity; a resolved part that no longer fits is listed with its verdict.

## Not decided yet
- Whether a placed part may name a product of a different class (the fit view only compares same-class products).
- How wire lengths / panel layout use the product's 3D model and footprint (later; they hang off Product).
