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
    check(d1[1]["outputs"][0].startswith("image %t2 png") and d1[1]["outputs"][1:] == ['math %o2 ""'],
          "wxplot2d gives a PNG read into the model, then its empty (%o2)")
    check(d1[2]["outputs"][0].startswith("error maxima expt: undefined"), "1/0 shows the error with its text")
    check(d1[3]["outputs"] == ["question Is y positive, negative or zero? answer=pos;", "math %o4 pos"],
          "asksign answered inline")
    d2, d3 = dump("eval", 2), dump("eval", 3)
    check(d2["state"] == "busy" and d2["running"] == 1, "the long integral is running")
    check(d3["state"] == "idle" and d3["cells"][4]["outputs"] == ["error interrupted Interrupted"], "Cmd+. interrupts it")
    d4 = dump("eval", 4)
    # Abort on error is off here: 2+2 after 1/0 runs and takes (%i4). The
    # cell after the question has not run yet and keeps its old outputs.
    check([c["label"] for c in d4["cells"]][:4] == [1, 2, 3, 5] and "math %o4 4" in d4["cells"][2]["outputs"]
          and d4["cells"][4]["outputs"] == ["error interrupted Interrupted"],
          f"after Restart, Cmd+R relabels from 1 in order and stops at the question: {[c['label'] for c in d4['cells']]}")
    check(d4["state"] == "question" and d4["status"] == "", "evaluation stops at the question; no status after a restart")
elif script == "restart-basics":
    def labels(n): return [c["label"] for c in dump("restart", n)["cells"]][:3]
    def stale(n): return [c["stale"] for c in dump("restart", n)["cells"]][:3]
    check(labels(1) == [1, 2, 3], f"three cells labelled 1..3: {labels(1)}")
    check(labels(2) == [-1, -1, -1] and stale(2) == [True, True, True],
          f"after Restart every label is --> and the outputs are stale: {labels(2)} {stale(2)}")
    d3 = dump("restart", 3)["cells"]
    check(labels(3) == [1, 2, 3] and stale(3) == [False, False, False] and d3[2]["outputs"] == ["math %o3 2"],
          f"Cmd+R after the restart runs past 1/0 (abort on error off): {labels(3)} {d3[2]['outputs']}")
elif script == "wrap-basics":
    def renders(n, label):
        return [r for r in dump("wrap", n)["renders"] if r["label"] == label]
    d1 = dump("wrap", 1)
    check(d1["windowWidth"] == 760, "the window is 760 points wide")
    narrow = {l: renders(1, l)[-1] for l in ["%o1", "%o2", "%o3", "%o4"] if renders(1, l)}
    check(len(narrow) == 4 and all(0 < r["wrap"] < r["natural"] and r["width"] <= r["wrap"] for r in narrow.values()),
          "the four long outputs are wider than the output column, broken at its width, and fit in it: " + str(narrow))
    check(all(r["height"] > 40 for r in narrow.values()), "each takes more than one line (one line is at most about 30 points)")
    matrix = renders(1, "%o5")
    check(len(matrix) > 0 and matrix[-1]["width"] > matrix[-1]["wrap"] > 0 and matrix[-1]["height"] < 40,
          "the wide matrix stays on one line (it scrolls): " + str(matrix[-1:]))
    wide = renders(2, "%o1")
    check(dump("wrap", 2)["windowWidth"] == 1100 and len(wide) > 0 and wide[-1]["wrap"] > narrow["%o1"]["wrap"]
          and wide[-1]["height"] < narrow["%o1"]["height"], "after widening the window, %o1 is broken again into fewer lines")
elif script == "copy-basics":
    c1, c2, c3, c4 = (dump("copy", n) for n in range(1, 5))
    check(c1["string"] == "'sum(1/k^2,k,1,inf)", "Copy as Maxima Input: 'sum(1/k^2,k,1,inf)")
    check(c2["string"] == r"\sum_{k = 1}^{\infty} \frac{1}{{k}^{2}}", "Copy as LaTeX: " + str(c2["string"]))
    check(str(c3["string"]).startswith("<math") and "&#x2211;" in c3["string"], "Copy MathML: a <math> element with the sum sign")
    check("public.png" in c4["types"] and "public.tiff" in c4["types"] and 30 < c4.get("image", [0, 0])[0] < 200,
          "Copy as Image: PNG and TIFF of the math alone (no label column): " + str(c4.get("image")))
