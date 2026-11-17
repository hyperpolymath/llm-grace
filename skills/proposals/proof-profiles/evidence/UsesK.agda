{-# OPTIONS --safe --without-K --cubical-compatible #-}
module UsesK where
data _≡_ {A : Set} (x : A) : A → Set where
  refl : x ≡ x
uip : {A : Set} {x : A} (p : x ≡ x) → p ≡ refl
uip refl = refl
