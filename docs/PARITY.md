# Feature parity with wxMaxima

Filled in during Phase 2, step 7. Until then this file lists what the math translator does not handle.

## Math XML translator (WXMLKit)

Tags the translator does not know render as their text content (never dropped) and are listed here.

| Tag | Emitted by wxMathML.lisp for | Status |
| --- | --- | --- |
| `slide` | animations (`wxanimate`, `with_slider_draw`) | missing: text only |
