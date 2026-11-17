; 7. backpressure: scores in 0..10, combine = addition capped at 10, neutral 0. TRUE: monoid.
(define-fun cap ((x Int) (y Int)) Int (ite (< (+ x y) 10) (+ x y) 10))
(declare-const a Int) (declare-const b Int) (declare-const c Int)
(assert (and (>= a 0) (<= a 10) (>= b 0) (<= b 10) (>= c 0) (<= c 10)))
(push) (assert (not (= (cap (cap a b) c) (cap a (cap b c))))) (check-sat) (pop)
(push) (assert (not (and (= (cap a 0) a) (= (cap 0 a) a)))) (check-sat) (pop)
; closure: result stays in 0..10
(push) (assert (not (and (>= (cap a b) 0) (<= (cap a b) 10)))) (check-sat) (pop)