elif script == "cells-basics":
    def inputs(n): return [c["input"] for c in dump("cells", n)["cells"]]
    d1 = dump("cells", 1)
    check(d1["selectedCells"] == [0, 1] and d1["firstResponder"] == "CellSelectionResponder",
          "a click on the bar and a Shift-click select cells 0 and 1")
    pb = dump("cells", "pb1")
    check("local.macsima.cells" in pb["types"] and "text/x-wxmaxima-batch" in pb["types"]
          and pb["string"].startswith("(%i1) a:1;\n(%o1) 1"), "Cmd+C puts the cells, .wxm and text on the pasteboard")
    check(inputs(2) == ["a:1;", "b:2;", "A note.", "a:1;", "b:2;"] and dump("cells", 2)["selectedCells"] == [3, 4],
          "Cmd+V pastes them after the selected cell and selects them")
    c2 = dump("cells", 2)["cells"]
    check(c2[3]["outputs"] == c2[0]["outputs"] and c2[3]["outputs"] != [], "pasted cells keep their outputs")
    check(inputs(3) == ["a:1;", "b:2;", "A note."], "Cmd+Z undoes the paste in one step")
    check(inputs(4) == ["b:2;", "A note."], "Cmd+X cuts the selected cell")
    check(inputs(5) == ["a:1;", "b:2;", "A note."], "Cmd+Z puts it back")
    check(inputs(6) == ["a:1;", "b:2;"], "Delete deletes the selected cell")
    check(dump("cells", 7)["selectedCells"] == [0, 1], "Shift+Up at the start of a cell selects it and the one above")
    d8 = dump("cells", 8)
    check(d8["selectedCells"] == [] and d8["firstResponder"] == "CellTextView", "Down goes back to editing")
elif script == "plots-basics":
    c = dump("plots", 1)["cells"]
    d = dump("plots", 1)
    check(c[0]["outputs"] == ["animation %t1 png 3 frames fr=-", 'math %o2 ""'],
          "with_slider gives a 3-frame animation, without the empty (%t2) line: " + str(c[0]["outputs"]))
    check(c[1]["outputs"][0].startswith("image %t3 png"), "wxdraw2d gives a PNG plot")
    check(any(o.startswith("image %t5 svg") for o in c[2]["outputs"]), "with wxplot_usesvg, an SVG plot: " + str(c[2]["outputs"]))
    check(d["status"] == "", "Maxima's progress text is gone once evaluation ends: " + repr(d["status"]))
    im = lambda n, i: dump("plots", n)["cells"][i]["images"]
    check(im(1, 0) == [{"ppi": "192", "pixels": 1600}], f"the animation's frames are 2x, marked ppi 192: {im(1, 0)}")
    check(im(1, 1) == [{"ppi": "", "pixels": 800}], f"wxdraw2d stays 1x, unmarked: {im(1, 1)}")
    check(im(2, 3) == [{"ppi": "192", "pixels": 1600}], f"wxplot2d draws 1600 pixels, marked ppi 192: {im(2, 3)}")
elif script == "kinds-basics":
    c1 = dump("kinds", 1)["cells"]
    image = [c for c in c1 if c["kind"] == "image"]
    check(len(image) == 1 and image[0]["input"] == "Poldino the guinea pig" and image[0]["outputs"][0].startswith("image - jpg"),
          "the image cell shows its caption and its JPEG")
    c2 = dump("kinds", 2)["cells"]
    new = [c for c in c2 if c["kind"] == "image" and c["input"] == "01-integral-result.png"]
    check(len(new) == 1 and new[0]["focused"] and new[0]["outputs"][0].startswith("image - png"),
          "Insert Image adds an image cell after the focused one, captioned with the file name")
    check(len(dump("kinds", 3)["cells"]) == len(c1), "Cmd+Z removes it")
