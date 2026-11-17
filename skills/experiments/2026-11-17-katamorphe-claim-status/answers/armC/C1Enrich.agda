{-# OPTIONS --safe #-}
-- Component 1: enrich.
module C1Enrich where

open import Prelude

-- Model A: absence is a separate case of the type (Maybe / Option).
-- f works on present values and cannot itself produce "absent".
enrich : {A B : Set} → (A → B) → Maybe A → Maybe B
enrich f nothing  = nothing
enrich f (just a) = just (f a)

-- functor law 1 (identity): justifies deleting enrich(identity)
enrich-id : {A : Set} (x : Maybe A) → enrich id x ≡ x
enrich-id nothing  = refl
enrich-id (just a) = refl

-- functor law 2 (composition): justifies the fusion
enrich-fuse : {A B C : Set} (f : A → B) (g : B → C) (x : Maybe A)
            → enrich g (enrich f x) ≡ enrich (g ∘ f) x
enrich-fuse f g nothing  = refl
enrich-fuse f g (just a) = refl

-- Model B: absence is an in-band value (null / None / undefined) and f is an
-- ordinary function on nullable values, so f may return null for a present input.
data V : Set where
  null : V
  val  : Nat → V

enrichN : (V → V) → V → V
enrichN f null    = null
enrichN f (val n) = f (val n)

-- deleting enrichN(identity) is still fine
enrichN-id : ∀ x → enrichN id x ≡ x
enrichN-id null    = refl
enrichN-id (val n) = refl

-- but fusion with plain composition is NOT: f returns null, g maps null to a value
f₀ g₀ : V → V
f₀ _ = null
g₀ _ = val 0

two-calls : enrichN g₀ (enrichN f₀ (val 1)) ≡ null
two-calls = refl

fused : enrichN (g₀ ∘ f₀) (val 1) ≡ val 0
fused = refl

enrichN-fuse-fails :
  ¬ (∀ (f g : V → V) x → enrichN g (enrichN f x) ≡ enrichN (g ∘ f) x)
enrichN-fuse-fails h with h f₀ g₀ (val 1)
... | ()

-- the fusion that is valid in model B keeps the null check between f and g
enrichN-fuse-guarded : ∀ (f g : V → V) x
  → enrichN g (enrichN f x) ≡ enrichN (λ v → enrichN g (f v)) x
enrichN-fuse-guarded f g null    = refl
enrichN-fuse-guarded f g (val n) = refl
