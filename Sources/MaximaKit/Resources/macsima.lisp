;; SPDX-License-Identifier: GPL-2.0-or-later
;; Macsima's own Lisp, sent after wxMathML.lisp (which stays a plain copy).
;; Every function prints one tagged reply and nothing else; they are sent as
;; :lisp-quiet lines, which use up no input label and get no prompt.
;; Like wxMathML.lisp, the definitions sit inside <suppressOutput>, so
;; compiler notes (which quote the source, tag names and all) are never
;; read as replies. The tags are spelled with code-char for the same reason.
(format t "~:@csuppressOutput~:@c~%" (code-char 60) (code-char 62))

;; The manual's entries for TOPIC, without describe's question when there
;; are several (diff has three): every exact match, with its section, and
;; the inexact matches as related topics. Uses Maxima's own index and
;; reader (cl-info.lisp, Maxima 5.50.0), so the text is what describe prints.
(defun macsima-help (topic)
  (format t "<macsima-help><topic>~a</topic>" (wxxml-fix-string topic))
  (handler-case
      (let* ((exact (cl-info::rearrange-matches (cl-info::exact-topic-match topic)))
             (inexact (cl-info::rearrange-matches (cl-info::inexact-topic-match topic)))
             (names (mapcar (lambda (item) (first (second item))) exact)))
        (dolist (item exact)
          (let ((text (ignore-errors (cl-info::read-info-text (first item) (second item)))))
            (when text
              (format t "<entry><name>~a</name><section>~a</section><text>~a</text></entry>"
                      (wxxml-fix-string (first (second item)))
                      (wxxml-fix-string (or (nth 4 (second item)) ""))
                      (wxxml-fix-string text)))))
        (let ((related (remove-duplicates
                        (remove-if (lambda (name) (member name names :test #'string=))
                                   (mapcar (lambda (item) (first (second item))) inexact))
                        :test #'string= :from-end t)))
          (format t "<related>~{<name>~a</name>~}</related>"
                  (mapcar #'wxxml-fix-string (subseq related 0 (min 60 (length related)))))))
    (error (condition)
      (format t "<error>~a</error>" (wxxml-fix-string (format nil "~a" condition)))))
  (format t "</macsima-help>~%")
  (finish-output))

;; The values of the watched variables NAMES (Maxima names, as typed): one
;; <variable> each, in linear form as wxMaxima's wx-query-variable prints
;; them (display2d false, no line breaks). A name with no value but a
;; function definition gets that instead; one with neither, <unbound/>.
;; Values longer than 4000 characters are cut, marked <cut/>.
(defun macsima-values (names)
  (format t "<macsima-values>")
  (dolist (name names)
    (let ((symbol (intern (concatenate 'string "$" (maybe-invert-string-case name)) :maxima)))
      (format t "<variable><name>~a</name>" (wxxml-fix-string name))
      (handler-case
          (let* (($display2d nil) ($linel 1000000)
                 (kind (cond ((boundp symbol) "value")
                             ((or (mget symbol 'mexpr) (mget symbol 'mmacro)) "function")))
                 (text (cond ((equal kind "value") ($sconcat (symbol-value symbol)))
                             (kind ($sconcat (meval `(($fundef) ,symbol)))))))
            (if (null kind)
                (format t "<unbound/>")
                (progn
                  (format t "<kind>~a</kind>" kind)
                  (when (> (length text) 4000)
                    (setq text (subseq text 0 4000))
                    (format t "<cut/>"))
                  (format t "<value>~a</value>" (wxxml-fix-string text)))))
        (error (condition)
          (format t "<error>~a</error>" (wxxml-fix-string (format nil "~a" condition)))))
      (format t "</variable>")))
  (format t "</macsima-values>~%")
  (finish-output))

;; The names of the user's variables (Maxima's values list), for Add All.
(defun macsima-variable-names ()
  (format t "<macsima-variable-names>~{<name>~a</name>~}</macsima-variable-names>~%"
          (mapcar (lambda (symbol) (wxxml-fix-string (maybe-invert-string-case (subseq (symbol-name symbol) 1))))
                  (remove-if-not #'symbolp (cdr $values))))
  (finish-output))

;; Plots for a Retina screen: wxplot2d and friends draw with pngcairo at
;; twice $wxplot_size's pixels (fonts and lines twice as large too), and the
;; image is marked ppi="192" so it shows at the size a 96 ppi plot of
;; $wxplot_size would have (wxMaxima reads ppi the same way). Replaces the
;; glue's $wxplot_preamble and wxxml-tag (wxMathML.lisp, wxMaxima 13e4aee);
;; draw's plots don't use the preamble and stay as they are, unmarked.
(defvar *macsima-plot-scale* 2)
(defvar *macsima-scaled-plot* nil)

(defun $wxplot_preamble ()
  (let ((w ($first $wxplot_size)) (h ($second $wxplot_size)) (k *macsima-plot-scale*))
    (cond ((and (not $wxplot_usesvg) $wxplot_pngcairo)
           (setq *macsima-scaled-plot* t)
           (format nil "set terminal pngcairo dashed background \"white\" enhanced font \"arial,10\" fontscale ~d linewidth ~d size ~d,~d; set zeroaxis;"
                   k k (* k w) (* k h)))
          ((not $wxplot_usesvg) (format nil "set terminal png size ~d,~d; set zeroaxis;" w h))
          (t (format nil "set terminal svg size ~d,~d; set zeroaxis;" w h)))))

(defun wxxml-tag (x l r)
  (let* ((name (cadr x))
         (tag (caddr x))
         (prop (cadddr x))
         (image (member tag '("img" "slide") :test #'equal)))
    (when (and image *macsima-scaled-plot*)
      (setq prop (if prop (format nil "~a ppi=\"~d\"" prop (* 96 *macsima-plot-scale*))
                     (format nil "ppi=\"~d\"" (* 96 *macsima-plot-scale*)))))
    (when image (setq *macsima-scaled-plot* nil))
    (if prop
        (append l (list (format nil "<~a ~a lisp=\"wxxml-tag\">~a</~a>" tag prop name tag)) r)
        (append l (list (format nil "<~a lisp=\"wxxml-tag\">~a</~a>" tag name tag)) r))))

(format t "~:@c/suppressOutput~:@c~%" (code-char 60) (code-char 62))
(finish-output)
