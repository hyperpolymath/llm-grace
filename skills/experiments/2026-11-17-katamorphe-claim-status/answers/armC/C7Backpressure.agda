{-# OPTIONS --safe #-}
-- Component 7: backpressure = ({0..10}, min(a + b, 10), 0).
module C7Backpressure where

open import Prelude
open import MonoidFold

min : Nat → Nat → Nat
min zero    b       = zero
min (suc a) zero    = zero
min (suc a) (suc b) = suc (min a b)

cap : Nat → Nat
cap n = min n 10

-- A score is a natural number that capping leaves alone, i.e. one that is ≤ 10.
record Score : Set where
  constructor score
  field
    n  : Nat
    ok : cap n ≡ n
open Score

-- "cap n ≡ n" is the same thing as "n ≤ 10" (checked for any bound k)
data _≤_ : Nat → Nat → Set where
  z≤n : ∀ {k} → zero ≤ k
  s≤s : ∀ {a k} → a ≤ k → suc a ≤ suc k

min-fix→≤ : ∀ a k → min a k ≡ a → a ≤ k
min-fix→≤ zero    k       e = z≤n
min-fix→≤ (suc a) zero    ()
min-fix→≤ (suc a) (suc k) e = s≤s (min-fix→≤ a k (cong pred e))
  where
    pred : Nat → Nat
    pred zero    = zero
    pred (suc m) = m

≤→min-fix : ∀ {a k} → a ≤ k → min a k ≡ a
≤→min-fix z≤n     = refl
≤→min-fix (s≤s p) = cong suc (≤→min-fix p)

-- arithmetic lemmas ---------------------------------------------------------
min-0ʳ : ∀ a → min a 0 ≡ 0
min-0ʳ zero    = refl
min-0ʳ (suc a) = refl

min-idem : ∀ x k → min (min x k) k ≡ min x k
min-idem zero    k       = refl
min-idem (suc x) zero    = refl
min-idem (suc x) (suc k) = cong suc (min-idem x k)

-- capping early does not change the capped total
min-absorb : ∀ x c k → min (min x k + c) k ≡ min (x + c) k
min-absorb zero    c k       = refl
min-absorb (suc x) c zero    = min-0ʳ c
min-absorb (suc x) c (suc k) = cong suc (min-absorb x c k)

cap-assoc : ∀ a b c → cap (cap (a + b) + c) ≡ cap (a + cap (b + c))
cap-assoc a b c =
  trans (min-absorb (a + b) c 10)
 (trans (cong cap (+-assoc a b c))
 (trans (cong cap (+-comm a (b + c)))
 (trans (sym (min-absorb (b + c) a 10))
        (cong cap (+-comm (cap (b + c)) a)))))

-- the operation on scores -----------------------------------------------------
infixl 6 _⊕_
_⊕_ : Score → Score → Score
s ⊕ t = score (cap (n s + n t)) (min-idem (n s + n t) 10)

zero-score : Score
zero-score = score 0 refl

uip : {A : Set} {x y : A} (p q : x ≡ y) → p ≡ q
uip refl refl = refl

score-≡ : ∀ {s t} → n s ≡ n t → s ≡ t
score-≡ {score a p} {score .a q} refl = cong (score a) (uip p q)

⊕-assoc : ∀ a b c → (a ⊕ b) ⊕ c ≡ a ⊕ (b ⊕ c)
⊕-assoc a b c = score-≡ (cap-assoc (n a) (n b) (n c))

⊕-idˡ : ∀ a → zero-score ⊕ a ≡ a
⊕-idˡ a = score-≡ (ok a)

⊕-idʳ : ∀ a → a ⊕ zero-score ≡ a
⊕-idʳ a = score-≡ (trans (cong cap (+-zero (n a))) (ok a))

⊕-comm : ∀ a b → a ⊕ b ≡ b ⊕ a
⊕-comm a b = score-≡ (cong cap (+-comm (n a) (n b)))

backpressure-monoid : IsMonoid _⊕_ zero-score
backpressure-monoid = record { assoc = ⊕-assoc ; idˡ = ⊕-idˡ ; idʳ = ⊕-idʳ }

open Fold _⊕_ zero-score backpressure-monoid
open CommFold _⊕_ zero-score backpressure-monoid ⊕-comm

backpressure-any-grouping : ∀ p q → items p ≡ items q → run p ≡ run q
backpressure-any-grouping = any-grouping

backpressure-any-grouping-any-order : ∀ p q → items p ↭ items q → run p ≡ run q
backpressure-any-grouping-any-order = any-grouping-any-order

-- Warning made precise: 0 is neutral only for in-range values.
-- If an out-of-range value (here 11) ever enters, "0 combined with it" changes it.
out-of-range-breaks-identity : ¬ (cap (0 + 11) ≡ 11)
out-of-range-breaks-identity ()
