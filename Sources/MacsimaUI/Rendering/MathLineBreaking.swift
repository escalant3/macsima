// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation

/// The script that breaks math wider than its page into lines. It follows
/// wxMaxima's approach (Cell::BreakLines_List and BreakUpCells in
/// src/cells/Cell.cpp), written anew for MathML:
///
/// - Math that fits stays one 2D expression, untouched.
/// - Otherwise the expression is cut into pieces, each drawn as its own
///   `<math>` in a wrapping flex box, so lines break between pieces.
/// - A piece wider than a line is broken up, as wxMaxima's BreakUp() turns
///   a cell into its linear form: a row (sum, list, function call, brackets)
///   into its parts, a fraction into `(a)/(b)`, a root into `sqrt(a)`, a
///   power of a wide base into `(a)^b`. Matrices, sums, integrals and limits
///   keep their 2D form (their body is a separate piece and breaks).
/// - Lines break before `+` and `−`, and after `=`, `,`, `:=` and other
///   relations. A term still wider than a line breaks between its factors,
///   where the hidden multiplication sign becomes a visible `⋅` at the end
///   of the line (wxMaxima's GH #2263).
/// - Continuation lines start at the math column, after the label column,
///   as wxMaxima indents them by the label width.
///
/// `layoutMath(width)` lays the page out for a row `width` CSS pixels wide
/// (0: no breaking) and returns the width on one line; `measureMath()`
/// returns `[width, height]` as drawn.
enum MathLineBreaking {
    static let script = #"""
    const NS = 'http://www.w3.org/1998/Math/MathML';
    const OPEN = new Set(['(', '[', '{', '⟨', '|']);
    const CLOSE = new Set([')', ']', '}', '⟩', '|']);
    const BEFORE = new Set(['+', '−', '-', '±', '∓']);
    const AFTER = new Set(['=', ',', ':=', ':', '::=', '<', '>', '≤', '≥', '≠', '→', ';', '#',
                           'and', 'or', '∧', '∨']);
    const row = document.querySelector('.row');
    const box = document.querySelector('.m');
    const label = document.querySelector('.lbl');
    const template = box.firstElementChild.cloneNode(true);

    function text(e) { return e.textContent.trim(); }
    function isThinSpace(e) { return e.localName === 'mspace' && e.getAttribute('width') === '0.17em'; }
    // Elements the line breaking adds (brackets, "/", "sqrt", dots) carry the class "lb".
    function el(name, content, form) {
      const e = document.createElementNS(NS, name);
      e.setAttribute('class', 'lb');
      e.textContent = content;
      if (name === 'mo') e.setAttribute('stretchy', 'false');
      if (form) e.setAttribute('form', form);
      return e;
    }
    function setForm(e, form) { if (!e.hasAttribute('form')) e.setAttribute('form', form); }

    // A piece is { e: element, kind }. The kind says where a line may break:
    // open (never after), close (never before), before (break before),
    // after (break after), weak (a hidden multiplication: break after, only
    // in a term wider than a line), glue (never around), atom.
    function piecesOfRow(kids) {
      const n = kids.length;
      return kids.map((e, i) => {
        let kind = 'atom';
        if (e.localName === 'mspace') {
          kind = isThinSpace(e) ? 'weak' : 'glue';
        } else if (e.localName === 'mo') {
          const t = text(e);
          // Function application, invisible times, the dot between numbers.
          if (t === '⁡' || t === '⁢' || t === '⋅' || t === '') {
            kind = 'glue';
          } else if (i === 0) {
            kind = 'open'; setForm(e, 'prefix');
          } else if (i === n - 1) {
            kind = 'close'; setForm(e, 'postfix');
          } else {
            // The form the operator had inside its row, so it keeps its spacing alone.
            setForm(e, 'infix');
            kind = BEFORE.has(t) ? 'before' : AFTER.has(t) ? 'after' : 'atom';
          }
          if (OPEN.has(t) || CLOSE.has(t)) e.setAttribute('stretchy', 'false');
        }
        return { e, kind };
      });
    }

    function isCompound(e) { return e.localName === 'mrow' && e.children.length > 1; }
    // A fraction's numerator or denominator in its linear form: its parts
    // flow on the line, in brackets if there are several.
    function parenthesized(e) {
      e = unwrap(e);
      if (!isCompound(e)) return [{ e, kind: 'atom' }];
      return [{ e: el('mo', '(', 'prefix'), kind: 'open' }, ...piecesOfRow(Array.from(e.children)),
              { e: el('mo', ')', 'postfix'), kind: 'close' }];
    }
    function unwrap(e) {
      while (e.localName === 'mrow' && e.children.length === 1) e = e.firstElementChild;
      return e;
    }
    function isFenced(kids) {
      return kids.length > 2 && kids[0].localName === 'mo' && OPEN.has(text(kids[0]))
        && kids[kids.length - 1].localName === 'mo' && CLOSE.has(text(kids[kids.length - 1]));
    }

