#lang rosette

(provide (all-defined-out))

(struct state (tick)
  #:transparent
  #:mutable)

; Debuging function to print specification state
(define (print-state cex s)
  (printf " tick: ~v\n" (bitvector->natural (evaluate (state-tick s) cex))))

(define (fresh-state)
  (define-symbolic* tick (bitvector 64))
  (state tick))

(define (intrp-timer st)
  (set-state-tick! st (bvadd (state-tick st) (bv 1 64))))