elif script == "folds-basics":
    d1 = dump("folds", 1)
    check([c["input"] for c in d1["cells"]] == ["x:1;", "S1", "a:1;", "T", "b:2;", "S2", "c:3;"], "seven cells: two sections, a subsection")
    check(d1["visible"] == [0, 1, 5, 6] and d1["cells"][1]["folded"], "folding S1 hides its cells, the subsection's too")
    d2 = dump("folds", 2)
    check([c["focused"] for c in d2["cells"]].index(True) == 5, "Down from the folded heading skips to S2")
    d3 = dump("folds", 3)
    check(d3["visible"] == [0, 1, 5] and [c["folded"] for c in d3["cells"]] == [False, True, False, True, False, True, False],
          "Cmd+Opt+[ folds every heading with cells under it")
    d4 = dump("folds", 4)
    check(d4["visible"] == list(range(7)) and d4["cells"][6]["hidden"], "Cmd+Opt+] unfolds all; the triangle hides a code cell")
    d5 = dump("folds", 5)
    check(4 in d5["visible"] and not d5["cells"][1]["folded"] and not d5["cells"][3]["folded"],
          "Find unfolds the sections around its match")
elif script == "format-basics":
    def text(n): return dump("format", n)["cells"][1]
    c1 = text(1)
    check(c1["input"] == "plain bold more" and c1["formats"] == ["bold=6-15"],
          "Cmd+B makes the selection bold; typing after it continues bold: " + str(c1))
    c2 = text(2)
    check(c2["input"] == "plain bold" and c2["formats"] == ["bold=6-10"], "Cmd+Z undoes the typing: " + str(c2))
    c3 = text(3)
    check(c3["formats"] == [], "Cmd+Z again undoes the bold: " + str(c3))
    check(text(4)["formats"] == ["italic=0-16", "underline=11-16", "superscript=11-16"],
          "Cmd+A, Cmd+I: all italic; then underlined superscript: " + str(text(4)["formats"]))
elif script == "checkpoint-b":
    d = dump("checkpoint-b", 1)
    kinds = [c["kind"] for c in d["cells"]]
    check(kinds[:8] == ["code", "code", "code", "text", "section", "code", "section", "image"]
          and d["cells"][4]["folded"] and d["selectedCells"] == [3, 4], "the checkpoint B worksheet was built: " + str(kinds))
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
    check(all(c["label"] == -1 for c in dump("advance-existing", 1)["cells"]),
          "after opening a file no input labels show, as in wxMaxima")
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
    code = lambda n: [c["input"] for c in dump("editor-syntax", n)["cells"] if c["focused"]][0]
    block = "f(x):=block([a],\n  a:x,\n  a^2\n)$"
    check(code(10) == block, f"Return indents after an open bracket and keeps it; ) takes it off: {code(10)!r}")
    check(code(11) == "f(x):=block([a],\n  a:x,\n  a^2\n/* )$ */", f"Cmd+/ comments the caret's line: {code(11)!r}")
    check(code(12) == block, f"Cmd+/ again uncomments it: {code(12)!r}")
    check(code(13) == "f(x):=block([a],\n  a:x,\n  a^2\n/* )$ */", f"Cmd+Z undoes the uncomment: {code(13)!r}")
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
elif script == "errors-basics":
    c1 = dump("errors", 1)["cells"]
    marks = [c["errorMarks"] for c in c1]
    check(marks[0] == {"statements": [[5, 6]], "spots": [], "current": True},
          f"1/0: the failing statement b:1/0; is marked, not the others: {marks[0]}")
    check(marks[1] == {"statements": [[0, 8]], "spots": [[3, 2]], "current": True},
          f"f(a,,b): the statement and the spot ,, Maxima's parser points at: {marks[1]}")
    check(marks[2] == {"statements": [], "spots": [[1, 1]], "current": True},
          f"g(x:=2; is never sent; the unclosed ( is marked: {marks[2]}")
    check(marks[3] is None, "the new empty cell has no marks")
    c2 = dump("errors", 2)
    check(c2["cells"][1]["errorMarks"]["current"] is False and c2["editor"]["backgrounds"] == [],
          f"typing in the cell hides its marks: {c2['editor']['backgrounds']}")