    // The linear form of a piece too wide for a line, or null when it has none.
    function breakUp(e, width) {
      const kids = Array.from(e.children);
      switch (e.localName) {
      case 'mrow': case 'mstyle':
        if (kids.length === 0) return null;
        return kids.length === 1 ? [{ e: kids[0], kind: 'atom' }] : piecesOfRow(kids);
      case 'mfrac':
        if (kids.length !== 2 || e.getAttribute('linethickness') === '0') return null;
        return [...parenthesized(kids[0]), { e: el('mo', '/', 'infix'), kind: 'atom' }, ...parenthesized(kids[1])];
      case 'msqrt': {
        const body = kids.filter(k => k.localName !== 'mpadded');   // the radical's strut
        const inner = document.createElementNS(NS, 'mrow');
        inner.append(...body);
        return [{ e: el('mi', 'sqrt'), kind: 'atom' }, { e: el('mo', '(', 'prefix'), kind: 'open' },
                { e: inner, kind: 'atom' }, { e: el('mo', ')', 'postfix'), kind: 'close' }];
      }
      case 'msup': {
        if (kids.length !== 2) return null;
        const base = unwrap(kids[0]);
        // Only a wide base helps; the exponent stays on the closing bracket.
        if (base.getBoundingClientRect().width < width / 2) return null;
        const parts = isFenced(Array.from(base.children)) ? piecesOfRow(Array.from(base.children))
          : [{ e: el('mo', '(', 'prefix'), kind: 'open' }, { e: base, kind: 'atom' }, { e: el('mo', ')', 'postfix'), kind: 'close' }];
        const last = parts.pop();
        const sup = document.createElementNS(NS, 'msup');
        sup.setAttribute('class', 'lb');
        sup.append(last.e, kids[1]);
        parts.push({ e: sup, kind: 'close' });
        return parts;
      }
      default:
        return null;
      }
    }

    // 2 = a line may break between a and b, 1 = only inside a term wider than a line, 0 = never.
    function breakBetween(a, b) {
      if (a.kind === 'open' || a.kind === 'glue' || a.kind === 'before') return 0;
      if (b.kind === 'close' || b.kind === 'glue' || b.kind === 'after' || b.kind === 'weak') return 0;
      if (a.kind === 'after' || b.kind === 'before') return 2;
      return a.kind === 'weak' ? 1 : 0;
    }

    function mathFor(piece) {
      const m = document.createElementNS(NS, 'math');
      m.setAttribute('display', 'block');
      m.append(piece.e);
      return m;
    }

    // Draws words (lists of pieces), each a span that never breaks inside.
    // WebKit sizes math around a stretchy bracket for its widest form and
    // centers the content in that box; each piece gets the width its
    // content takes, or lines would show gaps.
    function draw(words) {
      box.replaceChildren(...words.map(word => {
        const span = document.createElement('span');
        span.className = 'w';
        span.append(...word.map(mathFor));
        return span;
      }));
      const maths = Array.from(box.querySelectorAll('.w > math'));
      const widths = maths.map(m => m.firstElementChild ? m.firstElementChild.getBoundingClientRect().width : 0);
      maths.forEach((m, i) => { if (m.firstElementChild) m.style.width = widths[i] + 'px'; });
    }

    function widthsOf(pieces) {
      draw(pieces.map(p => [p]));
      return Array.from(box.querySelectorAll('.w')).map(w => w.getBoundingClientRect().width);
    }

    // Words: pieces between the places a line may break.
    function words(pieces, widths, limit) {
      const out = [];
      let word = [], weak = [], width = 0;
      const flush = () => {
        if (width > limit && weak.length > 0) {
          // A term wider than a line: break it between its factors too.
          let start = 0;
          for (const cut of weak) { out.push(word.slice(start, cut)); start = cut; }
          out.push(word.slice(start));
        } else if (word.length > 0) {
          out.push(word);
        }
        word = []; weak = []; width = 0;
      };
      pieces.forEach((p, i) => {
        const b = i > 0 ? breakBetween(pieces[i - 1], p) : 0;
        if (b === 2) flush();
        else if (b === 1) weak.push(word.length);
        word.push(i);
        width += widths[i];
      });
      flush();
      return out;
    }

