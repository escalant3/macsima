# Glue Lisp

`wxMathML.lisp` is copied unmodified from wxMaxima, with its copyright notices and its
`SPDX-License-Identifier: GPL-2.0+` header intact:

- Source: https://github.com/wxMaxima-developers/wxmaxima/blob/13e4aee209774c280bca064256a2578af969f3f6/src/wxMathML.lisp
- Commit: `13e4aee209774c280bca064256a2578af969f3f6` (main, committed 2026-10-18T11:12:44Z), fetched 2026-10-18.
- Copyright: Andrej Vodopivec (2004-2014), Gunter Koenigsmann (2014-2023), Robert Dodier (2019-2020),
  David Drysdale (MathML printer), and the mactex.lisp authors credited in the file. License GPL-2.0-or-later.

It is sent to Maxima the way wxMaxima does it (`wxMathml.cpp`, `wxMathML::GetCmd`): `;` comments outside
strings and leading indentation are removed, the lines are joined with spaces, and the result is sent
as a single `:lisp-quiet ...` line. Do not edit the file in place; if the app needs changes, keep them in
a separate file so updates from wxMaxima stay a plain copy.