elif script == "close-basics":
    procs = lambda n: [l for l in open(f".build/keyscripts/close-{n}.txt").read().splitlines() if l.strip()]
    check(len(procs(1)) == 2, f"two windows, two Maxima processes: {procs(1)}")
    check(len(procs(2)) == 1, f"closing one window shuts its Maxima down, the other keeps running: {procs(2)}")
    c3 = dump("close", 3)["cells"]
    check(c3[0]["input"] == "1+1;", f"the other window is still there: {[c['input'] for c in c3]}")
elif script == "close-saved":
    import zipfile
    procs = lambda n: [l for l in open(f".build/keyscripts/close-saved-{n}.txt").read().splitlines() if l.strip()]
    c1 = dump("close-saved", 1)["cells"]
    check(c1[0]["input"] == "Before the breakx" and len(procs(1)) == 1,
          "Cmd+W asks; Cancel keeps the window, its edit and its Maxima")
    with zipfile.ZipFile(".build/keyscripts/close-saved.wxmx") as z:
        content = z.read("content.xml").decode()
    check("<line>Before the break</line>" in content and "breakx" not in content,
          "Revert Changes closes the window and leaves the file as it was saved")
    check(procs(2) == [], f"and shuts that window's Maxima down: {procs(2)}")
elif script == "appearance":
    c = dump("appearance", 1)["cells"]
    check(len(c[0]["outputs"]) == 1 and c[1]["outputs"][1].startswith("error"), "the outputs arrived")
elif script == "site-screenshot":
    first = [(c["kind"], c["input"]) for c in dump("site", 1)["cells"]]
    check(first == [("title", "Integrals and series")], f"the title is the only cell: {first}")
    c = dump("site", 2)["cells"]
    outs = [x["outputs"] for x in c if x["kind"] == "code" and x["input"]]
    check(len(outs) == 4 and all(len(o) == 1 and o[0].startswith("math") for o in outs),
          f"four results, no errors: {outs}")
elif script == "zoom-basics":
    import zipfile, re
    z = lambda n: dump("zoom", n)["zoom"]
    check(z(1) == 100 and z(2) == 150 and z(3) == 140, f"Cmd+= five times: 150%; Cmd+-: 140% ({z(1)}, {z(2)}, {z(3)})")
    with zipfile.ZipFile(".build/keyscripts/zoom-basics.wxmx") as f:
        doc = re.search(r"<wxMaximaDocument[^>]*>", f.read("content.xml").decode()).group(0)
    check(z(4) == 110 and 'zoom="110"' in doc, f"Actual Size, Cmd+=, Cmd+S: the file says {doc}")
elif script == "complete-basics":
    c = lambda n: dump("complete", n).get("completion")
    line = lambda n: [x["input"] for x in dump("complete", n)["cells"] if x["focused"]][0].split("\n")[-1]
    sel = lambda n: dump("complete", n)["editor"]["selection"]
    first = "velocity: 3$ myfun(a, b) := a*b$\n"
    check(c(1) is not None and "integrate(<expr>, <x>)" in c(1)["items"] and c(1)["selected"] == c(1)["items"][0],
          f"Esc after integ opens the list, first entry selected: {c(1) and c(1)['items'][:6]}")
    check(c(2) is not None and c(2)["selected"] == c(2)["items"][1], "Down selects the next entry")
    check(c(3) is not None and all(i.startswith("integrat") for i in c(3)["items"])
          and c(3)["items"][:2] == ["integrate(<expr>, <x>)", "integrate(<expr>, <x>, <a>, <b>)"],
          f"typing rat narrows the list to integrat...: {c(3) and c(3)['items']}")
    base = len(first)
    check(c(4) is None and line(4) == "integrate(<expr>, <x>, <a>, <b>)" and sel(4) == [base + 10, 6],
          f"Down, Return: the template is inserted, <expr> selected: {line(4)!r} {sel(4)}")
    check(line(5) == "integrate(sin(t), <x>, <a>, <b>)" and sel(5) == [base + 18, 3],
          f"typing replaces <expr>; Tab selects <x>: {line(5)!r} {sel(5)}")
    check(sel(6) == [base + 18, 3], f"Tab, Shift+Tab: back on <x>: {sel(6)}")
    check(line(7) == "integrate(sin(t), t, 0, 1, velocity)" and c(7) is None,
          f"one match (a worksheet name) is inserted at once: {line(7)!r}")
    check(line(8).endswith(", myfun(<a>, <b>))") and sel(8)[1] == 3,
          f"a worksheet function comes with its template, <a> selected: {line(8)!r} {sel(8)}")
    check(line(9).endswith(", myf)"), f"Cmd+Z takes the completion back in one step: {line(9)!r}")
    check(c(10) is not None and len(c(10)["items"]) == 5 and all(i.startswith("diff(") for i in c(10)["items"]),
          f"Show Template lists diff's five templates: {c(10) and c(10)['items']}")
    check(c(11) is None and line(11) == "diff", "Esc closes the list, the text unchanged")
    check(c(12) is None and line(12) == "plot(", f"( closes the list and is typed: {line(12)!r}")
    check(c(13) is not None and c(13)["worksheet"] == ["velocity"], f"velocity is the worksheet's: {c(13) and c(13)['worksheet']}")
