{-# OPTIONS --safe #-}
-- Shared definitions. No standard library; only Agda's builtin Nat, List, Maybe, _≡_.
module Prelude where

open import Agda.Builtin.Equality public
open import Agda.Builtin.Nat public using (Nat; zero; suc; _+_)
open import Agda.Builtin.List public
open import Agda.Builtin.Maybe public

data ⊥ : Set where

infix 3 ¬_
¬_ : Set → Set
¬ A = A → ⊥

sym : {A : Set} {x y : A} → x ≡ y → y ≡ x
sym refl = refl

trans : {A : Set} {x y z : A} → x ≡ y → y ≡ z → x ≡ z
trans refl q = q

cong : {A B : Set} (f : A → B) {x y : A} → x ≡ y → f x ≡ f y
cong f refl = refl

cong₂ : {A B C : Set} (f : A → B → C) {x x' : A} {y y' : B}
      → x ≡ x' → y ≡ y' → f x y ≡ f x' y'
cong₂ f refl refl = refl

id : {A : Set} → A → A
id x = x

infixr 9 _∘_
_∘_ : {A B C : Set} → (B → C) → (A → B) → A → C
(g ∘ f) x = g (f x)

-- arithmetic on Nat ---------------------------------------------------------

+-zero : ∀ a → a + 0 ≡ a
+-zero zero    = refl
+-zero (suc a) = cong suc (+-zero a)

+-suc : ∀ a b → a + suc b ≡ suc (a + b)
+-suc zero    b = refl
+-suc (suc a) b = cong suc (+-suc a b)

+-assoc : ∀ a b c → (a + b) + c ≡ a + (b + c)
+-assoc zero    b c = refl
+-assoc (suc a) b c = cong suc (+-assoc a b c)

+-comm : ∀ a b → a + b ≡ b + a
+-comm zero    b = sym (+-zero b)
+-comm (suc a) b = trans (cong suc (+-comm a b)) (sym (+-suc b a))

suc≢self : ∀ n → ¬ (suc n ≡ n)
suc≢self zero    ()
suc≢self (suc n) e = suc≢self n (cong pred e)
  where
    pred : Nat → Nat
    pred zero    = zero
    pred (suc k) = k

-- truncated subtraction, written out so the definition is visible
infixl 6 _∸_
_∸_ : Nat → Nat → Nat
a     ∸ zero  = a
zero  ∸ suc b = zero
suc a ∸ suc b = a ∸ b

0∸ : ∀ b → 0 ∸ b ≡ 0
0∸ zero    = refl
0∸ (suc b) = refl

-- lists ---------------------------------------------------------------------

infixr 5 _++_
_++_ : {A : Set} → List A → List A → List A
[]       ++ ys = ys
(x ∷ xs) ++ ys = x ∷ (xs ++ ys)

map : {A B : Set} → (A → B) → List A → List B
map f []       = []
map f (x ∷ xs) = f x ∷ map f xs

foldl : {A B : Set} → (B → A → B) → B → List A → B
foldl f b []       = b
foldl f b (x ∷ xs) = foldl f (f b x) xs
