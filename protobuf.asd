
;;;;    protobuf.asd


;; Copyright 2010, Google Inc. All rights reserved.

;; Redistribution and use in source and binary forms, with or without
;; modification, are permitted provided that the following conditions are
;; met:

;;     * Redistributions of source code must retain the above copyright
;; notice, this list of conditions and the following disclaimer.
;;     * Redistributions in binary form must reproduce the above
;; copyright notice, this list of conditions and the following disclaimer
;; in the documentation and/or other materials provided with the
;; distribution.
;;     * Neither the name of Google Inc. nor the names of its
;; contributors may be used to endorse or promote products derived from
;; this software without specific prior written permission.

;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;; A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;; OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
;; LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
;; DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
;; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
;; (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
;; OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


(cl:in-package #:common-lisp-user)

(defpackage #:protobuf-system
  (:documentation "System definitions for protocol buffer code.")
  (:use #:common-lisp #:asdf))

(in-package #:protobuf-system)


;;; Teach ASDF how to convert protocol buffer definition files into Lisp.


(defparameter *protoc* #p"google-protobuf/src/protoc"
   "Pathname of the protocol buffer compiler.")

(defclass proto-file (cl-source-file)
  ((relative-proto-pathname
    :initarg :proto-pathname
    :initform nil
    :reader proto-pathname
   :documentation "Relative pathname that specifies a protobuf .proto file")
   (search-path
    :initform ()
    :initarg :proto-search-path
    :reader search-path
    :documentation "List containing directories in which the protocol buffer
compiler should search for imported protobuf files."))
  (:documentation "A protocol buffer definition file."))

(defclass proto-to-lisp (operation)
  ()
  (:documentation "An ASDF operation that compiles a file containing protocol
buffer definitions into a Lisp source code."))

(defmethod component-depends-on ((operation compile-op) (component proto-file))
  "Compiling a protocol buffer file depends on compiling dependencies and
converting the protobuf file into Lisp source code."
  (append
   `((compile-op "package" "base" "protocol-buffer" "varint" "wire-format")
     (proto-to-lisp ,(component-name component)))
   (call-next-method)))

(defmethod component-depends-on ((operation load-op) (component proto-file))
  "Loading a protocol buffer file depends on loading dependencies and
converting the protobuf file into Lisp source code."
  (append
   `((load-op "package" "base" "protocol-buffer" "varint" "wire-format")
     (proto-to-lisp ,(component-name component)))
   (call-next-method)))

(defun proto-input (proto-file)
  "Return the pathname of the protocol buffer definition file that must be
translated into Lisp source code for this PROTO-FILE component."
  (if (proto-pathname proto-file)
      ;; Path of the protobuf file was specified with :PROTO-PATHNAME.
      (merge-pathnames
       (make-pathname :type "proto")
       (merge-pathnames (pathname (proto-pathname proto-file))
                        (asdf::component-parent-pathname proto-file)))
      ;; No :PROTO-PATHNAME was specified, to the path of the protobuf
      ;; defaults to that of the Lisp file, but with a ".proto" suffix.
      (let ((lisp-pathname (component-pathname proto-file)))
        (merge-pathnames (make-pathname :type "proto") lisp-pathname))))

(defmethod input-files ((operation proto-to-lisp) (component proto-file))
  (list *protoc* (proto-input component)))

(defmethod output-files ((operation proto-to-lisp) (component proto-file))
  (list (component-pathname component)))

(defmethod perform ((operation proto-to-lisp) (component proto-file))
  (let* ((source-file (proto-input component))
         (output-file (component-pathname component))
         (search-path (cons (directory-namestring source-file)
                            (search-path component)))
         (status
          (run-shell-command "~A --proto_path=~{~A~^:~} --lisp_out=~A ~A"
                             (namestring *protoc*)
                             search-path
                             (directory-namestring output-file)
                             (namestring source-file))))
    (unless (zerop status)
      (error 'compile-failed :component component :operation operation))))

(defmethod asdf::component-self-dependencies ((op load-op) (c proto-file))
  "Remove PROTO-TO-LISP operations from self dependencies.  Otherwise, the
.lisp output files of PROTO-TO-LISP are considered to be input files for
LOAD-OP, which means ASDF loads both the .lisp file and the .fasl file."
  (remove-if (lambda (x)
               (eq (car x) 'proto-to-lisp))
             (call-next-method)))


;;; A Common Lisp implementation of Google's protocol buffers


(defsystem protobuf
  :name "Protocol Buffer"
  :description "Protocol buffer code"
  :long-description "A Common Lisp implementation of Google's protocol
buffer compiler and support libraries."
  :version "0.3.3"
  :author "Robert Brown"
  :licence "See file COPYING and the copyright messages in individual files."

  ;; After loading the system, announce its availability.
  :perform (load-op :after (operation component)
             (pushnew :protobuf cl:*features*)
             (provide 'protobuf))

  :depends-on (#-(or allegro clisp sbcl) :trivial-utf-8)

  :components
  ((:static-file "COPYING")
   (:static-file "README")
   (:static-file "TODO")
   (:static-file "golden")

   (:cl-source-file "package")

   #-(or abcl allegro cmu sbcl)
   (:module "sysdep"
    :pathname ""           ; this module's files are not in a subdirectory
    :depends-on ("package")
    :components ((:cl-source-file "portable-float")))

   (:cl-source-file "optimize" :depends-on ("package"))
   (:cl-source-file "base" :depends-on ("package" "optimize"))
   (:cl-source-file "varint"  :depends-on ("package" "optimize" "base"))
   (:cl-source-file "varint-test" :depends-on ("package"))
   (:cl-source-file "protocol-buffer" :depends-on ("package"))
   (:cl-source-file "message-test"
    :depends-on ("optimize" "base" "protocol-buffer" "unittest"))
   ;; The varint dependency is needed because some varint functions are
   ;; declared in line and so must be loaded before wire-format is compiled.
   (:cl-source-file "wire-format"
    :depends-on ("package" "base" "optimize" "varint"
                 #-(or abcl allegro cmu sbcl) "sysdep"))
   (:cl-source-file "wire-format-test" :depends-on ("package" "optimize"))

   ;; Old protocol buffer tests
   ;; XXXX: Delete these when the new proto2 tests cover all the functionality.

   (:cl-source-file "proto-lisp-test"
    :depends-on ("base" "testproto1" "testproto2"))
   ;; Two protocol buffers used by the old tests.
   (:proto-file "testproto1")
   (:proto-file "testproto2")

   ;; Test protocol buffers and protobuf definitions used by the proto2
   ;; compiler.

   (:proto-file "descriptor"
    :proto-pathname "google-protobuf/src/google/protobuf/descriptor")
   (:proto-file "unittest_import"
    :proto-pathname "google-protobuf/src/google/protobuf/unittest_import")
   (:proto-file "unittest"
    :proto-pathname "google-protobuf/src/google/protobuf/unittest"
    :depends-on ("unittest_import")
    :proto-search-path ("google-protobuf/src/"))
   ))
