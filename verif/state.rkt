#lang rosette/safe

(require
  serval/lib/core
  serval/riscv/spec
  (only-in racket/list range)
  (prefix-in constant: "generated/asm-offsets.rkt"))

(provide
  (all-defined-out)
  (all-from-out serval/riscv/spec))

(struct state (regs 
               pagedb.refcnt
               pagedb.flag
               pagedb.prop)
  #:transparent #:mutable
  #:methods gen:equal+hash
  [(define (equal-proc s t equal?-recur)
     (define-symbolic pageno (bitvector 64))
     (&& (equal?-recur (state-regs s) (state-regs t))
         ; pagedb
         (forall (list pageno)
                 (=> (page-in-bound? pageno)
                     (&& (bveq ((state-pagedb.flag s) pageno) ((state-pagedb.flag t) pageno))
                         (bveq ((state-pagedb.prop s) pageno) ((state-pagedb.prop t) pageno))
                         (bveq ((state-pagedb.refcnt s) pageno) ((state-pagedb.refcnt t) pageno)))))))
   (define (hash-proc s hash-recur) 1)
   (define (hash2-proc s hash2-recur) 2)]
  ; pretty-print function
  #:methods gen:custom-write
  [(define (write-proc s port mode)
     (define-symbolic %pageno (bitvector 64))
     (fprintf port "(state")
     (fprintf port "\n  pagedb.refcnt . ~a~a~a" (list %pageno) "~>" ((state-pagedb.refcnt s) %pageno))
     (fprintf port "\n  pagedb.flag . ~a~a~a" (list %pageno) "~>" ((state-pagedb.flag s) %pageno))
     (fprintf port "\n  pagedb.prop . ~a~a~a" (list %pageno) "~>" ((state-pagedb.prop s) %pageno))
     (fprintf port ")"))])


(define (make-havoc-regs)
  (define-symbolic*
    ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6
    satp scause scounteren sepc sscratch sstatus stvec stval mepc sip sie
    (bitvector 64))
  (regs ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6
    satp scause scounteren sepc sscratch sstatus stvec stval mepc sip sie))

(define (make-havoc-state)
  (define-symbolic* symbolic-pagedb.prop
                    symbolic-pagedb.flag
                    symbolic-pagedb.refcnt
                    (~> (bitvector 64) (bitvector 64)))
  (state (make-havoc-regs)
         symbolic-pagedb.flag
         symbolic-pagedb.refcnt
         symbolic-pagedb.prop))

(define-syntax-rule (make-state-updater name getter setter)
  (define (name state indices value)
    (setter state (update (getter state) indices value))))

(make-state-updater update-state-pagedb.flag! state-pagedb.flag set-state-pagedb.flag!)
(make-state-updater update-state-pagedb.prop! state-pagedb.prop set-state-pagedb.prop!)
(make-state-updater update-state-pagedb.refcnt! state-pagedb.refcnt set-state-pagedb.refcnt!)

(define (page-flag-mask flag)
  (bvshl (bv 1 64) (bv flag 64)))

(define (page-in-bound? pageno)
  (bvult pageno (bv constant:NPAGE 64)))

(define (page-has-flag? s pageno flag)
  (&& (page-in-bound? pageno)
      (! (bvzero? (bvand ((state-pagedb.flag s) pageno) (page-flag-mask flag))))))

(define (page-reserved? s pageno)
  (page-has-flag? s pageno constant:PG_RESERVED))

; PG_PROPERTY means the head of a free mem block
(define (page-property? s pageno)
  (page-has-flag? s pageno constant:PG_PROPERTY))

(define (page-clear-flag! s pageno flag)
  (define oldf ((state-pagedb.flag s) pageno))
  (update-state-pagedb.flag! s pageno (bvand oldf (bvnot (page-flag-mask flag)))))

(define (page-set-flag! s pageno flag)
  (define oldf ((state-pagedb.flag s) pageno))
  (update-state-pagedb.flag! s pageno (bvor oldf (page-flag-mask flag))))

(define (page-freemems s pageno)
  ((state-pagedb.prop s) pageno))

; find head of the first block with at least num consecutive free pages 
(define (find-free-pages s num)
  (define indexl 
    (map (lambda (x) 
           (bv x 64)) 
         (range constant:NPAGE)))
  (findf (lambda (pageno)
           ; the first block of free mem. has page-property.
           (&& (page-property? s pageno)
               (bvule num (page-freemems s pageno))))
         indexl))

(define (allocate-pages s num)
  (define (update-free-pages s index num)
    (define newhead (bvadd index num))
    (define newfree (bvsub (page-freemems s index) num))
    ; clear old head's PG_PROPERTY flag
    (page-clear-flag! s index constant:PG_PROPERTY)
    (when (! (bveq newfree (bv 0 64)))
      ; set the new head, only when some free pages are left
      (page-set-flag! s newhead constant:PG_PROPERTY)
      (update-state-pagedb.prop! s newhead newfree)))

  (let ([index (find-free-pages s num)])
    (when index (update-free-pages s index num))))