elif script == "help-basics":
    h = lambda n: dump("help", n)["help"]
    check(h(1)["visible"] and h(1)["topic"] == "integrate" and h(1)["entries"] == ["integrate"],
          f"F1 in integrate opens the panel on its entry: {h(1)}")
    check(h(2)["topic"] == "quad_qag" and h(2)["history"] == ["integrate"], f"a link goes to quad_qag: {h(2)}")
    check(h(3)["topic"] == "integrate" and h(3)["history"] == [], f"Back returns to integrate: {h(3)}")
    check(h(4)["topic"] == ":=" and h(4)["entries"] == [":="], f"F1 on := looks up the operator: {h(4)}")
    check(h(5)["entries"] == ["diff", "diff <1>", "diff <2>"], f"diff has three entries, all shown: {h(5)}")
    check(h(6)["entries"] == [] and h(6)["error"] is None, f"no entry for nosuchtopic: {h(6)}")
    check(h(7)["pending"] == "expand" and dump("help", 7)["state"] == "question",
          f"while asksign waits, the lookup waits: {h(7)}")
elif script == "panels-basics":
    w = lambda n: {v["name"]: v for v in dump("panels", n)["watch"]}
    check(dump("panels", 1)["sidebar"] == "variables", "the variables panel is open")
    check(w(1).get("x", {}).get("text") == "3" and w(1)["f"]["kind"] == "function" and w(1)["f"]["text"] == "f(t):=t^2",
          f"after evaluating, x is 3 and f shows its definition: {w(1)}")
    check(w(2)["x"]["text"] == "4", f"evaluating again updates x: {w(2).get('x')}")
    check("big" in w(3) and w(3)["big"]["cut"] and list(w(3))[:2] == ["x", "f"],
          f"Add All adds big (cut, it is long) after the names already watched: {list(w(3))}")
    attrs = dump("panels", 4)["watchAttributes"]
    names = list(w(4))
    check("f" not in names and attrs.get("variables_num") == str(len(names))
          and [attrs.get(f"variables_{i}") for i in range(len(names) + 1)] == names + [""],
          f"Stop Watching f; the list is in the file's attributes as wxMaxima writes them: {attrs}")
    focused = lambda n: [i for i, c in enumerate(dump("panels", n)["cells"]) if c["focused"]]
    check(dump("panels", 5)["sidebar"] == "contents" and focused(5) == [4], f"a click on Intro focuses it: {focused(5)}")
    check(dump("panels", 6)["cells"][3]["folded"], "the title is folded")
    check(focused(7) == [6] and not dump("panels", 7)["cells"][3]["folded"],
          f"a click on Detail unfolds the title and focuses Detail: {focused(7)}")
    s8, s9 = dump("panels", 8)["statusBar"], dump("panels", 9)["statusBar"]
    check(s8["busy"] and s8["cpu"] > 50, f"while the loop runs: the clock runs and Maxima uses a core: {s8}")
    check(not s9["busy"] and s9["last"] > 2, f"afterwards, how long it took: {s9}")
