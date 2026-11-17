{-# OPTIONS --safe #-}
-- Generic theorems: what the monoid laws buy you when folding in shards.
--   any-grouping            : monoid              => every bracketing of the same
--                                                   sequence (same order, empty shards
--                                                   allowed) gives the same result
--   any-grouping-any-order  : commutative monoid  => the same, for any reordering too
module MonoidFold where

open import Prelude

record IsMonoid {A : Set} (_∙_ : A → A → A) (ε : A) : Set where
  field
    assoc : ∀ a b c → (a ∙ b) ∙ c ≡ a ∙ (b ∙ c)
    idˡ   : ∀ a → ε ∙ a ≡ a
    idʳ   : ∀ a → a ∙ ε ≡ a

module Fold {A : Set} (_∙_ : A → A → A) (ε : A) (M : IsMonoid _∙_ ε) where
  open IsMonoid M

  -- reference result: plain sequential right fold
  fold : List A → A
  fold []       = ε
  fold (x ∷ xs) = x ∙ fold xs

  fold-++ : ∀ xs ys → fold (xs ++ ys) ≡ fold xs ∙ fold ys
  fold-++ []       ys = sym (idˡ (fold ys))
  fold-++ (x ∷ xs) ys =
    trans (cong (x ∙_) (fold-++ xs ys)) (sym (assoc x (fold xs) (fold ys)))

  -- a sequential left fold with an accumulator starting at ε is the same thing
  foldl-acc : ∀ a xs → foldl _∙_ a xs ≡ a ∙ fold xs
  foldl-acc a []       = sym (idʳ a)
  foldl-acc a (x ∷ xs) = trans (foldl-acc (a ∙ x) xs) (assoc a x (fold xs))

  foldl-is-fold : ∀ xs → foldl _∙_ ε xs ≡ fold xs
  foldl-is-fold xs = trans (foldl-acc ε xs) (idˡ (fold xs))

  -- A scheduler's plan: an arbitrary bracketing, possibly with empty shards.
  data Plan : Set where
    none : Plan                 -- an empty shard, contributes ε
    one  : A → Plan
    join : Plan → Plan → Plan

  run : Plan → A
  run none       = ε
  run (one a)    = a
  run (join l r) = run l ∙ run r

  items : Plan → List A         -- the values, left to right
  items none       = []
  items (one a)    = a ∷ []
  items (join l r) = items l ++ items r

  run-is-fold : ∀ p → run p ≡ fold (items p)
  run-is-fold none       = refl
  run-is-fold (one a)    = sym (idʳ a)
  run-is-fold (join l r) =
    trans (cong₂ _∙_ (run-is-fold l) (run-is-fold r))
          (sym (fold-++ (items l) (items r)))

  any-grouping : ∀ p q → items p ≡ items q → run p ≡ run q
  any-grouping p q e =
    trans (run-is-fold p) (trans (cong fold e) (sym (run-is-fold q)))

module CommFold {A : Set} (_∙_ : A → A → A) (ε : A) (M : IsMonoid _∙_ ε)
                (comm : ∀ a b → a ∙ b ≡ b ∙ a) where
  open IsMonoid M
  open Fold _∙_ ε M

  -- "ys is a rearrangement of xs"
  infix 4 _↭_
  data _↭_ : List A → List A → Set where
    done : [] ↭ []
    skip : ∀ {x xs ys} → xs ↭ ys → (x ∷ xs) ↭ (x ∷ ys)
    swap : ∀ {x y xs ys} → xs ↭ ys → (x ∷ y ∷ xs) ↭ (y ∷ x ∷ ys)
    then : ∀ {xs ys zs} → xs ↭ ys → ys ↭ zs → xs ↭ zs

  fold-perm : ∀ {xs ys} → xs ↭ ys → fold xs ≡ fold ys
  fold-perm done = refl
  fold-perm (skip {x} p) = cong (x ∙_) (fold-perm p)
  fold-perm (swap {x} {y} {xs} {ys} p) =
    trans (sym (assoc x y (fold xs)))
   (trans (cong (_∙ fold xs) (comm x y))
   (trans (assoc y x (fold xs))
          (cong (λ z → y ∙ (x ∙ z)) (fold-perm p))))
  fold-perm (then p q) = trans (fold-perm p) (fold-perm q)

  any-grouping-any-order : ∀ p q → items p ↭ items q → run p ≡ run q
  any-grouping-any-order p q e =
    trans (run-is-fold p) (trans (fold-perm e) (sym (run-is-fold q)))
