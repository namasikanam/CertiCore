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

(define all-pages
  (map
    (lambda (pageno-int) (bv pageno-int 64))
    (range constant:NPAGE)))

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

  (define (bvcount f l)
    (cond
      [(null? l) (bv64 0)]
      [else (let ([cnt (bvcount f (cdr l))])
              (if (f (car l))
                (bvadd1 cnt)
                cnt))
            ]))

  (&&
    (bvule nr_free (bv64 constant:NPAGE))

    ; We cannot use filter here, *sigh*
     (bveq
       nr_free
       (bvcount impl-page-available? all-pages)))
)