elif script == "modes-basics":
    d = lambda n: dump("modes", n)
    def cell(n, start):
        return [c for c in d(n)["cells"] if c["input"].startswith(start)][0]
    check(d(1)["state"] == "question", f"asksign waits for an answer: {d(1)['state']}")
    q = cell(2, "asksign")["outputs"]
    check(d(2)["state"] == "idle" and any(o.startswith("error interrupted") for o in q),
          f"Interrupt while it waits: the cell ends as interrupted, Maxima is idle: {d(2)['state']} {q}")
    check(d(3)["state"] == "debugger" and d(3)["debugger"]["level"] == 1 and d(3)["debugger"]["debugOnError"],
          f"Debug on Error: 1/0 stops in the debugger at level 1: {d(3)['debugger']}")
    h = " | ".join(cell(4, "h(x)")["outputs"])
    check("answer=x; | math - 0" in h, f"x evaluates in h's frame (0): {h[-300:]}")
    check("#0: h(x=0)" in h, f":bt shows the frame: {h[-300:]}")
    check(d(5)["state"] == "idle" and d(5)["debugger"]["level"] == -1, f":top leaves the debugger: {d(5)['state']}")
    check(d(6)["state"] == "debugger" and d(6)["debugger"]["location"] == "debug-f.mac:4"
          and d(6)["debugger"]["source"] == "y: x^2,", f"the breakpoint stops at line 4 of the file, shown: {d(6)['debugger']}")
    check(d(7)["debugger"]["location"] == "debug-f.mac:5", f"Step Over goes to line 5: {d(7)['debugger']}")
    f = " | ".join(cell(8, ":break")["outputs"])
    check(d(8)["state"] == "idle" and "math %o" in f and "100" in f, f"Continue finishes f(3) = 100: {f[-200:]}")
    check(cell(9, "to_lisp")["label"] > 0, f"the to_lisp() cell has its input label: {cell(9, 'to_lisp')['label']}")
    lisp = cell(9, "(+ 1 2)")
    check(d(9)["debugger"]["lisp"] and lisp["label"] == -1 and any(o == "text 3" for o in lisp["outputs"]),
          f"in Lisp mode, (+ 1 2) gives 3 and no input label: {lisp['label']} {lisp['outputs']}")
    last = cell(10, "2+2")
    check(not d(10)["debugger"]["lisp"] and d(10)["state"] == "idle" and last["label"] > 0 and "math" in last["outputs"][0],
          f"Return to Maxima: 2+2 runs with a label again: {last['label']} {last['outputs']}")
elif script == "files-basics":
    import os
    read = lambda n: open(f".build/keyscripts/{n}", encoding="utf-8").read() if os.path.exists(f".build/keyscripts/{n}") else ""
    html, tex, mac, req, wxm = (read(n) for n in ["files-1.html", "files-1.tex", "files-1.mac", "files-2.html", "files-3.wxm"])
    check("<math" in html and "integrate(x^2, x);" in html and "data:image/png;base64," in html and "Some notes." in html,
          "Export › HTML: inputs, MathML outputs, the plot inside the page, the text cell")
    check("\\includeimage{files-1_img/image1.png}" in tex and os.path.exists(".build/keyscripts/files-1_img/image1.png")
          and "\\begin{equation*}" in tex, "Export › LaTeX: the math, and the plot in files-1_img/")
    check(mac.startswith("integrate(x^2, x);\n") and "/* Some notes. */" in mac, f"Export › Maxima Batch File: {mac[:120]!r}")
    check("<math" in req and "integrate(x^2, x);" in req, "wxworksheettohtml() in a cell writes the page Maxima asked for")
    check(wxm.startswith("/* [wxMaxima batch file version 1]") and "integrate(x^2, x);" in wxm,
          "Save To .wxm writes wxMaxima's batch format")
    d2 = dump("files", 2)
    kinds = [c["kind"] for c in d2["cells"]]
    check(kinds.count("text") == 10 and "pageBreak" in kinds, f"textcells.wxm opens as a worksheet: {kinds}")
    check("Open Recent" in dump("files", 1)["menus"] and "Maxima Batch File…" in dump("files", 1)["menus"],
          f"File › Open Recent and Export are there: {dump('files', 1)['menus']}")
