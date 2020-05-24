#lang rosette/safe

(require
  serval/llvm
  serval/lib/core
  serval/lib/unittest
  serval/spec/refinement
  "llvm-impl.rkt"
  "llvm-spec.rkt"
  (only-in racket/base parameterize struct-copy)
  (prefix-in implementation: "generated/kernel.map.rkt")
  (prefix-in implementation: "generated/kernel.global.rkt")
  (prefix-in implementation: "generated/kernel.ll.rkt")
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
  (verify-refinement
    #:implstate machine
    #:impl (make-machine-func impl-func)
    #:specstate (make-havoc-state)
    #:spec spec-func
    #:abs abs-function
    #:ri (compose1 mregions-invariants machine-mregions)
    args))

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
))

(module+ test
  (time (run-tests llvm-tests)))
