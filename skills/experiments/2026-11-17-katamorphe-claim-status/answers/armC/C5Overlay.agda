{-# OPTIONS --safe #-}
-- Component 5: overlay = (Maybe A, later-present-wins, absent).
module C5Overlay where

open import Prelude
open import MonoidFold

-- earlier ▹ later
infixl 6 _▹_
_▹_ : {A : Set} → Maybe A → Maybe A → Maybe A
e ▹ just x  = just x
e ▹ nothing = e

module _ {A : Set} where

  ▹-assoc : (a b c : Maybe A) → (a ▹ b) ▹ c ≡ a ▹ (b ▹ c)
  ▹-assoc a b (just x) = refl
  ▹-assoc a b nothing  = refl

  ▹-idˡ : (a : Maybe A) → nothing ▹ a ≡ a
  ▹-idˡ (just x) = refl
  ▹-idˡ nothing  = refl

  ▹-idʳ : (a : Maybe A) → a ▹ nothing ≡ a
  ▹-idʳ a = refl

  ▹-idem : (a : Maybe A) → a ▹ a ≡ a
  ▹-idem (just x) = refl
  ▹-idem nothing  = refl

  overlay-monoid : IsMonoid (_▹_ {A}) nothing
  overlay-monoid = record { assoc = ▹-assoc ; idˡ = ▹-idˡ ; idʳ = ▹-idʳ }

  open Fold (_▹_ {A}) nothing overlay-monoid

  -- any bracketing of the same layers in the same order, empty groups included
  overlay-any-grouping : ∀ p q → items p ≡ items q → run p ≡ run q
  overlay-any-grouping = any-grouping

-- order matters: not commutative
▹-not-comm : ¬ (∀ (a b : Maybe Nat) → a ▹ b ≡ b ▹ a)
▹-not-comm h with h (just 1) (just 2)
... | ()
