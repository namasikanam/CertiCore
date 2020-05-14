#lang rosette/safe

(require
  "state.rkt"
  serval/lib/core
  (prefix-in constant: "generated/asm-offsets.rkt")
)

(provide (all-defined-out))

(define (mregions-abstract mregions)
  (define block-pagedb (find-block-by-name mregions 'pages))

  (state (zero-regs)
         ; pagedb.refcnt
         (lambda (pageno)
           (mblock-iload block-pagedb (list pageno 'ref)))
         ; pagedb.flag
         (lambda (pageno)
           (mblock-iload block-pagedb (list pageno 'flags)))
         ; pagedb.prop
         (lambda (pageno)
           (mblock-iload block-pagedb (list pageno 'property)))))

(define (mregions-invariants mregions)
  (define block-pagedb (find-block-by-name mregions 'pages))

  (define (pageno->pagedb.flag pageno)
    (mblock-iload block-pagedb (list pageno 'flags)))

  (define (pageno->pagedb.property pageno)
    (mblock-iload block-pagedb (list pageno 'property)))

  (define (pageno->pagedb.ref pageno)
    (mblock-iload block-pagedb (list pageno 'ref)))

  (define (impl-page-has-flag? pageno flag)
    (&& (page-in-bound? pageno)
        (! (bvzero? (bvand
                      (pageno->pagedb.flag pageno) 
                      (page-flag-mask flag))))))

  (define (impl-page-reserved? pageno)
    (impl-page-has-flag? pageno constant:PG_RESERVED))

  (define (impl-page-property? pageno)
    (impl-page-has-flag? pageno constant:PG_PROPERTY))

  (define (impl-is-head? pageno)
    (&& (! (impl-page-reserved? pageno))
        (impl-page-property? pageno)))

  ; two pages
  (define-symbolic pgi pgj (bitvector 64))

  ; does [x1, y1) and [x2, y2) ovrelap?
  (define (overlap? x1 y1 x2 y2)
    (|| (bvult x2 y1)
        (bvult x1 y2)))

  (&&
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
