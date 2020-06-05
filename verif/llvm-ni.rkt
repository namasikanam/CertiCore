#lang rosette/safe

(require
  serval/lib/unittest
  serval/lib/core

  rosette/lib/roseunit
  rosette/lib/angelic

  "llvm.rkt"
  "llvm-spec.rkt"
  "llvm-impl.rkt"
; some invariants are possibly needed
;   "llvm-invariants.rkt"

  (only-in racket/base struct-copy string-append)

  rackunit
  rackunit/text-ui)

; ==== unwinding is an equivalence relation ====

; u is a page id
(define (unwinding u s t)
  (bveq
    ((state-pagedb.flag s) u)
    ((state-pagedb.flag t) u)))

(define (verify-unwinding-symmetry)
  (define s (make-havoc-state))
  (define t (make-havoc-state))
  (define-symbolic* u (bitvector 64))
  (check-unsat? (verify (assert (=> (unwinding u s t) (unwinding u t s))))))

(define (verify-unwinding-reflexivity)
  (define s (make-havoc-state))
  (define-symbolic* u (bitvector 64))
  (check-unsat? (verify (assert (unwinding u s s)))))

(define (verify-unwinding-transitivity)
  (define s (make-havoc-state))
  (define t (make-havoc-state))
  (define v (make-havoc-state))
  (define-symbolic* u (bitvector 64))
  (check-unsat? (verify (assert
    (=> (&& (unwinding u s t) (unwinding u t v))
        (unwinding u s v))))))

; ==== weak step consistency ====

; TODO: state invariants perhaps are needed further

(define (verify-weak-step-consistency spec)
  (define-symbolic* base (bitvector 64))
  (define-symbolic* num (bitvector 64))

  (define s (make-havoc-state))
  (define t (make-havoc-state))
  (define old-s (struct-copy state s))
  (define old-t (struct-copy state t))

  (apply spec s (list base num))
  (apply spec t (list base num))

  (define-symbolic* u (bitvector 64))

  (define (check-unwinding x)
  (=> (&& (bvule base x)
          (bvult x (bvadd base num)))
      (unwinding x old-s old-t)))
  (define pre (&& (unwinding u old-s old-t)
                  (check-unwinding (bv64 0))
                  (check-unwinding (bv64 1))
                  (check-unwinding (bv64 2))
                  (check-unwinding (bv64 3))
                  (check-unwinding (bv64 4))))
  (check-equal? (asserts) null)
  (define post (unwinding u s t))
  (check-equal? (asserts) null)

  (let ([sol (verify (assert (=> pre post)))])
    (when (sat? sol)
      (define concrete-old-s (evaluate old-s sol))
      (define concrete-old-s-pagedb.flag (state-pagedb.flag concrete-old-s))
      (printf "\n concrete-old-s-pagedb.flag:")
      (map
        (lambda
          (i)
          (printf "\n    ~a ~~> ~a" i (concrete-old-s-pagedb.flag i)))
        all-pages)
      
      (define concrete-old-t (evaluate old-t sol))
      (define concrete-old-t-pagedb.flag (state-pagedb.flag concrete-old-t))
      (printf "\n concrete-old-t-pagedb.flag:")
      (map
        (lambda
          (i)
          (printf "\n    ~a ~~> ~a" i (concrete-old-t-pagedb.flag i)))
        all-pages)
      
      (define concrete-s (evaluate s sol))
      (define concrete-s-pagedb.flag (state-pagedb.flag concrete-s))
      (printf "\n concrete-s-pagedb.flag:")
      (map
        (lambda
          (i)
          (printf "\n    ~a ~~> ~a" i (concrete-s-pagedb.flag i)))
        all-pages)

      (define concrete-t (evaluate t sol))
      (define concrete-t-pagedb.flag (state-pagedb.flag t))
      (printf "\n concrete-t-pagedb.flag:")
      (map
        (lambda
          (i)
          (printf "\n    ~a ~~> ~a" i (concrete-t-pagedb.flag i)))
        all-pages)

      (ce-handler 0 0 sol))
    (check-unsat? sol)))

; ==== local respect ====

; TODO: state invariants perhaps are needed further

(define (verify-local-respect spec)

  (define-symbolic* base (bitvector 64))
  (define-symbolic* num (bitvector 64))

  (define s (make-havoc-state))
  (define old-s (struct-copy state s))

  (apply spec s (list base num))

  (define-symbolic* u (bitvector 64))

  (define pre (! (&& (bvule base u)
                     (bvult u (bvadd base num)))))
  (check-equal? (asserts) null)
  (define post (unwinding u s old-s))
  (check-equal? (asserts) null)

  (let ([sol (verify (assert (=> pre post)))])
    (when (sat? sol) (ce-handler 0 0 sol))
    (check-unsat? sol)))

; ==== Let's verify it! ====

(define-syntax-rule (ni-case+ name op)
 (begin
  (test-case+ (string-append name " weak-step-consistency") (verify-weak-step-consistency op))
  (test-case+ (string-append name " local-respect") (verify-local-respect op))))

(define ni-tests
  (test-suite+ "safety property tests"
    (test-case+ "unwinding symmetry" (verify-unwinding-symmetry))
    (test-case+ "unwinding reflexivity" (verify-unwinding-reflexivity))
    (test-case+ "unwinding transitivity" (verify-unwinding-transitivity))

    (ni-case+ "default_free_pages" spec-default_free_pages)
    ; (ni-case+ "default_init_memmap" spec-default_init_memmap)
))

(module+ test
  (time (run-tests ni-tests)))