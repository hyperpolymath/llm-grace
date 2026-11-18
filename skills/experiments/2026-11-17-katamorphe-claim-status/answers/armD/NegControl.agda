{-# OPTIONS --safe --without-K #-}
-- NEGATIVE CONTROL: this file is EXPECTED TO FAIL type-checking.
-- It asserts the associativity instance that Ledgerline.Drift refutes.
-- Purpose: show the checker is really evaluating these terms.
module NegControl where
open import Ledgerline
open Drift

bad : dist (dist 1 1) 2 ≡ dist 1 (dist 1 2)
bad = refl
