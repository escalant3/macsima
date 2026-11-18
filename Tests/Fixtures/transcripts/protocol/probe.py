#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# An independent client for Maxima's -s socket protocol, sharing no code with
# MaximaKit. It checks the claims in docs/MAXIMA_PROTOCOL.md against a real
# Maxima and writes the results and every exchange after setup as JSON.
#
#   python3 -I Tests/Fixtures/transcripts/protocol/probe.py Tests/Fixtures/transcripts/protocol/session.json
import json, os, re, select, signal, socket, subprocess, sys, tempfile, time

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
TOKEN = "PROTOCOL-DOC-TOKEN"
out_path = sys.argv[1]


def one_line(path):
    # Same framing as GlueLisp.command(from:).
    res, in_string = [], False
    for line in open(path, encoding="utf-8").read().split("\n"):
        if not line:
            continue
        kept, i, start = "", 0, True
        while i < len(line):
            c = line[i]
            if start and c in " \t":
                i += 1
                continue
            start = False
            if c == "\\":
                kept += line[i:i + 2]
                i += 2
                continue
            if c == '"':
                in_string = not in_string
            if c == ";" and not in_string:
                break
            kept += c
            i += 1
        res.append(kept + " ")
    return ":lisp-quiet " + "".join(res) + "\n"


