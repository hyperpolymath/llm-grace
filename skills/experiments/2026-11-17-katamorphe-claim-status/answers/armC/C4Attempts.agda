{-# OPTIONS --safe #-}
-- Component 4: attempts.
module C4Attempts where

open import Prelude

infixr 2 _,_
record Att (A : Set) : Set where
  constructor _,_
  field
    value    : A
    attempts : Nat
open Att

infixl 1 _>>=_
_>>=_ : {A B : Set} → Att A → (A → Att B) → Att B
m >>= f = value (f (value m)) , attempts m + attempts (f (value m))

-- ---------------------------------------------------------------------------
-- As designed: pure(v) = (v, 1)
pure : {A : Set} → A → Att A
pure v = v , 1

-- left identity: pure v >>= f  vs  f v.  Off by exactly one, at every call site.
left-count : {A B : Set} (f : A → Att B) (v : A)
           → attempts (pure v >>= f) ≡ suc (attempts (f v))
left-count f v = refl

left-identity-never-holds : {A B : Set} (f : A → Att B) (v : A)
                          → ¬ ((pure v >>= f) ≡ f v)
left-identity-never-holds f v e = suc≢self (attempts (f v)) (cong attempts e)

-- right identity: m >>= pure  vs  m.  Also off by one, always.
right-count : {A : Set} (m : Att A) → attempts (m >>= pure) ≡ suc (attempts m)
right-count m = +-comm (attempts m) 1

right-identity-never-holds : {A : Set} (m : Att A) → ¬ ((m >>= pure) ≡ m)
right-identity-never-holds m e =
  suc≢self (attempts m) (trans (sym (right-count m)) (cong attempts e))

-- associativity does hold (re-nesting a chain is fine)
>>=-assoc : {A B C : Set} (m : Att A) (f : A → Att B) (g : B → Att C)
          → ((m >>= f) >>= g) ≡ (m >>= (λ x → f x >>= g))
>>=-assoc m f g =
  cong (value (g (value (f (value m)))) ,_)
       (+-assoc (attempts m) (attempts (f (value m)))
                (attempts (g (value (f (value m))))))

-- the plain "apply f to the value" map is a functor ...
mapAtt : {A B : Set} → (A → B) → Att A → Att B
mapAtt f m = f (value m) , attempts m

mapAtt-id : {A : Set} (m : Att A) → mapAtt id m ≡ m
mapAtt-id m = refl

mapAtt-∘ : {A B C : Set} (f : A → B) (g : B → C) (m : Att A)
         → mapAtt g (mapAtt f m) ≡ mapAtt (g ∘ f) m
mapAtt-∘ f g m = refl

-- ... but it is not the map you get from >>= and pure (that one adds an attempt)
derived-map-differs : {A B : Set} (f : A → B) (m : Att A)
                    → ¬ ((m >>= (λ x → pure (f x))) ≡ mapAtt f m)
derived-map-differs f m e =
  suc≢self (attempts m) (trans (sym (+-comm (attempts m) 1)) (cong attempts e))

-- ---------------------------------------------------------------------------
-- Repair: pure₀(v) = (v, 0); count an attempt explicitly with `attempt`.
pure₀ : {A : Set} → A → Att A
pure₀ v = v , 0

attempt : {A : Set} → A → Att A      -- the old pure, under an honest name
attempt v = v , 1

left-identity₀ : {A B : Set} (f : A → Att B) (v : A) → (pure₀ v >>= f) ≡ f v
left-identity₀ f v = refl

right-identity₀ : {A : Set} (m : Att A) → (m >>= pure₀) ≡ m
right-identity₀ m = cong (value m ,_) (+-zero (attempts m))

-- associativity is the same proof: >>= did not change
assoc₀ : {A B C : Set} (m : Att A) (f : A → Att B) (g : B → Att C)
       → ((m >>= f) >>= g) ≡ (m >>= (λ x → f x >>= g))
assoc₀ = >>=-assoc