elif script == "settings-basics":
    d = lambda n: dump("settings", n)
    def last_render(n, label):
        r = [x for x in d(n)["renders"] if x["label"] == label]
        return r[-1] if r else None
    f1, f2 = d(1)["editor"]["font"], d(2)["editor"]["font"]
    check(f1.endswith(" 14") and f2 == "Menlo 20", f"code font and size follow Settings at once: {f1} -> {f2}")
    r1, r2 = last_render(1, "%o1"), last_render(2, "%o1")
    check(r1 and r2 and r2["height"] > r1["height"] * 1.3, f"the math is rendered again, larger: {r1} -> {r2}")
    cell = [c for c in d(3)["cells"] if c["input"] == "1/0; 5;"][0]
    check(any(o.startswith("error") for o in cell["outputs"]) and any("math %o" in o and o.endswith(" 5") for o in cell["outputs"]),
          f"Abort on error off: 5 is evaluated after 1/0: {cell['outputs']}")
    plot = [c for c in d(4)["cells"] if c["input"].startswith("wxplot2d")][0]
    check(any(o.startswith("image %t") and " svg" in o for o in plot["outputs"]), f"plots come as SVG: {plot['outputs']}")
    check(d(5)["zoom"] == 150, f"a new worksheet starts at the default zoom: {d(5)['zoom']}")
    s7 = {c["input"].strip(): c for c in d(7)["cells"]}
    check(s7["1/0;"]["outputs"][0].startswith("error") and s7["7;"]["outputs"] == ["math %o3 7"]
          and s7["8;"]["outputs"] == [] and d(7)["state"] == "idle",
          f"abort on error: Cmd+R stops at 1/0; 7; keeps its old (%o3), 8; is not run: {[(k, v['outputs']) for k, v in s7.items()]}")
elif script == "bottom-scroll":
    d1, d2, d3 = dump("bottom", 1), dump("bottom", 2), dump("bottom", 3)
    last = d1["cells"][-1]
    check(len(d1["cells"]) == 16 and last["input"] == "a;\nb;\nc;\nd;\ne;" and last["focused"],
          f"16 cells, five lines in the last: {last['input']!r}")
    check(d1["caret"]["visible"], f"after Return at the bottom, the new line is in view: {d1['caret']}")
    check(d2["caret"]["visible"], f"a line that wraps at the bottom stays in view: {d2['caret']}")
    check(d3["caret"]["visible"], f"after Cmd+Z, the caret is in view: {d3['caret']}")
elif script == "l10n-es":
    d1, d2 = dump("l10n", 1), dump("l10n", 2)
    bar = d1["menuBar"]
    check(all(m in bar for m in ["Archivo", "Edición", "Celda", "Formato", "Maxima", "Ventana", "Ayuda"]),
          f"the menu bar is in Spanish, macOS's menus too: {bar}")
    check(d1["stateLabel"] == "Listo", f"the toolbar says Listo: {d1['stateLabel']!r}")
    first = d1["cells"][0]["outputs"]
    check(bool(first) and "Paréntesis desequilibrados" in first[0] and "línea 1, columna" in first[0],
          f"Macsima's own syntax error is in Spanish: {first}")
    check(d1["cells"][1]["outputs"][0].startswith("error maxima expt:"), "Maxima's messages stay as Maxima prints them")
    check(d2["find"]["visible"] and d2["find"]["status"] == "No hay coincidencias",
          f"the find bar is open and says No hay coincidencias: {d2['find']}")
elif script == "checkpoint-a":
    import os
    check(all(os.path.exists(f"docs/phase3-screenshots/{n}") for n in ["03-bracket-match.png", "04-find.png"]),
          "the screenshots were taken")
else:
    sys.exit(f"unknown script {script}")
print("PASS" if failures == 0 else f"FAIL ({failures})")
sys.exit(1 if failures else 0)
