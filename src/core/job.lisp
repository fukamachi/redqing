(in-package :cl-user)
(defpackage redqing.job
  (:use #:cl)
  (:import-from #:local-time
                #:timestamp-to-unix
                #:now)
  (:export #:job
           #:job-id
           #:job-options
           #:perform
           #:encode-job
           #:decode-job))
(in-package :redqing.job)

(defun generate-random-id (&optional (length 12))
  (format nil "~(~36,8,'0R~)" (random (expt 36 length))))

(defun symbol-name-with-package (symbol)
  (let ((package (symbol-package symbol)))
    (unless package
      (error "Uninterned symbol is not allowed"))
    (format nil "~A::~A"
            (package-name package)
            (symbol-name symbol))))

(defclass job ()
  ((id :initarg :id
       :initform (generate-random-id)
       :accessor job-id)
   (options :initarg :options
            :initform '()
            :accessor job-options)))

(defgeneric perform (job &rest args)
  (:method ((job job) &rest args)
    (declare (ignore args))
    (error "PEFORM is not implemented for ~S" (class-name (class-of job)))))

(defgeneric encode-job (job args)
  (:method ((job job) args)
    (let ((job-class (class-name (class-of job))))
      `(("class" . ,(symbol-name-with-package job-class))
        ("args" . ,args)
        ("jid" . ,(job-id job))
        ("created_at" . ,(timestamp-to-unix (now)))
        ,@(job-options job)))))

(defun decode-job (job-info)
  (let ((class (assoc "class" job-info :test #'string=))
        (args  (assoc "args"  job-info :test #'string=))
        (jid   (assoc "jid"   job-info :test #'string=)))
    (unless (and class args jid)
      (error "Invalid job: ~S" job-info))
    (let ((class (read-from-string (cdr class))))
      (check-type class symbol)
      (let ((job (make-instance class :id jid
                                      :options job-info)))
        (check-type job job)
        job))))
