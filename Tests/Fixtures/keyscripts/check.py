# SPDX-License-Identifier: GPL-2.0-or-later
# Checks the dumps a key script wrote. Usage: check.py <script name>
import json, sys

def cells(n):
    with open(f".build/keyscripts/editor-{n}.json") as f:
        return [(c["kind"], c["input"], c["focused"]) for c in json.load(f)["cells"]]

expected = {
    1: [("code", "x+1;\ny", True)],  # Return inserts a newline, Shift+Return does not
    2: [("code", "x+1;\ny", False), ("text", "Some prose.", False), ("title", "A title", False),
        ("section", "A section", False), ("subsection", "A subsection", False), ("code", "diff(x^3,x);", True)],
    3: None,  # undo of the typing: last cell empty
    4: [("code", "x+1;\ny", False), ("text", "Some prose.", False), ("title", "A title", False),
        ("section", "A section", False), ("subsection", "A subsection", True)],  # undo of the insert
    5: [("code", "x+1;\ny", False), ("text", "Some prose.", False), ("title", "A title", False),
        ("section", "A section", True)],  # Cmd+Shift+Delete deleted the subsection
}
failures = 0
for n, want in expected.items():
    got = cells(n)
    if n == 3:
        ok = len(got) == 6 and got[5] == ("code", "", True)
    else:
        ok = got == want
    print(("ok  " if ok else "BAD ") + f"step {n}: {got}")
    failures += not ok
print("PASS" if failures == 0 else f"FAIL ({failures})")
sys.exit(1 if failures else 0)
