{-# OPTIONS --safe #-}
-- Component 6: transformBatch(f) = reverse ∘ map f.
module C6TransformBatch where

open import Prelude

rev : {A : Set} → List A → List A
rev []       = []
rev (x ∷ xs) = rev xs ++ (x ∷ [])

tb : {A B : Set} → (A → B) → List A → List B     -- transformBatch
tb f xs = rev (map f xs)

-- list lemmas ---------------------------------------------------------------
++-[] : {A : Set} (xs : List A) → xs ++ [] ≡ xs
++-[] []       = refl
++-[] (x ∷ xs) = cong (x ∷_) (++-[] xs)

++-assoc : {A : Set} (xs ys zs : List A) → (xs ++ ys) ++ zs ≡ xs ++ (ys ++ zs)
++-assoc []       ys zs = refl
++-assoc (x ∷ xs) ys zs = cong (x ∷_) (++-assoc xs ys zs)

rev-++ : {A : Set} (xs ys : List A) → rev (xs ++ ys) ≡ rev ys ++ rev xs
rev-++ []       ys = sym (++-[] (rev ys))
rev-++ (x ∷ xs) ys =
  trans (cong (_++ (x ∷ [])) (rev-++ xs ys)) (++-assoc (rev ys) (rev xs) (x ∷ []))

rev-rev : {A : Set} (xs : List A) → rev (rev xs) ≡ xs
rev-rev []       = refl
rev-rev (x ∷ xs) = trans (rev-++ (rev xs) (x ∷ [])) (cong (x ∷_) (rev-rev xs))

map-++ : {A B : Set} (f : A → B) (xs ys : List A)
       → map f (xs ++ ys) ≡ map f xs ++ map f ys
map-++ f []       ys = refl
map-++ f (x ∷ xs) ys = cong (f x ∷_) (map-++ f xs ys)

-- reverse is natural: it commutes with map f
map-rev : {A B : Set} (f : A → B) (xs : List A) → map f (rev xs) ≡ rev (map f xs)
map-rev f []       = refl
map-rev f (x ∷ xs) =
  trans (map-++ f (rev xs) (x ∷ [])) (cong (_++ (f x ∷ [])) (map-rev f xs))

-- plain map IS a functor
map-id : {A : Set} (xs : List A) → map id xs ≡ xs
map-id []       = refl
map-id (x ∷ xs) = cong (x ∷_) (map-id xs)

map-∘ : {A B C : Set} (f : A → B) (g : B → C) (xs : List A)
      → map g (map f xs) ≡ map (g ∘ f) xs
map-∘ f g []       = refl
map-∘ f g (x ∷ xs) = cong (g (f x) ∷_) (map-∘ f g xs)

-- transformBatch is NOT a functor --------------------------------------------
tb-id-fails : ¬ (∀ (xs : List Nat) → tb id xs ≡ xs)
tb-id-fails h with h (1 ∷ 2 ∷ [])
... | ()

two-calls : tb id (tb id (1 ∷ 2 ∷ [])) ≡ 1 ∷ 2 ∷ []
two-calls = refl

fused : tb (id ∘ id) (1 ∷ 2 ∷ []) ≡ 2 ∷ 1 ∷ []
fused = refl

tb-fuse-fails :
  ¬ (∀ (f g : Nat → Nat) xs → tb g (tb f xs) ≡ tb (g ∘ f) xs)
tb-fuse-fails h with h id id (1 ∷ 2 ∷ [])
... | ()

-- what two calls actually compute: a plain map, original order (reversals cancel)
tb-tb : {A B C : Set} (f : A → B) (g : B → C) (xs : List A)
      → tb g (tb f xs) ≡ map (g ∘ f) xs
tb-tb f g xs =
  trans (cong rev (map-rev g (map f xs)))
 (trans (rev-rev (map g (map f xs)))
        (map-∘ f g xs))

-- so the planned fusion returns exactly the reverse of what the pipeline returns today
planned-fusion-is-reversed : {A B C : Set} (f : A → B) (g : B → C) (xs : List A)
  → tb (g ∘ f) xs ≡ rev (tb g (tb f xs))
planned-fusion-is-reversed f g xs = cong rev (sym (tb-tb f g xs))

-- three calls do fuse into one transformBatch (odd number of reversals)
tb-tb-tb : {A B C D : Set} (f : A → B) (g : B → C) (h : C → D) (xs : List A)
         → tb h (tb g (tb f xs)) ≡ tb (h ∘ g ∘ f) xs
tb-tb-tb f g h xs =
  trans (cong (tb h) (tb-tb f g xs)) (cong rev (map-∘ (g ∘ f) h xs))
