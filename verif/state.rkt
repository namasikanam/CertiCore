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
               nrfree
               pagedb.flag)
  #:transparent #:mutable
  #:methods gen:equal+hash
  [(define (equal-proc s t equal?-recur)
     (define-symbolic pageno (bitvector 64))
     (&& (equal?-recur (state-regs s) (state-regs t))
         (equal?-recur (state-nrfree s) (state-nrfree t))
         ; pagedb
         (forall (list pageno)
                 (=> (page-in-bound? pageno)
                     (&& (bveq ((state-pagedb.flag s) pageno) ((state-pagedb.flag t) pageno)))))))
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
  (define-symbolic* symbolic-nrfree (bitvector 64))
  (state (make-havoc-regs)
         symbolic-nrfree
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

(define (page-available? s pageno)
  (&& (! (page-allocated? s pageno))
      (! (page-reserved? s pageno))))

(define (page-clear-flag! s pageno flag)
  (define oldf ((state-pagedb.flag s) pageno))
  (update-state-pagedb.flag! s pageno (bvand oldf (bvnot (page-flag-mask flag)))))

(define (page-set-flag! s pageno flag)
  (define oldf ((state-pagedb.flag s) pageno))
  (update-state-pagedb.flag! s pageno (bvor oldf (page-flag-mask flag))))

(define (bv64 x) (bv x 64))

; find head of the first block with at least num consecutive free pages 
(define (find-free-pages s num)
  (define (find-free-accumulate lst acc ans)
    (cond
      [(bveq num acc) ans] ; success in finding a block
      [(null? lst) #f] ; failure
      [(page-available? s (car lst))
       (find-free-accumulate 
         (cdr lst)
         (bvadd1 acc)
         (if (bveq acc (bv 0 64))
           (car lst)
           ans))]
      [else ; find an allocated one before success: start again!
        (find-free-accumulate (cdr lst) (bv 0 64) (bv 0 64))]))
  (define indexl (map bv64 (range constant:NPAGE)))
  ; the first 'ans' does not matter, actually
  (find-free-accumulate indexl (bv 0 64) (bv 0 64)))

(define (spec-default-alloc-pages s num)
  (cond
    [! (bvult (bv 0 64) num) (bv constant:NULLPAGE 64)]
    [! (bvule num (state-nrfree s)) (bv constant:NULLPAGE 64)]
    [else
      (begin
        (define freeblk (find-free-pages s num))
        (when freeblk
          (define end (bvadd num freeblk))
          (define (update-flags! index)
            (cond
              [(bveq index end) (void)]
              [else
                (begin
                  (page-set-flag! s index constant:PG_ALLOCATED)
                  (update-flags! (bvadd1 index)))]))
          (update-flags! freeblk))
        (if freeblk freeblk (bv constant:NULLPAGE 64)))
      ]))

(define (spec-default-free-pages s index num)
  (define end (bvadd index num))
  (define (update-flags! index)
    (cond
      [(bveq index end) (void)]
      [else
        (begin
          (page-clear-flag! s index constant:PG_ALLOCATED)
          (update-flags! (bvadd1 index)))]))
  (update-flags! index))

;(define (find-free-pages s num)
  ;(define indexl 
    ;(map bv64 (range constant:NPAGE)))
  ;(findf (lambda (pageno)
           ;(&& (page-is-head? s pageno)
               ;(bvule num (page-freemems s pageno))))
         ;indexl))

;(define (allocate-pages s num) ; alloc num-page block using first fit algo.
  ;(define (update-free-pages s index num)
    ;(define newhead (bvadd index num))
    ;(define newfree (bvsub (page-freemems s index) num)))

  ;(let ([index (find-free-pages s num)])
    ;(when index (update-free-pages s index num))))

;; free the block from index with num pages
;(define (free-pages s index num) 

  ;(define (find-block-next start)
    ;(define indexl 
      ;(map bv64 (range (bitvector->natural start) constant:NPAGE)))
    ;(findf (lambda (pageno)
             ;(page-is-head? s pageno))
           ;indexl))

  ;(define (find-block-prev end)
    ;(define indexl 
      ;(map bv64 (range (bitvector->natural end) -1 -1)))
    ;(findf (lambda (pageno)
             ;(page-is-head? s pageno))
           ;indexl))

  ;; first find whether a free block around adjoins index
  ;(let ([next (find-block-next (bvadd index num))]
        ;[prev (find-block-prev (bvsub index (bv 1 64)))])

    ;; if possible, merge the block with previous block 
    ;; then indexp would be the first block, after merge
    ;(define indexp
      ;(if (&& prev (bveq index (bvadd prev (page-freemems prev))))
        ;(begin
          ;(page-clear-flag! s index constant:PG_PROPERTY)
          ;prev)
        ;index))

    ;; likewise, merge the next block if possible
    ;(when (&& next (bveq next (bvadd index num)))
      ;(page-clear-flag! s next constant:PG_PROPERTY))))
