{-# OPTIONS --safe --cubical #-}
module CubicalLayer where
open import Agda.Primitive.Cubical using (I; i0; i1)
open import Agda.Builtin.Cubical.Path using (PathP)
open import Core using (ℕ; _+_; zero; +-idʳ)
Path : (A : Set) → A → A → Set
Path A x y = PathP (λ _ → A) x y
-- function extensionality: provable here, not in the canonical profile
funExt : {A B : Set} {f g : A → B} → ((x : A) → Path B (f x) (g x)) → Path (A → B) f g
funExt h i x = h x i
