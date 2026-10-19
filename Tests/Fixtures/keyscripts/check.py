# SPDX-License-Identifier: GPL-2.0-or-later
# Checks the dumps a key script wrote. Usage: check.py <script name>
import json, sys

def dump(name, n):
    with open(f".build/keyscripts/{name}-{n}.json") as f:
        return json.load(f)

def cells(name, n):
    return [(c["kind"], c["input"], c["focused"]) for c in dump(name, n)["cells"]]

failures = 0
def check(ok, what):
    global failures
    print(("ok  " if ok else "BAD ") + what)
    failures += not ok

script = sys.argv[1]
if script == "editor-basics":
    # Shift+Return evaluates and moves to a new code cell (as in wxMaxima).
    first = [("code", "x+1;\ny", False), ("code", "", False)]
    base = first + [("text", "Some prose.", False), ("title", "A title", False), ("section", "A section", False)]
    check(cells("editor", 1) == [("code", "x+1;\ny", False), ("code", "", True)],
          "Return inserts a newline; Shift+Return does not, and moves to a new cell")
    check(cells("editor", 2) == base + [("subsection", "A subsection", False), ("code", "diff(x^3,x);", True)],
          "Cmd+1..4 and Cmd+0 insert text, title, section, subsection and code cells")
    got = cells("editor", 3)
    check(len(got) == 7 and got[6] == ("code", "", True), "Cmd+Z undoes the typing")
    check(cells("editor", 4) == base + [("subsection", "A subsection", True)], "Cmd+Z again undoes the insert")
    check(cells("editor", 5) == base[:4] + [("section", "A section", True)], "Cmd+Shift+Delete deletes the cell")
elif script == "eval-basics":
    d1 = dump("eval", 1)["cells"]
    check([c["label"] for c in d1] == [1, 2, 3, 4, -1], "input labels 1..4, then the new empty cell")
    check(d1[0]["outputs"] == ["math %o1 -cos(x)"], "integrate gives -cos(x)")
    check(d1[1]["outputs"][0].startswith("image %t2 png") and d1[1]["outputs"][1:] == ["math %o2 "],
          "wxplot2d gives a PNG read into the model, then its empty (%o2)")
    check(d1[2]["outputs"][0].startswith("error maxima expt: undefined"), "1/0 shows the error with its text")
    check(d1[3]["outputs"] == ["question Is y positive, negative or zero? answer=pos;", "math %o4 pos"],
          "asksign answered inline")
    d2, d3 = dump("eval", 2), dump("eval", 3)
    check(d2["state"] == "busy" and d2["running"] == 1, "the long integral is running")
    check(d3["state"] == "idle" and d3["cells"][4]["outputs"] == ["error interrupted Interrupted"], "Cmd+. interrupts it")
    d4 = dump("eval", 4)
    check([c["label"] for c in d4["cells"]][:4] == [1, 2, 3, 4] and d4["cells"][4]["label"] == -1,
          "after Restart, Cmd+R relabels from 1 in order (and stops at the question)")
    check(d4["state"] == "question" and d4["status"] == "", "evaluation stops at the question; no status after a restart")
elif script == "save-basics":
    import zipfile, re
    with zipfile.ZipFile("Tests/Fixtures/wxmx/wxmaxima-written/basics.wxmx") as z:
        before = z.read("content.xml").decode()
    with zipfile.ZipFile(".build/keyscripts/save-basics.wxmx") as z:
        names = [i.filename for i in z.infolist()]
        stored = all(i.compress_type == zipfile.ZIP_STORED for i in z.infolist())
        after = z.read("content.xml").decode()
        image = z.read("image1.png") if "image1.png" in names else b""
    check(names == ["mimetype", "format.txt", "content.xml", "image1.png"] and stored,
          "saved archive: mimetype, format.txt, content.xml, image1.png, all stored")
    check("<line>Reference title (edited in Macsima)</line>" in after, "the edit is saved")
    check(re.findall(r'uuid="([^"]+)"', before) == re.findall(r'uuid="([^"]+)"', after), "every cell keeps its uuid")
    with zipfile.ZipFile("Tests/Fixtures/wxmx/wxmaxima-written/basics.wxmx") as z:
        check(image == z.read("image1.png"), "the plot image is saved unchanged")
    d = dump("save", 1)
    check(len(d["cells"]) == 13 and d["cells"][0]["input"] == "Reference title (edited in Macsima)",
          "the window shows 13 cells and the edited title")
