{-# OPTIONS --safe #-}
-- Component 3: drift = (Nat, |a − b|, 0).
module C3Drift where

open import Prelude

diff : Nat → Nat → Nat          -- |a − b|
diff zero    b       = b
diff (suc a) zero    = suc a
diff (suc a) (suc b) = diff a b

-- diff really is the absolute difference: |a − b| = (a ∸ b) + (b ∸ a)
diff-spec : ∀ a b → diff a b ≡ (a ∸ b) + (b ∸ a)
diff-spec zero    b       = cong (_+ b) (sym (0∸ b))
diff-spec (suc a) zero    = sym (+-zero (suc a))
diff-spec (suc a) (suc b) = diff-spec a b

-- laws that hold
diff-idˡ : ∀ a → diff 0 a ≡ a
diff-idˡ a = refl

diff-idʳ : ∀ a → diff a 0 ≡ a
diff-idʳ zero    = refl
diff-idʳ (suc a) = refl

diff-comm : ∀ a b → diff a b ≡ diff b a
diff-comm zero    zero    = refl
diff-comm zero    (suc b) = refl
diff-comm (suc a) zero    = refl
diff-comm (suc a) (suc b) = diff-comm a b

-- the law that fails: associativity
left-grouping : diff (diff 1 2) 3 ≡ 2
left-grouping = refl

right-grouping : diff 1 (diff 2 3) ≡ 0
right-grouping = refl

diff-not-assoc : ¬ (∀ a b c → diff (diff a b) c ≡ diff a (diff b c))
diff-not-assoc h with h 1 2 3
... | ()

-- consequence: even a plain sequential fold depends on the order of the readings
order-1-2-3 : foldl diff 0 (1 ∷ 2 ∷ 3 ∷ []) ≡ 2
order-1-2-3 = refl

order-2-3-1 : foldl diff 0 (2 ∷ 3 ∷ 1 ∷ []) ≡ 0
order-2-3-1 = refl
