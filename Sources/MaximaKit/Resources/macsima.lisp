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

(format t "~:@c/suppressOutput~:@c~%" (code-char 60) (code-char 62))
(finish-output)
