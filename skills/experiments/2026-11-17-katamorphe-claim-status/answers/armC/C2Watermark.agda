{-# OPTIONS --safe #-}
-- Component 2: watermark = (Nat, max, 0).
module C2Watermark where

open import Prelude
open import MonoidFold

max : Nat → Nat → Nat
max zero    b       = b
max (suc a) zero    = suc a
max (suc a) (suc b) = suc (max a b)

max-idˡ : ∀ a → max 0 a ≡ a
max-idˡ a = refl

max-idʳ : ∀ a → max a 0 ≡ a
max-idʳ zero    = refl
max-idʳ (suc a) = refl

max-assoc : ∀ a b c → max (max a b) c ≡ max a (max b c)
max-assoc zero    b       c       = refl
max-assoc (suc a) zero    c       = refl
max-assoc (suc a) (suc b) zero    = refl
max-assoc (suc a) (suc b) (suc c) = cong suc (max-assoc a b c)

max-comm : ∀ a b → max a b ≡ max b a
max-comm zero    zero    = refl
max-comm zero    (suc b) = refl
max-comm (suc a) zero    = refl
max-comm (suc a) (suc b) = cong suc (max-comm a b)

max-idem : ∀ a → max a a ≡ a
max-idem zero    = refl
max-idem (suc a) = cong suc (max-idem a)

max-monoid : IsMonoid max 0
max-monoid = record { assoc = max-assoc ; idˡ = max-idˡ ; idʳ = max-idʳ }

open Fold max 0 max-monoid
open CommFold max 0 max-monoid max-comm

-- any bracketing of the same marks, empty shards included, same order
watermark-any-grouping : ∀ p q → items p ≡ items q → run p ≡ run q
watermark-any-grouping = any-grouping

-- any bracketing of any rearrangement of the marks
watermark-any-grouping-any-order : ∀ p q → items p ↭ items q → run p ≡ run q
watermark-any-grouping-any-order = any-grouping-any-order