elif script == "advance-basics":
    d1 = dump("advance", 1)
    check(len(d1["cells"]) == 1 and d1["cells"][0]["kind"] == "code" and d1["cells"][0]["focused"],
          "the app starts with an untitled worksheet, not the Open panel")
    c = dump("advance", 2)["cells"]
    check([(x["input"], x["label"]) for x in c] == [("2+2;", 1), ("3+3;", 2), ("", -1)],
          "Shift+Return on the last cell moves to a new code cell; typing goes there")
    check(c[2]["focused"], "the new cell has the focus")
    check(any("math %o2 6" in o for o in c[1]["outputs"]), "the second cell was evaluated: 6")
elif script == "advance-existing":
    def focused(n):
        return [i for i, c in enumerate(dump("advance-existing", n)["cells"]) if c["focused"]]
    check(focused(1) == [1], "from the first heading, Shift+Return moves to the next cell (1+1;)")
    c2 = dump("advance-existing", 2)["cells"]
    check(focused(2) == [3], "evaluating 1+1; skips the page break and moves to the next heading")
    check(c2[1]["outputs"] == ["math %o1 2"], "1+1; was evaluated")
    check(len(c2) == 6, "no cell was added when a next cell exists")
elif script == "editor-syntax":
    e1 = dump("editor-syntax", 1)["editor"]["colors"]
    check(e1 == ["/* note */=systemGrayColor", "if=systemPurpleColor", "1.5e3=systemBlueColor",
                 "then=systemPurpleColor", "sin=systemTealColor", "else=systemPurpleColor",
                 '"big"=systemRedColor', ";=secondaryLabelColor", "?car=systemOrangeColor", "$=secondaryLabelColor"],
          f"comment, keywords, number, built-in, string, terminators and Lisp symbol coloured: {e1}")
    bg = lambda n: [b.split("=")[0] for b in dump("editor-syntax", n)["editor"]["backgrounds"]]
    check(bg(2) == ["1:(", "11:)"], f"after the closing parenthesis, it and its partner are marked: {bg(2)}")
    check(bg(3) == ["3:[", "5:]"], f"after ], the bracket pair [ ] is marked: {bg(3)}")
    check(bg(4) == [], f"no bracket next to the caret, no mark: {bg(4)}")
    def at(n):
        d = dump("editor-syntax", n)
        return [i for i, c in enumerate(d["cells"]) if c["focused"]], d["editor"]["selection"]
    check(at(5) == ([0], [7, 0]), f"Up on the first line moves to the cell above, same column: {at(5)}")
    check(at(6) == ([1], [7, 0]), f"Down on the last line moves to the cell below, same column: {at(6)}")
    check(at(7) == ([1], [12, 0]), f"Down in the last cell moves to its end: {at(7)}")
    check(at(8) == ([2], [2, 0]), f"Up from a second line stays in the cell: {at(8)}")
    check(at(9) == ([1], [2, 0]), f"then Up leaves for the cell above: {at(9)}")
elif script == "undo-scroll":
    c1 = dump("undo-scroll", 1)["cells"]
    check(len(c1) == 61 and c1[60]["input"] == "last", f"61 cells, typing in the last: {len(c1)}")
    c2 = dump("undo-scroll", 2)["cells"]
    check(c2[0]["input"] == "1+1;" and c2[60]["focused"],
          f"Cmd+Z in the last cell undoes the typing in the first, which scrolled away: {c2[0]['input']!r}")
elif script == "find-basics":
    f = lambda n: dump("find", n)["find"]
    inputs = lambda n: [c["input"] for c in dump("find", n)["cells"]]
    check(f(1)["count"] == 5 and f(1)["status"] == "1 of 5",
          f"Cmd+F, typing x: 5 matches over three cells, case-insensitive, wrapping to the first: {f(1)}")
    check(dump("find", 1)["findSelection"] == [2, 1], "the first match is selected in its cell")
    check(f(2)["status"] == "2 of 5", f"Cmd+G goes to the next match: {f(2)['status']}")
    check(f(3)["status"] == "5 of 5", f"Cmd+Shift+G twice goes back, wrapping: {f(3)['status']}")
    check(inputs(4) == ["a:y+1;\ny^2", "f(y):=y;", "a word with y"], f"Replace All in every cell: {inputs(4)}")
    check(f(4)["status"] == "No matches", "no matches left")
    check(not f(5)["visible"], "Esc closes the bar")
    check(inputs(6) == ["a:x+1;\nx^2", "f(x):=X;", "a word with x"], f"one Cmd+Z undoes Replace All: {inputs(6)}")
else:
    sys.exit(f"unknown script {script}")
print("PASS" if failures == 0 else f"FAIL ({failures})")
sys.exit(1 if failures else 0)
