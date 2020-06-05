#lang rosette/safe

(require
  serval/lib/core
  serval/lib/unittest
  serval/riscv/spec
  (only-in racket/list range)
  (only-in racket/base struct-copy)
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

; ==== Utils =====

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

(define (bv64 x) (bv x 64))

(define (set-return! s val)
  (set-state-regs! s (struct-copy regs (state-regs s) [a0 val])))

; ==== Function Updater ====

(define (update-func func pred value-func)
  (lambda args (if (apply pred args) (value-func (apply func args)) (apply func args))))

(define (update-state-func-pagedb.flag! s pred value-func)
  (set-state-pagedb.flag! s (update-func (state-pagedb.flag s) pred value-func)))

(define (page-set-flag-func! s pred flag)
  (update-state-func-pagedb.flag!
    s pred (lambda (val)
             (bvor val (page-flag-mask flag)))))

(define (page-clear-flag-func! s pred flag)
  (update-state-func-pagedb.flag!
    s pred (lambda (val)
             (bvand (bvnot (page-flag-mask flag)) val))))

; ==== Magic Spec ====

(define (spec-magic s)
  (set-return! s (bv64 0)))

; ==== Init Spec ====

(define (spec-default_init s)
  (set-state-nrfree! s (bv64 0))
  (set-return! s (void)))

; ==== Init Mem Spec ====

; If the flags of pages in [base, base + num) are all 1?
(define (page-valid-flag? s base num flag)
  (define pages
    (map bv64 (range constant:NPAGE)))
  (define (check-flag? pageno)
    (=>
      (&& (bvuge pageno base)
          (bvult pageno (bvadd base num)))
      (page-has-flag? s pageno flag)))
  (andmap check-flag? pages))

; If the flags of pages in [base, base + num) are all 0?
; Similar to the above one, expect [andmap] -> [ormap]
(define (page-sat-flag? s base num flag)
  (define pages
    (map bv64 (range constant:NPAGE)))
  (define (check-flag? pageno)
    (&&
      (&& (bvuge pageno base)
          (bvult pageno (bvadd base num)))
      (page-has-flag? s pageno flag)))
  (ormap check-flag? pages))

(define (spec-default_init_memmap s base num)
  (define val
    (cond
      [(! (bvugt num (bv64 0))) (bv64 1)]
      [(! (bvule num (bv64 constant:NPAGE))) (bv64 2)]
      [(! (bvule base (bv64 constant:NPAGE))) (bv64 3)]
      [(! (bvule (bvadd base num) (bv64 constant:NPAGE))) (bv64 4)]
      [(! (page-valid-flag? s base num constant:PG_RESERVED)) (bv64 5)]
      [(page-sat-flag? s base num constant:PG_ALLOCATED) (bv64 6)]
      [else
        (page-clear-flag-func!
          s
          (lambda (pageno)
            (&& (bvuge pageno base)
                (bvult pageno (bvadd base num))))
          constant:PG_RESERVED)
        (set-state-nrfree! s (bvadd (state-nrfree s) num))
        (bv64 0)]))
  (set-return! s val))

; ==== Alloc Spec ====

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
         (if (bveq acc (bv64 0))
           (car lst)
           ans))]
      [else ; find an allocated one before success: start again!
        (find-free-accumulate (cdr lst) (bv64 0) (bv64 0))]))
  (define indexl (map bv64 (range constant:NPAGE)))
  ; the first 'ans' does not matter, actually
  (find-free-accumulate indexl (bv64 0) (bv64 0)))

(define (spec-default_alloc_pages s num)
  (define val
    (cond
      [(! (bvult (bv64 0) num)) (bv64 constant:NULLPAGE)]
      [(! (bvule num (bv64 constant:NPAGE))) (bv64 constant:NULLPAGE)]
      [else
        (begin
          (define freeblk (find-free-pages s num))
          (if freeblk
            (begin
              (set-state-nrfree! s (bvsub (state-nrfree s) num))
              (page-set-flag-func! 
                s
                (lambda (pageno) 
                  (&& (bvule freeblk pageno)
                      (bvult pageno (bvadd num freeblk))))
                constant:PG_ALLOCATED)
              freeblk)
            (bv64 constant:NULLPAGE)))]))
  (set-return! s val))

; ==== Free Spec ====

; the unverified version
; (define (spec-default_free_pages s base num)
;   (cond
;     [(bvuge base (bv64 constant:NPAGE)) (void)]
;     [(bveq num (bv64 0)) (void)]
;     [(bvugt num (bv64 constant:NPAGE)) (void)]
;     [(bvugt (bvadd base num) (bv64 constant:NPAGE)) (void)]
;     [(bvugt num (bvsub (bv64 constant:NPAGE) (state-nrfree s))) (void)]
;     [else
;       (page-clear-flag-func!
;         s
;         (lambda (pageno)
;           (&& (bvuge pageno base)
;               (bvult pageno (bvadd base num))))
;         constant:PG_ALLOCATED)
;       (set-state-nrfree! s (bvadd (state-nrfree s) num))
;       (void)])
;   (set-return! s (void)))

; the verified version
(define (spec-default_free_pages s base num)
  (when
    (&&
      (! (bvuge base (bv64 constant:NPAGE)))
      (! (bveq num (bv64 0)))
      (! (bvugt num (bv64 constant:NPAGE)))
      (! (bvugt (bvadd base num) (bv64 constant:NPAGE))))
    (page-clear-flag-func!
      s
      (lambda (pageno)
        (&& (bvuge pageno base)
            (bvult pageno (bvadd base num))))
      constant:PG_ALLOCATED)
    (set-state-nrfree! s (bvadd (state-nrfree s) num)))
  (set-return! s (void)))

; ==== NR Free Spec ====

(define (spec-default_nr_free_pages s)
  (set-return! s (state-nrfree s)))

(define spec-tests
  (test-suite+
  "tests for specification functions with concrete values"
  #:before clear-asserts!
  #:after  clear-asserts!

    (test-case+
      "spec-default_free_pages test"
      (define s
        (state
          (regs (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0) (bv64 0))
          (bv64 0)
          (lambda
              (pageno)
            pageno)))
      (define base (bv64 1))
      (define num (bv64 3))
      (spec-default_free_pages s base num)
      (define new-flag (state-pagedb.flag s))

      (check bveq (new-flag (bv64 0)) (bv64 0))
      (check bveq (new-flag (bv64 1)) (bv64 1))
      (check bveq (new-flag (bv64 2)) (bv64 0))
      (check bveq (new-flag (bv64 3)) (bv64 1))
      (check bveq (new-flag (bv64 4)) (bv64 4)))))

(module+ test
  (time (run-tests spec-tests)))