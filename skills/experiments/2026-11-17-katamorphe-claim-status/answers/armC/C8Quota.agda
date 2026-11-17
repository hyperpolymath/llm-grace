{-# OPTIONS --safe #-}
-- Component 8: quota = (Nat, a ∸ b, 0).   (_∸_ is defined in Prelude.)
module C8Quota where

open import Prelude
open import MonoidFold

-- the one law that holds
∸-idʳ : ∀ a → a ∸ 0 ≡ a
∸-idʳ a = refl

-- the laws that fail
∸-no-idˡ : ¬ (∀ a → 0 ∸ a ≡ a)
∸-no-idˡ h with h 1
... | ()

left-grouping : (5 ∸ 3) ∸ 2 ≡ 0
left-grouping = refl

right-grouping : 5 ∸ (3 ∸ 2) ≡ 4
right-grouping = refl

∸-not-assoc : ¬ (∀ a b c → (a ∸ b) ∸ c ≡ a ∸ (b ∸ c))
∸-not-assoc h with h 5 3 2
... | ()

∸-not-comm : ¬ (∀ a b → a ∸ b ≡ b ∸ a)
∸-not-comm h with h 1 0
... | ()

-- a shard that starts from the "neutral" 0 loses everything it is given
shard-from-zero : ∀ ds → foldl _∸_ 0 ds ≡ 0
shard-from-zero []       = refl
shard-from-zero (d ∷ ds) = trans (cong (λ z → foldl _∸_ z ds) (0∸ d)) (shard-from-zero ds)

-- What is really there: debits (Nat, +, 0) act on a balance.
--   q ∸ 0 = q            (∸-idʳ above)
--   (q ∸ a) ∸ b = q ∸ (a + b)
∸-action : ∀ q a b → (q ∸ a) ∸ b ≡ q ∸ (a + b)
∸-action q       zero    b = refl
∸-action zero    (suc a) b = 0∸ b
∸-action (suc q) (suc a) b = ∸-action q a b

sum : List Nat → Nat
sum []       = 0
sum (d ∷ ds) = d + sum ds

-- applying debits one by one = subtracting their total once
sequential-is-one-subtraction : ∀ q ds → foldl _∸_ q ds ≡ q ∸ sum ds
sequential-is-one-subtraction q []       = refl
sequential-is-one-subtraction q (d ∷ ds) =
  trans (sequential-is-one-subtraction (q ∸ d) ds) (∸-action q d (sum ds))

-- and the total is a commutative-monoid fold, so THAT part can be sharded freely
+-monoid : IsMonoid _+_ 0
+-monoid = record { assoc = +-assoc ; idˡ = λ a → refl ; idʳ = +-zero }

open Fold _+_ 0 +-monoid
open CommFold _+_ 0 +-monoid +-comm

sum-is-fold : ∀ ds → sum ds ≡ fold ds
sum-is-fold []       = refl
sum-is-fold (d ∷ ds) = cong (d +_) (sum-is-fold ds)

debit-total-any-grouping-any-order : ∀ p q → items p ↭ items q → run p ≡ run q
debit-total-any-grouping-any-order = any-grouping-any-order

-- end to end: sequential application = initial balance ∸ (total computed by ANY plan)
quota-via-plan : ∀ q₀ p → foldl _∸_ q₀ (items p) ≡ q₀ ∸ run p
quota-via-plan q₀ p =
  trans (sequential-is-one-subtraction q₀ (items p))
        (cong (q₀ ∸_) (trans (sum-is-fold (items p)) (sym (run-is-fold p))))
