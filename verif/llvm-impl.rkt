#lang rosette/safe

(require
  "llvm-spec.rkt"
  serval/lib/core
  (prefix-in constant: "generated/asm-offsets.rkt")
  (only-in racket/list range)
)

(provide (all-defined-out))

(define (mregions-abstract mregions)
  (define block-pagedb (find-block-by-name mregions 'pages))

  (state (zero-regs)
         ; nr_free
         (mblock-iload (find-block-by-name mregions 'nr_free) null)
         ; pagedb.flag
         (lambda (pageno)
           (mblock-iload block-pagedb (list pageno 'flags)))))

(define (mregions-invariants mregions)
  (define block-pagedb (find-block-by-name mregions 'pages))

  (define nr_free (mblock-iload (find-block-by-name mregions 'nr_free) null))

  (define (pageno->pagedb.flag pageno)
    (mblock-iload block-pagedb (list pageno 'flags)))

  (define (impl-page-has-flag? pageno flag)
    (&& (page-in-bound? pageno)
        (! (bvzero? (bvand
                      (pageno->pagedb.flag pageno) 
                      (page-flag-mask flag))))))

  (define (impl-page-reserved? pageno)
    (impl-page-has-flag? pageno constant:PG_RESERVED))

  (define (impl-page-allocated? pageno)
    (impl-page-has-flag? pageno constant:PG_ALLOCATED))

  (define (impl-page-available? pageno)
    (&& (! (impl-page-allocated? pageno))
        (! (impl-page-reserved? pageno))))

  (define all-pages
    (map
      (lambda (pageno-int) (bv pageno-int 64))
      (range constant:NPAGE)))

  ; two pages
  (define-symbolic pgi pgj (bitvector 64))

  ; does [x1, y1) and [x2, y2) overlap?
  (define (overlap? x1 y1 x2 y2)
    (|| (bvult x2 y1)
        (bvult x1 y2)))

  (&&
    (bvule nr_free (bv constant:NPAGE 64))

    ; An invariant to characterize nr_free
    ; i don't know why it doesn't work
    ;(equal?
    ;  (bitvector->integer nr_free)
    ;  (length (filter impl-page-available? all-pages)))

    ;length is non-negative
    ;(forall (list pgi)
            ;(=> (impl-is-head? pgi)
                ;(bvult (bv 0 64) (pageno->pagedb.property pgi))))
     ;non-overlapping
    ;(forall (list pgi pgj)
            ;(=> (&& (impl-is-head? pgi)
                    ;(impl-is-head? pgj))
                ;(! (overlap? pgi (bvadd pgi 
                                        ;(pageno->pagedb.property pgi))
                             ;pgj (bvadd pgj 
                                        ;(pageno->pagedb.property pgj))))))
  ))