(in-package :cl-user)
(defpackage redqing.worker.manager
  (:use #:cl
        #:redqing.worker.processor
        #:redqing.specials)
  (:import-from #:alexandria
                #:when-let)
  (:export #:manager
           #:make-manager
           #:manager-stopped-p
           #:start
           #:stop
           #:kill
           #:wait-manager-ends))
(in-package :redqing.worker.manager)

(defstruct (manager (:constructor %make-manager))
  host
  port
  (queues '())
  (children '())
  (lock (bt:make-recursive-lock))
  (stopped-p t))

(defun make-manager (&key (host *default-redis-host*) (port *default-redis-port*) queues (count 25) (timeout 5))
  (let ((manager (%make-manager :host host :port port :queues queues)))
    (setf (manager-children manager)
          (loop repeat count
                collect (make-processor :host host
                                        :port port
                                        :queues queues
                                        :manager manager
                                        :timeout timeout)))
    manager))

(defun processor-stopped (manager processor)
  (bt:with-recursive-lock-held ((manager-lock manager))
    (setf (manager-children manager)
          (delete processor (manager-children manager) :test #'eq))
    (when (null (manager-children manager))
      (setf (manager-stopped-p manager) t)))
  (values))

(defun processor-died (manager processor e)
  (bt:with-recursive-lock-held ((manager-lock manager))
    (stop processor)
    (setf (manager-children manager)
          (delete processor (manager-children manager) :test #'eq))
    (unless (manager-stopped-p manager)
      (vom:warn "Processor died with ~S: ~A" (class-name (class-of e)) e)
      (vom:debug "Adding a new processor...")
      (let ((new-processor
              (make-processor :host (manager-host manager)
                              :port (manager-port manager)
                              :queues (manager-queues manager)
                              :manager manager
                              :timeout (processor-timeout processor))))
        (push new-processor (manager-children manager))
        (start new-processor))))
  (values))

(defmethod run :around ((processor processor))
  (handler-case (call-next-method)
    (error (e)
      (when-let (manager (processor-manager processor))
        (processor-died manager processor e))))
  (vom:debug "Shutting down a processor..."))

(defmethod finalize :after ((processor processor))
  (when-let (manager (processor-manager processor))
    (processor-stopped manager processor)))

(defmethod start ((manager manager))
  (setf (manager-stopped-p manager) nil)
  (map nil #'start (manager-children manager))
  manager)

(defmethod stop ((manager manager))
  (when (manager-stopped-p manager)
    (return-from stop nil))

  (setf (manager-stopped-p manager) t)
  (vom:info "Terminating quiet processors...")
  (map nil #'stop (manager-children manager))
  (vom:info "Exiting...")
  t)

(defmethod kill ((manager manager) &optional (wait t))
  (setf (manager-stopped-p manager) t)
  (vom:info "Terminating all processors...")
  (map nil (lambda (p)
             (kill p nil))
       (manager-children manager))
  (when wait
    (wait-manager-ends manager)
    (sleep 3))
  (vom:info "Exiting...")
  t)

(defun wait-manager-ends (manager)
  (map nil #'wait-processor-ends (manager-children manager)))
