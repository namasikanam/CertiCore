#lang rosette/safe

(require
  serval/lib/unittest
  serval/lib/core
  serval/spec/refinement
  serval/riscv/base
  serval/riscv/interp
  serval/riscv/objdump
  (only-in racket/base struct-copy for)
  (prefix-in specification: "spec.rkt")
  (prefix-in implementation:
    (combine-in
      "generated/kernel.asm.rkt"
      "generated/kernel.global.rkt"
      "generated/kernel.map.rkt")))

(provide refinement-tests)

; Helper function to find the start of a symbol in our monitor's image
(define (find-symbol-start name)
  (define sym (find-symbol-by-name implementation:symbols name))
  (bv (car sym) 64))

; Representation invariant that is assumed to hold
; before each system call, and is proven to hold after
(define (rep-invariant cpu)
  (equal? (csr-ref cpu 'stvec) (find-symbol-start '__alltraps)))

; Initialize the machine state with concrete values
; consistent with the representation invariant.
(define (init-rep-invariant cpu)
  (csr-set! cpu 'stvec (find-symbol-start '__alltraps)))

; Check that init-rep-invariant is consistent with
; the representation invariant
(define (verify-rep-invariant)
  (define cpu1 (init-cpu implementation:symbols implementation:globals))
  (define cpu2 (init-cpu implementation:symbols implementation:globals))
  (define equal-before (cpu-equal? cpu1 cpu2))
  (init-rep-invariant cpu2)
  (define equal-after (cpu-equal? cpu1 cpu2))
  (check-unsat? (verify (assert (implies (&& equal-before (rep-invariant cpu1)) equal-after)))))

; Abstraction function that maps an implementation CPU
; state to the specification state
(define (abs-function cpu)
  ; Get list of implementation memory regions
  (define mr (cpu-mregions cpu))
  ; Find the block containing the global variable named "dictionary"
  (define tick (mblock-iload (find-block-by-name mr 'ticks) null))
  ; Construct specification state
  (specification:state tick))

; Simulate an ecall from the kernel to the security monitor.
; It sets mcause to ECALL,
; the program counter to the value in the mtvec CSR,
; a7 to the monitor call number,
; and a0 through a6 to the monitor call arguments.
(define (cpu-interrupt cpu expcode)
  (set-cpu-pc! cpu (csr-ref cpu 'stvec))
  ; timer interrupt
  (csr-set! cpu 'scause (bv expcode 64))
  (interpret-objdump-program cpu implementation:instructions))

; Check RISC-V refinement for a single system call using
; cpu-ecall and Serval's refinement definition
(define (verify-riscv-refinement spec-func expcode)
  (define cpu (init-cpu implementation:symbols implementation:globals))
  (init-rep-invariant cpu)

  (define (handle-ce s1 s2 cex)
    ;(printf "Args: ~v\n" (map bitvector->natural (evaluate args cex)))
    (displayln "\nspec state:")
    (specification:print-state cex s1)
    (displayln "\nabs(impl state):")
    (specification:print-state cex s2))

  (verify-refinement
    ; Implementation state
    #:implstate cpu
    ; Implementation transition function
    #:impl (lambda (c) (cpu-interrupt c expcode))
    ; Specification state
    #:specstate (specification:fresh-state)
    ; Specification transition function
    #:spec spec-func
    ; Abstraction funtion from c -> s
    #:abs abs-function
    ; Representation invariant c -> bool
    #:ri rep-invariant
    ; Arguments to monitor call
    null
    handle-ce))


;(define (verify-boot-invariants)
  ;(define cpu (init-cpu implementation:symbols implementation:globals))
  ;; Set program counter to architecturally-defined reset vector
  ;(set-cpu-pc! cpu (bv #x0000000080000000 64))
  ;; Set a0 to be hartid (boot cpu number)
  ;(gpr-set! cpu 'a0 (bv constants:CONFIG_BOOT_CPU 64))

  ;; Interpret until first mret to user space
  ;(check-asserts (interpret-objdump-program cpu implementation:instructions))

  ;; Prove that the representation invariant holds
  ;(check-unsat? (verify (assert (rep-invariant cpu)))))


(define (refinement-tests)
  (test-case+ "verify init-rep-invariant" (verify-rep-invariant))

  (define s-timer-no #x8000000000000005)

  ;(test-case+ "verify boot invariants" (verify-boot-invariants))

  (test-case+ "timer refinement"
    (verify-riscv-refinement
      specification:intrp-timer
      s-timer-no)))

(module+ test
  (refinement-tests))