    function lineBreak(limit) {
      const body = document.createElementNS(NS, 'mrow');
      body.append(...template.cloneNode(true).children);
      let pieces = [{ e: body, kind: 'atom' }];
      for (let round = 0; round < 200; round++) {
        const widths = widthsOf(pieces);
        // Break up every piece wider than a line...
        let next = [], changed = false;
        pieces.forEach((p, i) => {
          const linear = widths[i] > limit ? breakUp(p.e, widths[i]) : null;
          if (linear) { next.push(...linear); changed = true; } else next.push(p);
        });
        if (!changed) {
          // ...then, in a word still wider than a line, its widest piece that has a linear form.
          for (const word of words(pieces, widths, limit)) {
            const total = word.reduce((s, i) => s + widths[i], 0);
            if (total <= limit || word.length < 2) continue;
            const widest = word.filter(i => ['mrow', 'mfrac', 'msqrt'].includes(pieces[i].e.localName) && pieces[i].e.children.length > 0)
              .sort((a, b) => widths[b] - widths[a])[0];
            if (widest === undefined) continue;
            const linear = breakUp(pieces[widest].e, widths[widest]);
            if (linear) { next = [...pieces.slice(0, widest), ...linear, ...pieces.slice(widest + 1)]; changed = true; break; }
          }
        }
        if (!changed) {
          draw(words(pieces, widths, limit).map(w => w.map(i => pieces[i])));
          return;
        }
        pieces = next;
      }
    }

    // A hidden multiplication ending a line is shown as a dot.
    function showDotsAtLineEnds() {
      for (let pass = 0; pass < 3; pass++) {
        const spans = Array.from(box.children);
        let changed = false;
        for (let i = 0; i + 1 < spans.length; i++) {
          const last = spans[i].lastElementChild?.firstElementChild;
          if (!last || !isThinSpace(last)) continue;
          if (spans[i + 1].getBoundingClientRect().left < spans[i].getBoundingClientRect().right - 1) {
            last.replaceWith(el('mo', '⋅', 'infix'));
            changed = true;
          }
        }
        if (!changed) return;
      }
    }

    // For checks (macsima-render verify): [lines, text of the math without
    // what line breaking added, text of the math as given].
    function lineBreakReport() {
      let lines = box.children.length > 0 ? 1 : 0;
      const spans = Array.from(box.children);
      for (let i = 1; i < spans.length; i++) {
        if (spans[i].getBoundingClientRect().left < spans[i - 1].getBoundingClientRect().right - 1) lines++;
      }
      const kept = node => node.nodeType === Node.TEXT_NODE ? node.textContent
        : node.getAttribute?.('class') === 'lb' && node.childElementCount === 0 ? ''
        : Array.from(node.childNodes).map(kept).join('');
      const squash = t => t.replace(/[\s\u2061\u2062]/g, '');
      return [lines, squash(kept(box)), squash(template.textContent)];
    }

    // Lays the math out for a row `width` CSS pixels wide (0: never break);
    // returns the width of the math on one line.
    function layoutMath(width) {
      box.classList.remove('wrapped');
      row.classList.remove('wrapped');
      box.style.width = '';
      box.replaceChildren(template.cloneNode(true));
      const natural = Math.ceil(row.getBoundingClientRect().width);
      if (width <= 0 || natural <= width) return natural;
      const style = getComputedStyle(row);
      const limit = Math.max(150, width - label.getBoundingClientRect().width - parseFloat(style.columnGap)
        - parseFloat(style.paddingRight) - 1);
      row.classList.add('wrapped');
      box.classList.add('wrapped');
      box.style.width = limit + 'px';
      lineBreak(limit);
      showDotsAtLineEnds();
      return natural;
    }

    // [width, height] of what is drawn: when the math is broken into lines,
    // the longest line, not the width it may use.
    function measureMath() {
      const rect = row.getBoundingClientRect();
      if (!row.classList.contains('wrapped')) return [Math.ceil(rect.width), Math.ceil(rect.height)];
      let right = label.getBoundingClientRect().right;
      for (const w of box.children) right = Math.max(right, w.getBoundingClientRect().right);
      return [Math.ceil(right - rect.left + parseFloat(getComputedStyle(row).paddingRight)), Math.ceil(rect.height)];
    }

    // Where each numbered element was drawn, for selecting parts of the math:
    // [number, x, y, width, height, ...]. An element split over lines appears
    // once per piece.
    function measureParts() {
      const out = [];
      for (const e of document.querySelectorAll('[data-p]')) {
        const r = e.getBoundingClientRect();
        if (r.width <= 0 || r.height <= 0) continue;
        out.push(+e.getAttribute('data-p'), r.left, r.top, r.width, r.height);
      }
      return out;
    }
    """#
}