tmp = tempfile.mkdtemp(prefix="macsima-probe-")
srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0))
srv.listen(5)
port = srv.getsockname()[1]
env = dict(os.environ, MAXIMA_AUTH_CODE=TOKEN, TMPDIR=tmp + "/")
t0 = time.time()
proc = subprocess.Popen(["/opt/homebrew/bin/maxima", "-s", str(port)], env=env, stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
srv.settimeout(20)
ctl, _ = srv.accept()
connect_s = time.time() - t0
ctl.setblocking(False)


def read(quiet=1.0, limit=30.0, until=None):
    buf, start, last = b"", time.time(), time.time()
    while time.time() - start < limit and time.time() - last < quiet:
        r, _, _ = select.select([ctl], [], [], 0.05)
        if r:
            d = ctl.recv(1 << 16)
            if not d:
                break
            buf += d
            last = time.time()
            if until and re.search(until, buf):
                quiet = min(quiet, 0.3)
    return buf.decode("utf-8", "replace")


def send(s):
    ctl.setblocking(True)
    ctl.sendall(s.encode())
    ctl.setblocking(False)


results, log = {}, []


def step(name, lines, quiet=1.2, limit=30.0):
    for l in lines:
        send(l + "\n")
    got = read(quiet, limit)
    log.append({"step": name, "sent": lines, "received": got})
    return got


banner = read(1.5, 8)
results["connect_seconds"] = round(connect_s, 2)
results["first_line"] = re.sub(r"\d+", "N", banner.split("\n")[0])
results["bare_first_prompt_unwrapped"] = "(%i1)" in banner and "<PROMPT>" not in banner

glue = one_line(f"{REPO}/Sources/MaximaKit/Resources/wxMathML.lisp")
own = one_line(f"{REPO}/Sources/MaximaKit/Resources/macsima.lisp")
results["glue_line_bytes"] = len(glue.encode())
results["macsima_line_bytes"] = len(own.encode())
send(glue)
setup = read(2.5, 40, until=rb"</variables>")
results["setup_output_bytes"] = len(setup.encode())
m = re.search(r"<suppressOutput>(.*?)</suppressOutput>", setup, re.S)
results["key_nested_in_suppressOutput"] = bool(m and f"<wxxml-key>{TOKEN}</wxxml-key>" in m.group(1))
results["tags_during_setup"] = sorted(set(re.findall(r"^<([a-zA-Z-]+)>", setup, re.M)))
results["prompt_after_glue"] = "<PROMPT>" in setup

for l in [':lisp-quiet (setf $gnuplot_command "/opt/homebrew/bin/gnuplot")\n',
          f':lisp-quiet (setf $maxima_tempdir "{tmp}")\n',
          f':lisp-quiet (when (fboundp \'wx-open-interrupt-channel) (wx-open-interrupt-channel "127.0.0.1" {port} "{TOKEN}"))\n',
          ':lisp-quiet (ignore-errors (setf (symbol-value \'*lisp-quiet-suppressed-prompt*) "<PROMPT>(%i1)</PROMPT>"))\n',
          ':lisp-quiet (setf *prompt-suffix* "</PROMPT>") (setf *prompt-prefix* "<PROMPT>") (setf $in_netmath nil) (setf $show_openplot t) \n']:
    send(l)
srv.settimeout(5)
try:
    chan, _ = srv.accept()
    chan.settimeout(3)
    first = b""
    while b"\n" not in first:
        first += chan.recv(4096)
    results["interrupt_channel_first_line_is_token"] = first.strip().decode() == TOKEN
except Exception as e:
    chan = None
    results["interrupt_channel_error"] = repr(e)
send(own)
results["setup_lines_output"] = read(2.0, 10)[:200]

g = step("lisp-quiet gets no prompt", [":lisp-quiet (setq $linel 80)"])
results["lisp_quiet_no_prompt"] = "<PROMPT>" not in g

g = step("plain statement", ["integrate(sin(x), x);"])
results["statement_math_then_prompt"] = bool(re.search(r"<math>.*</math>\s*<PROMPT>\(%i\d+\) </PROMPT>", g, re.S))

g = step("dollar statement prints only a prompt", ["a:3$"])
results["dollar_no_math"] = "<math>" not in g and "<PROMPT>" in g

g = step("print is plain text", ['print("hello")$'])
results["print_string_is_math"] = "<math><st>hello</st>" in g

g = step("math error", ["1/0;"])
results["maxima_error_text"] = "-- an error." in g and "<PROMPT>" in g

g = step("syntax error", ["x+;"])
results["syntax_error_text"] = "incorrect syntax:" in g
results["syntax_error_prompt"] = "<PROMPT>" in g

g = step("lisp line prompt", [":lisp (+ 1 2)"])
results["lisp_line_prompt_repr"] = re.findall(r"<PROMPT>(.*?)</PROMPT>", g, re.S)

# The break-command quirk.
g = step("break command right after :lisp-quiet", [":lisp-quiet (setq $linel 80)", ":info :bkpt"], quiet=3)
results["break_after_quiet_prompts"] = len(re.findall(r"<PROMPT>", g))
results["break_after_quiet_received"] = g[:300]
g = step("recover with :lisp (values)", [":lisp (values)"])
results["recover_prompts"] = len(re.findall(r"<PROMPT>", g))
g = step("statement to reset state", ["1+1;"])
g = step("break command right after a prompt", [":info :bkpt"], quiet=3)
results["break_after_statement_prompts"] = len(re.findall(r"<PROMPT>", g))
results["break_after_statement_received"] = g[:300]
step("settle", [":lisp (values)"], quiet=1.5)
g = step("wrapped break command after :lisp-quiet", [":lisp-quiet (setq $linel 80)", ":lisp-quiet nil", ":info :bkpt", ":lisp (values)"], quiet=2)
results["wrapped_break_prompts"] = len(re.findall(r"<PROMPT>", g))
step("statement", ["2+2;"])
g = step("wrapped break command after a statement", [":lisp-quiet nil", ":info :bkpt", ":lisp (values)"], quiet=2)
results["wrapped_break_after_statement_prompts"] = len(re.findall(r"<PROMPT>", g))

# Questions.
g = step("question", ["asksign(y);"])
pr = re.findall(r"<PROMPT>(.*?)</PROMPT>", g, re.S)
results["question_prompt"] = pr
g = step("lisp-quiet while a question waits", [":lisp-quiet (setq $linel 80)"], quiet=2)
results["quiet_during_question_received"] = g[:500]
g = step("answer", ["pos;"], quiet=2)
results["after_answer_received"] = g[:500]
step("settle", ["2+2;"], quiet=1.5)

# Lisp mode and debugger.
g = step("to_lisp", ["to_lisp();"])
results["to_lisp_prompt"] = re.findall(r"<PROMPT>(.*?)</PROMPT>", g, re.S)
g = step("to-maxima", ["(to-maxima)"])
results["to_maxima_prompt"] = re.findall(r"<PROMPT>(.*?)</PROMPT>", g, re.S)
step("debug setup", ["debugmode(true)$", "h(x):=1/x$"], quiet=1.5)
g = step("enter debugger", ["h(0);"])
results["debugger_prompt"] = re.findall(r"<PROMPT>(.*?)</PROMPT>", g, re.S)
g = step("leave debugger", [":top"])
results["after_top_prompt"] = re.findall(r"<PROMPT>(.*?)</PROMPT>", g, re.S)
step("debug off", ["debugmode(false)$"], quiet=1.5)

# Interrupts.
LONG = "block([s:0], for i:1 thru 2000000000 do s:s+i, s);"
if chan:
    send(LONG + "\n")
    time.sleep(1.5)
    chan.sendall(b"interrupt\n")
    t = time.time()
    g = read(1.5, 15, until=rb"</PROMPT>")
    log.append({"step": "interrupt via channel", "sent": [LONG, "<channel> interrupt"], "received": g})
    results["channel_interrupt_text"] = "User interrupt" in g
    results["channel_interrupt_prompt"] = "<PROMPT>" in g
send(LONG + "\n")
time.sleep(1.5)
os.killpg(proc.pid, signal.SIGINT)
g = read(1.5, 15, until=rb"</PROMPT>")
log.append({"step": "interrupt via SIGINT", "sent": [LONG, "<SIGINT to group>"], "received": re.sub(r"#x[0-9A-Fa-f]+", "#xADDRESS", g)})
results["sigint_text"] = "Interactive interrupt at" in g
results["sigint_prompt"] = "<PROMPT>" in g

# Plots.
g = step("plot", ["wxplot2d(x^2,[x,0,1]);"], quiet=3, limit=20)
imgs = re.findall(r"<img[^>]*>[^<]*</img>", g)
results["plot_img_tag"] = [re.sub(r">.*/", ">TMP/", i) for i in imgs]
log[-1]["received"] = g.replace(tmp, "TMP")

os.killpg(proc.pid, signal.SIGTERM)
try:
    proc.wait(5)
except subprocess.TimeoutExpired:
    os.killpg(proc.pid, signal.SIGKILL)
    proc.wait()
results["group_gone_after_term"] = proc.poll() is not None

home = os.path.expanduser("~")
text = json.dumps({"results": results, "exchanges": log}, indent=1, ensure_ascii=False)
text = text.replace(tmp, "TMP").replace(home, "~")
open(out_path, "w", encoding="utf-8").write(text + "\n")
print(json.dumps(results, indent=1, ensure_ascii=False).replace(tmp, "TMP").replace(home, "~"))
