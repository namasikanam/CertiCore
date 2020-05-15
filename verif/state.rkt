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
               pagedb.flag)
  #:transparent #:mutable
  #:methods gen:equal+hash
  [(define (equal-proc s t equal?-recur)
     (define-symbolic pageno (bitvector 64))
     (&& (equal?-recur (state-regs s) (state-regs t))
         ; pagedb
         (forall (list pageno)
                 (=> (page-in-bound? pageno)
                     (&& (bveq ((state-pagedb.flag s) pageno) ((state-pagedb.flag t) pageno)))
   (define (hash-proc s hash-recur) 1)
   (define (hash2-proc s hash2-recur) 2)]
  ; pretty-print function
  #:methods gen:custom-write
  [(define (write-proc s port mode)
     (define-symbolic %pageno (bitvector 64))
     (fprintf port "(state")
     (fprintf port "\n  pagedb.flag . ~a~a~a" (list %pageno) "~>" ((state-pagedb.flag s) %pageno))
     (fprintf port ")"))])

(define (make-havoc-regs)
  (define-symbolic*
    ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6
    satp scause scounteren sepc sscratch sstatus stvec stval mepc sip sie
    (bitvector 64))
  (regs ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6
    satp scause scounteren sepc sscratch sstatus stvec stval mepc sip sie))

(define (make-havoc-state)
  (define-symbolic* symbolic-pagedb.flag
                    (~> (bitvector 64) (bitvector 64)))
  (state (make-havoc-regs)
         symbolic-pagedb.flag))

(define-syntax-rule (make-state-updater name getter setter)
  (define (name state indices value)
    (setter state (update (getter state) indices value))))

(make-state-updater update-state-pagedb.flag! state-pagedb.flag set-state-pagedb.flag!)

(define (page-flag-mask flag)
  (bvshl (bv 1 64) (bv flag 64)))

(define (page-in-bound? pageno)
  (bvult pageno (bv constant:NPAGE 64)))

(define (page-has-flag? s pageno flag)
  (&& (page-in-bound? pageno)
      (! (bvzero? (bvand ((state-pagedb.flag s) pageno) (page-flag-mask flag))))))

(define (page-reserved? s pageno)
  (page-has-flag? s pageno constant:PG_RESERVED))

(define (page-allocated? s pageno)
  (page-has-flag? s pageno constant:PG_ALLOCATED))

(define (page-clear-flag! s pageno flag)
  (define oldf ((state-pagedb.flag s) pageno))
  (update-state-pagedb.flag! s pageno (bvand oldf (bvnot (page-flag-mask flag)))))

(define (page-set-flag! s pageno flag)
  (define oldf ((state-pagedb.flag s) pageno))
  (update-state-pagedb.flag! s pageno (bvor oldf (page-flag-mask flag))))

(define (page-freemems s pageno)
  ((state-pagedb.prop s) pageno))

(define (bv64 x) (bv x 64))

; find head of the first block with at least num consecutive free pages 
(define (find-free-pages s num)
  (define indexl 
    (map bv64 (range constant:NPAGE)))
  (findf (lambda (pageno)
           (&& (page-is-head? s pageno)
               (bvule num (page-freemems s pageno))))
         indexl))

(define (allocate-pages s num) ; alloc num-page block using first fit algo.
  (define (update-free-pages s index num)
    (define newhead (bvadd index num))
    (define newfree (bvsub (page-freemems s index) num)))

  (let ([index (find-free-pages s num)])
    (when index (update-free-pages s index num))))

; free the block from index with num pages
(define (free-pages s index num) 

  (define (find-block-next start)
    (define indexl 
      (map bv64 (range (bitvector->natural start) constant:NPAGE)))
    (findf (lambda (pageno)
             (page-is-head? s pageno))
           indexl))

  (define (find-block-prev end)
    (define indexl 
      (map bv64 (range (bitvector->natural end) -1 -1)))
    (findf (lambda (pageno)
             (page-is-head? s pageno))
           indexl))

  ; first find whether a free block around adjoins index
  (let ([next (find-block-next (bvadd index num))]
        [prev (find-block-prev (bvsub index (bv 1 64)))])

    ; if possible, merge the block with previous block 
    ; then indexp would be the first block, after merge
    (define indexp
      (if (&& prev (bveq index (bvadd prev (page-freemems prev))))
        (begin
          (page-clear-flag! s index constant:PG_PROPERTY)
          prev)
        index))

    ; likewise, merge the next block if possible
    (when (&& next (bveq next (bvadd index num)))
      (page-clear-flag! s next constant:PG_PROPERTY))))
