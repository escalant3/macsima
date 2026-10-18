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
    base = [("code", "x+1;\ny", False), ("text", "Some prose.", False), ("title", "A title", False),
            ("section", "A section", False)]
    check(cells("editor", 1) == [("code", "x+1;\ny", True)], "Return inserts a newline, Shift+Return does not")
    check(cells("editor", 2) == base + [("subsection", "A subsection", False), ("code", "diff(x^3,x);", True)],
          "Cmd+1..4 and Cmd+0 insert text, title, section, subsection and code cells")
    got = cells("editor", 3)
    check(len(got) == 6 and got[5] == ("code", "", True), "Cmd+Z undoes the typing")
    check(cells("editor", 4) == base + [("subsection", "A subsection", True)], "Cmd+Z again undoes the insert")
    check(cells("editor", 5) == base[:3] + [("section", "A section", True)], "Cmd+Shift+Delete deletes the cell")
elif script == "eval-basics":
    d1 = dump("eval", 1)["cells"]
    check([c["label"] for c in d1] == [1, 2, 3, 4], "input labels 1..4")
    check(d1[0]["outputs"] == ["math %o1 -cos(x)"], "integrate gives -cos(x)")
    check(len(d1[1]["outputs"]) == 1 and d1[1]["outputs"][0].startswith("image %t2 png"), "wxplot2d gives a PNG read into the model")
    check(d1[2]["outputs"][0].startswith("error maxima expt: undefined"), "1/0 shows the error with its text")
    check(d1[3]["outputs"] == ["question Is y positive, negative or zero? answer=pos", "math %o4 pos"],
          "asksign answered inline")
    d2, d3 = dump("eval", 2), dump("eval", 3)
    check(d2["state"] == "busy" and d2["running"] == 1, "the long integral is running")
    check(d3["state"] == "idle" and d3["cells"][4]["outputs"] == ["error interrupted Interrupted"], "Cmd+. interrupts it")
    d4 = dump("eval", 4)
    check([c["label"] for c in d4["cells"]] == [1, 2, 3, 4, -1], "after Restart, Cmd+R relabels from 1 in order")
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
else:
    sys.exit(f"unknown script {script}")
print("PASS" if failures == 0 else f"FAIL ({failures})")
sys.exit(1 if failures else 0)
