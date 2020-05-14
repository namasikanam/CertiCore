#lang rosette/safe

(require
  serval/llvm
  serval/lib/core
  serval/lib/unittest
  serval/spec/refinement
  "impl.rkt"
  "state.rkt"
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


(define (spec-magic s)
  (set-state-regs! s (struct-copy regs (state-regs s) [a0 (bv 0 64)])))

(define llvm-tests
  (test-suite+ "LLVM tests"
    (test-case+ "magic LLVM"
      (verify-llvm-refinement spec-magic implementation:@cprintf))
))

(module+ test
  (time (run-tests llvm-tests)))
