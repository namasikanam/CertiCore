#lang rosette/safe

(require
  serval/llvm
  serval/lib/core
  serval/lib/unittest
  serval/spec/refinement
  (prefix-in serval: serval/spec/ni)
  "llvm-impl.rkt"
  "llvm-spec.rkt"
  (only-in racket/base parameterize struct-copy hash->list)
  (only-in racket/list range)
  (prefix-in implementation: "generated/kernel.map.rkt")
  (prefix-in implementation: "generated/kernel.global.rkt")
  (prefix-in implementation: "generated/kernel.ll.rkt")
  (prefix-in constant: "generated/asm-offsets.rkt")
)

(define (make-machine-func func)
  (lambda (machine . args)
    (parameterize ([current-machine machine])
      (define result (apply func args))
      (set-machine-retval! machine result))))

(define (abs-function machine)
  (define s (mregions-abstract (machine-mregions machine)))
  (set-state-regs! s (struct-copy regs (state-regs s) [a0 (machine-retval machine)]))
  s)

(define (verify-llvm-refinement spec-func impl-func [args null])
  (define machine (make-machine implementation:symbols implementation:globals))

  (define (ce-handler s1 s2 cex)
    (displayln "counter model (detailed)")
    (map
      (lambda
        (l)
        (define key (car l))
        (define value (cdr l))
        (printf "  ~v:" key)
        (if
          (fv? value)
          (map
            (lambda
              (i)
              (printf "\n    ~a ~~> ~a" i (value i)))
            all-pages)
          (printf "~v" value))
        (printf "\n"))
      (hash->list (model cex))))

  (verify-refinement
  #:implstate machine
  #:impl (make-machine-func impl-func)
  #:specstate (make-havoc-state)
  #:spec spec-func
  #:abs abs-function
  #:ri (compose1 mregions-invariants machine-mregions)
  args
  ce-handler))

; "args" here should be a list of ("base" and "num")
(define (verify-step-consistency spec args)
  (define base (car args))
  (define num (car (cdr args)))
  (define (unwinding s t)
    (andmap
      (lambda
        (pageno)
        (||
          (bvuge base (bv64 constant:NPAGE))
          (bveq num (bv64 0))
          (bvugt num (bv64 constant:NPAGE))
          (bvugt (bvadd base num) (bv64 constant:NPAGE))
          (=>
            (||
              (bvult pageno base)
              (bvuge pageno (bvadd base num)))
            (bveq
              ((state-pagedb.flag s) pageno)
              ((state-pagedb.flag t) pageno)))))
      all-pages))
  (define (ce-handler sol)
    (displayln "counter model (detailed)")
    (map
      (lambda
        (l)
        (define key (car l))
        (define value (cdr l))
        (printf "  ~v:" key)
        (if
          (fv? value)
          (map
            (lambda
              (i)
              (printf "\n    ~a ~~> ~a" i (value i)))
            all-pages)
          (printf "~v" value))
        (printf "\n"))
      (hash->list (model sol))))
  (serval:check-step-consistency
    #:state-init make-havoc-state
    #:state-copy (lambda (s) (struct-copy state s))
    #:unwinding unwinding
    spec
    args
    ce-handler))

(define llvm-tests
  (test-suite+ "LLVM tests"
    (test-case+ "magic LLVM"
      (verify-llvm-refinement spec-magic implementation:@verify_magic))
    (test-case+ "default_init LLVM"
      (verify-llvm-refinement spec-default_init implementation:@default_init))
   (test-case+ "default_init_memmap LLVM"
     (verify-llvm-refinement spec-default_init_memmap implementation:@default_init_memmap (list (make-bv64) (make-bv64))))
    (test-case+ "default_alloc_pages LLVM"
      (verify-llvm-refinement spec-default_alloc_pages implementation:@default_alloc_pages (list (make-bv64))))
    (test-case+ "default_free_pages LLVM"
      (verify-llvm-refinement spec-default_free_pages implementation:@default_free_pages (list (make-bv64) (make-bv64))))
    (test-case+ "default_nr_free_pages LLVM"
      (verify-llvm-refinement spec-default_nr_free_pages implementation:@default_nr_free_pages (list)))
    (test-case+ "step-consistency spec-default_free_pages LLVM"
      (verify-step-consistency spec-default_free_pages (list (make-bv64) (make-bv64))))
))

(module+ test
  (time (run-tests llvm-tests)))
