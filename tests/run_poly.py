"""Polygon handle editing: a randomised check of the model (polytest): random polygons with arcs and curves get random
menu actions (Add handle, Delete handle, Free line, Arc in, Arc out, Curve) and handle drags, and after each one the
other handles must keep their absolute positions, an added handle must be exactly the snapped click, a deleted one
exactly one of the old handles, a polygon must keep two handles, the origin must be the top left of the bounding box,
which must hold every point, and saving then loading must give back the same handles, arcs and control points."""
import os, re, subprocess, sys
BUILD = os.environ.get("TC_BUILD", "build")
r = subprocess.run([os.path.join(BUILD, "polytest")], capture_output=True, text=True)
out = r.stdout.strip().split("\n")
m = re.match(r"POLYTEST runs=(\d+) actions=(\d+) drags=(\d+) roundtrips=(\d+) checks=(\d+) fails=(\d+)", out[-1])
if r.returncode != 0 or not m:
    print(r.stdout[-600:], r.stderr[-300:]); print("\nPOLYGON EDITING CHECKS FAILED: the driver did not finish"); sys.exit(1)
runs, actions, drags, trips, checks, fails = (int(x) for x in m.groups())
for l in out[:-1]: print(" ", l)
ok = fails == 0 and actions > 5000 and drags > 2000 and trips > 1500 and checks > 500000
print(f"polygon handles: {runs} random polygons, {actions} menu actions, {drags} handle drags, {trips} save/load round trips, {checks} checks, {fails} failures")
print("\nPOLYGON EDITING CHECKS PASSED" if ok else "\nPOLYGON EDITING CHECKS FAILED")
sys.exit(0 if ok else 1)
