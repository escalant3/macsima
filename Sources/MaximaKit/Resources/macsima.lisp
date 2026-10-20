;; SPDX-License-Identifier: GPL-2.0-or-later
;; Macsima's own Lisp, sent after wxMathML.lisp (which stays a plain copy).
;; Every function prints one tagged reply and nothing else; they are sent as
;; :lisp-quiet lines, which use up no input label and get no prompt.

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
