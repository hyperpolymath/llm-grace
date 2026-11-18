{-# OPTIONS --safe --without-K #-}

-- NEGATIVE CONTROL: this file is EXPECTED TO BE REJECTED by Agda.
-- It claims the law that the design note relies on for component 3 (drift is associative)
-- on the instance 1, 2, 3. Rejection shows the checker is not accepting everything.

module NegativeControl where

open import Agda.Builtin.Equality using (_≡_; refl)
open import Ledgerline using (dist)

drift-associative-on-1-2-3 : dist (dist 1 2) 3 ≡ dist 1 (dist 2 3)
drift-associative-on-1-2-3 = refl
