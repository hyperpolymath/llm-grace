{-# OPTIONS --safe --without-K #-}

-- Machine checks for the Ledgerline ingest design note (draft 3).
-- Self-contained: no standard library, no postulates, no holes.
-- Check with:  LC_ALL=C.UTF-8 agda Ledgerline.agda
--
-- All function equalities are stated POINTWISE (for every input), so no
-- function-extensionality axiom is needed.

module Ledgerline where

------------------------------------------------------------------------
-- Prelude
------------------------------------------------------------------------

infix 4 _≡_
data _≡_ {A : Set} (x : A) : A → Set where
  refl : x ≡ x

sym : {A : Set} {x y : A} → x ≡ y → y ≡ x
sym refl = refl

trans : {A : Set} {x y z : A} → x ≡ y → y ≡ z → x ≡ z
trans refl q = q

cong : {A B : Set} (f : A → B) {x y : A} → x ≡ y → f x ≡ f y
cong f refl = refl

cong₂ : {A B C : Set} (f : A → B → C) {x x′ : A} {y y′ : B}
      → x ≡ x′ → y ≡ y′ → f x y ≡ f x′ y′
cong₂ f refl refl = refl

data ⊥ : Set where

infix 3 ¬_
¬_ : Set → Set
¬ A = A → ⊥

data ℕ : Set where
  zero : ℕ
  suc  : ℕ → ℕ
{-# BUILTIN NATURAL ℕ #-}

infixl 6 _+_ _∸_
_+_ : ℕ → ℕ → ℕ
zero  + n = n
suc m + n = suc (m + n)

-- truncated subtraction ("monus")
_∸_ : ℕ → ℕ → ℕ
m     ∸ zero  = m
zero  ∸ suc n = zero
suc m ∸ suc n = m ∸ n

max : ℕ → ℕ → ℕ
max zero    n       = n
max (suc m) zero    = suc m
max (suc m) (suc n) = suc (max m n)

min : ℕ → ℕ → ℕ
min zero    n       = zero
min (suc m) zero    = zero
min (suc m) (suc n) = suc (min m n)

infix 4 _≤_
data _≤_ : ℕ → ℕ → Set where
  z≤n : {n : ℕ} → zero ≤ n
  s≤s : {m n : ℕ} → m ≤ n → suc m ≤ suc n

≤-refl : (n : ℕ) → n ≤ n
≤-refl zero    = z≤n
≤-refl (suc n) = s≤s (≤-refl n)

pred : ℕ → ℕ
pred zero    = zero
pred (suc n) = n

+-identityʳ : (n : ℕ) → n + 0 ≡ n
+-identityʳ zero    = refl
+-identityʳ (suc n) = cong suc (+-identityʳ n)

+-suc : (m n : ℕ) → m + suc n ≡ suc (m + n)
+-suc zero    n = refl
+-suc (suc m) n = cong suc (+-suc m n)

+-assoc : (a b c : ℕ) → (a + b) + c ≡ a + (b + c)
+-assoc zero    b c = refl
+-assoc (suc a) b c = cong suc (+-assoc a b c)

+-comm : (m n : ℕ) → m + n ≡ n + m
+-comm zero    n = sym (+-identityʳ n)
+-comm (suc m) n = trans (cong suc (+-comm m n)) (sym (+-suc n m))

suc≢self : (n : ℕ) → ¬ (suc n ≡ n)
suc≢self zero    ()
suc≢self (suc n) p = suc≢self n (cong pred p)

data Maybe (A : Set) : Set where
  nothing : Maybe A
  just    : A → Maybe A

infixr 5 _∷_ _++_
data List (A : Set) : Set where
  []  : List A
  _∷_ : A → List A → List A

_++_ : {A : Set} → List A → List A → List A
[]       ++ ys = ys
(x ∷ xs) ++ ys = x ∷ (xs ++ ys)

map : {A B : Set} → (A → B) → List A → List B
map f []       = []
map f (x ∷ xs) = f x ∷ map f xs

concat : {A : Set} → List (List A) → List A
concat []         = []
concat (xs ∷ xss) = xs ++ concat xss

infixr 4 _,_
record _×_ (A B : Set) : Set where
  constructor _,_
  field
    fst : A
    snd : B
open _×_

------------------------------------------------------------------------
-- Generic: what "fold in any grouping" needs, and that a monoid gives it
------------------------------------------------------------------------

module Fold {M : Set} (_·_ : M → M → M) (e : M)
            (assoc : (a b c : M) → (a · b) · c ≡ a · (b · c))
            (idˡ   : (a : M) → e · a ≡ a)
            (idʳ   : (a : M) → a · e ≡ a) where

  -- sequential reference: start from the neutral value, absorb left to right
  foldl : M → List M → M
  foldl acc []       = acc
  foldl acc (x ∷ xs) = foldl (acc · x) xs

  fold : List M → M
  fold []       = e
  fold (x ∷ xs) = x · fold xs

  foldl-fold : (acc : M) (xs : List M) → foldl acc xs ≡ acc · fold xs
  foldl-fold acc []       = sym (idʳ acc)
  foldl-fold acc (x ∷ xs) = trans (foldl-fold (acc · x) xs) (assoc acc x (fold xs))

  sequential : (xs : List M) → foldl e xs ≡ fold xs
  sequential xs = trans (foldl-fold e xs) (idˡ (fold xs))

  fold-++ : (xs ys : List M) → fold (xs ++ ys) ≡ fold xs · fold ys
  fold-++ []       ys = sym (idˡ (fold ys))
  fold-++ (x ∷ xs) ys =
    trans (cong (x ·_) (fold-++ xs ys)) (sym (assoc x (fold xs) (fold ys)))

  -- Shard theorem: cut the sequence into consecutive shards (some possibly
  -- empty), fold every shard from the neutral value, fold the shard results
  -- in shard order: same answer as folding the whole sequence.
  fold-shards : (xss : List (List M)) → fold (map fold xss) ≡ fold (concat xss)
  fold-shards []         = refl
  fold-shards (xs ∷ xss) =
    trans (cong (fold xs ·_) (fold-shards xss)) (sym (fold-++ xs (concat xss)))

  -- Arbitrary grouping = arbitrary binary tree over the sequence.
  data Tree : Set where
    empty : Tree
    leaf  : M → Tree
    node  : Tree → Tree → Tree

  foldT : Tree → M
  foldT empty      = e
  foldT (leaf x)   = x
  foldT (node l r) = foldT l · foldT r

  flatten : Tree → List M
  flatten empty      = []
  flatten (leaf x)   = x ∷ []
  flatten (node l r) = flatten l ++ flatten r

  foldT-flatten : (t : Tree) → foldT t ≡ fold (flatten t)
  foldT-flatten empty      = refl
  foldT-flatten (leaf x)   = sym (idʳ x)
  foldT-flatten (node l r) =
    trans (cong₂ _·_ (foldT-flatten l) (foldT-flatten r))
          (sym (fold-++ (flatten l) (flatten r)))

  -- Any two groupings of the same sequence (same order) agree, and agree
  -- with the sequential left-to-right fold.
  regroup : (t u : Tree) → flatten t ≡ flatten u → foldT t ≡ foldT u
  regroup t u p =
    trans (foldT-flatten t) (trans (cong fold p) (sym (foldT-flatten u)))

  grouping-vs-sequential : (t : Tree) → foldT t ≡ foldl e (flatten t)
  grouping-vs-sequential t = trans (foldT-flatten t) (sym (sequential (flatten t)))

  -- With commutativity, two adjacent blocks may also be swapped.
  module Commutative (comm : (a b : M) → a · b ≡ b · a) where
    swap-blocks : (xs ys : List M) → fold (xs ++ ys) ≡ fold (ys ++ xs)
    swap-blocks xs ys =
      trans (fold-++ xs ys) (trans (comm (fold xs) (fold ys)) (sym (fold-++ ys xs)))

    -- Arbitrary reordering: the usual permutation relation on lists.
    data Perm : List M → List M → Set where
      nil  : Perm [] []
      skip : {x : M} {xs ys : List M} → Perm xs ys → Perm (x ∷ xs) (x ∷ ys)
      swap : {x y : M} {xs : List M} → Perm (x ∷ y ∷ xs) (y ∷ x ∷ xs)
      tran : {xs ys zs : List M} → Perm xs ys → Perm ys zs → Perm xs zs

    fold-perm : {xs ys : List M} → Perm xs ys → fold xs ≡ fold ys
    fold-perm nil                    = refl
    fold-perm (skip {x} p)           = cong (x ·_) (fold-perm p)
    fold-perm (swap {x} {y} {xs})    =
      trans (sym (assoc x y (fold xs)))
            (trans (cong (_· fold xs) (comm x y)) (assoc y x (fold xs)))
    fold-perm (tran p q)             = trans (fold-perm p) (fold-perm q)

------------------------------------------------------------------------
-- 1. enrich
------------------------------------------------------------------------

module Enrich where

  enrich : {A B : Set} → (A → B) → Maybe A → Maybe B
  enrich f nothing  = nothing
  enrich f (just x) = just (f x)

  -- delete enrich(identity)
  enrich-id : {A : Set} (m : Maybe A) → enrich (λ x → x) m ≡ m
  enrich-id nothing  = refl
  enrich-id (just x) = refl

  -- fuse enrich(g) after enrich(f)
  enrich-fuse : {A B C : Set} (f : A → B) (g : B → C) (m : Maybe A)
              → enrich g (enrich f m) ≡ enrich (λ x → g (f x)) m
  enrich-fuse f g nothing  = refl
  enrich-fuse f g (just x) = refl

  -- CAVEAT MODEL: "absent" is an ordinary value of the field type (null),
  -- so f may itself return it.  V = Maybe ℕ plays "nullable number",
  -- nothing plays null, and functions act on V directly.
  V : Set
  V = Maybe ℕ

  enrichNull : (V → V) → V → V
  enrichNull f nothing  = nothing
  enrichNull f (just x) = f (just x)

  f₀ : V → V          -- a step that can produce null
  f₀ _ = nothing

  g₀ : V → V          -- a step that maps null to a default
  g₀ nothing  = just 0
  g₀ (just x) = just x

  two-calls : enrichNull g₀ (enrichNull f₀ (just 1)) ≡ nothing
  two-calls = refl

  fused-call : enrichNull (λ v → g₀ (f₀ v)) (just 1) ≡ just 0
  fused-call = refl

  fusion-fails-with-null :
    ¬ (enrichNull g₀ (enrichNull f₀ (just 1)) ≡ enrichNull (λ v → g₀ (f₀ v)) (just 1))
  fusion-fails-with-null ()

------------------------------------------------------------------------
-- 2. watermark
------------------------------------------------------------------------

module Watermark where

  max-idˡ : (a : ℕ) → max 0 a ≡ a
  max-idˡ a = refl

  max-idʳ : (a : ℕ) → max a 0 ≡ a
  max-idʳ zero    = refl
  max-idʳ (suc a) = refl

  max-assoc : (a b c : ℕ) → max (max a b) c ≡ max a (max b c)
  max-assoc zero    b       c       = refl
  max-assoc (suc a) zero    c       = refl
  max-assoc (suc a) (suc b) zero    = refl
  max-assoc (suc a) (suc b) (suc c) = cong suc (max-assoc a b c)

  max-comm : (a b : ℕ) → max a b ≡ max b a
  max-comm zero    zero    = refl
  max-comm zero    (suc b) = refl
  max-comm (suc a) zero    = refl
  max-comm (suc a) (suc b) = cong suc (max-comm a b)

  max-idem : (a : ℕ) → max a a ≡ a
  max-idem zero    = refl
  max-idem (suc a) = cong suc (max-idem a)

  -- max is the least upper bound for ≤, and 0 is the least element
  max-ub₁ : (a b : ℕ) → a ≤ max a b
  max-ub₁ zero    b       = z≤n
  max-ub₁ (suc a) zero    = ≤-refl (suc a)
  max-ub₁ (suc a) (suc b) = s≤s (max-ub₁ a b)

  max-ub₂ : (a b : ℕ) → b ≤ max a b
  max-ub₂ a       zero    = z≤n
  max-ub₂ zero    (suc b) = s≤s (max-ub₂ zero b)
  max-ub₂ (suc a) (suc b) = s≤s (max-ub₂ a b)

  max-least : {a b c : ℕ} → a ≤ c → b ≤ c → max a b ≤ c
  max-least z≤n     q       = q
  max-least (s≤s p) z≤n     = s≤s p
  max-least (s≤s p) (s≤s q) = s≤s (max-least p q)

  open Fold max 0 max-assoc max-idˡ max-idʳ public
  open Commutative max-comm public

------------------------------------------------------------------------
-- 3. drift
------------------------------------------------------------------------

module Drift where

  -- |a − b| on ℕ
  dist : ℕ → ℕ → ℕ
  dist zero    n       = n
  dist (suc m) zero    = suc m
  dist (suc m) (suc n) = dist m n

  -- formalisation guard: dist really is the absolute difference
  dist-spec : (a b : ℕ) → dist a b ≡ (a ∸ b) + (b ∸ a)
  dist-spec zero    zero    = refl
  dist-spec zero    (suc b) = refl
  dist-spec (suc a) zero    = sym (+-identityʳ (suc a))
  dist-spec (suc a) (suc b) = dist-spec a b

  dist-idˡ : (a : ℕ) → dist 0 a ≡ a
  dist-idˡ a = refl

  dist-idʳ : (a : ℕ) → dist a 0 ≡ a
  dist-idʳ zero    = refl
  dist-idʳ (suc a) = refl

  dist-comm : (a b : ℕ) → dist a b ≡ dist b a
  dist-comm zero    zero    = refl
  dist-comm zero    (suc b) = refl
  dist-comm (suc a) zero    = refl
  dist-comm (suc a) (suc b) = dist-comm a b

  -- NOT associative
  left-grouping : dist (dist 1 1) 2 ≡ 2
  left-grouping = refl

  right-grouping : dist 1 (dist 1 2) ≡ 0
  right-grouping = refl

  not-assoc : ¬ ((a b c : ℕ) → dist (dist a b) c ≡ dist a (dist b c))
  not-assoc h with h 1 1 2
  ... | ()

  -- the note's plan on readings 1,1,2: sequential from 0 versus shards [1] | [1,2]
  foldl : ℕ → List ℕ → ℕ
  foldl acc []       = acc
  foldl acc (x ∷ xs) = foldl (dist acc x) xs

  sequential-run : foldl 0 (1 ∷ 1 ∷ 2 ∷ []) ≡ 2
  sequential-run = refl

  sharded-run : dist (foldl 0 (1 ∷ [])) (foldl 0 (1 ∷ 2 ∷ [])) ≡ 0
  sharded-run = refl

------------------------------------------------------------------------
-- 4. attempts
------------------------------------------------------------------------

module Attempts where

  Att : Set → Set
  Att A = A × ℕ

  infixl 1 _>>=_
  _>>=_ : {A B : Set} → Att A → (A → Att B) → Att B
  m >>= f = fst (f (fst m)) , snd m + snd (f (fst m))

  -- the note's unit
  pure₁ : {A : Set} → A → Att A
  pure₁ v = v , 1

  -- the planned rewrite  pure(v) >>= f  ⟶  f(v)  is wrong for EVERY f and v
  left-identity-fails : {A B : Set} (f : A → Att B) (v : A) → ¬ ((pure₁ v >>= f) ≡ f v)
  left-identity-fails f v p = suc≢self (snd (f v)) (cong snd p)

  right-identity-fails : {A : Set} (m : Att A) → ¬ ((m >>= pure₁) ≡ m)
  right-identity-fails m p =
    suc≢self (snd m)
      (trans (sym (trans (+-suc (snd m) 0) (cong suc (+-identityʳ (snd m)))))
             (cong snd p))

  concrete : (pure₁ 7 >>= (λ v → v , 5)) ≡ (7 , 6)
  concrete = refl

  -- bind IS associative (this law does not mention pure)
  bind-assoc : {A B C : Set} (m : Att A) (f : A → Att B) (g : B → Att C)
             → ((m >>= f) >>= g) ≡ (m >>= (λ x → f x >>= g))
  bind-assoc m f g =
    cong (fst (g (fst (f (fst m)))) ,_)
         (+-assoc (snd m) (snd (f (fst m))) (snd (g (fst (f (fst m))))))

  -- the unit is forced: if pure v = (v , k) satisfies left identity, k = 0
  unit-forced : (k : ℕ)
              → ((f : ℕ → Att ℕ) (v : ℕ) → (((v , k) >>= f) ≡ f v))
              → k ≡ 0
  unit-forced k h = trans (sym (+-identityʳ k)) (cong snd (h (λ v → v , 0) 0))

  -- repaired unit: Writer monad over (ℕ, +, 0)
  pure₀ : {A : Set} → A → Att A
  pure₀ v = v , 0

  left-identity₀ : {A B : Set} (f : A → Att B) (v : A) → (pure₀ v >>= f) ≡ f v
  left-identity₀ f v = refl

  right-identity₀ : {A : Set} (m : Att A) → (m >>= pure₀) ≡ m
  right-identity₀ m = cong (fst m ,_) (+-identityʳ (snd m))

  -- counting is a separate, explicit effect
  tick : Att ℕ
  tick = 0 , 1

  -- the value-only map is a functor
  amap : {A B : Set} → (A → B) → Att A → Att B
  amap f m = f (fst m) , snd m

  amap-id : {A : Set} (m : Att A) → amap (λ x → x) m ≡ m
  amap-id m = refl

  amap-∘ : {A B C : Set} (f : A → B) (g : B → C) (m : Att A)
         → amap g (amap f m) ≡ amap (λ x → g (f x)) m
  amap-∘ f g m = refl

  -- but "map defined through bind and the note's pure" is NOT that functor
  derived-map-miscounts : (m : Att ℕ) → ¬ ((m >>= (λ x → pure₁ x)) ≡ amap (λ x → x) m)
  derived-map-miscounts m = right-identity-fails m

------------------------------------------------------------------------
-- 5. overlay
------------------------------------------------------------------------

module Overlay {A : Set} where

  -- earlier ◁ later : the later layer wins when it has a setting
  infixl 6 _◁_
  _◁_ : Maybe A → Maybe A → Maybe A
  x ◁ nothing = x
  x ◁ just b  = just b

  ◁-idʳ : (x : Maybe A) → x ◁ nothing ≡ x
  ◁-idʳ x = refl

  ◁-idˡ : (y : Maybe A) → nothing ◁ y ≡ y
  ◁-idˡ nothing  = refl
  ◁-idˡ (just b) = refl

  ◁-assoc : (x y z : Maybe A) → (x ◁ y) ◁ z ≡ x ◁ (y ◁ z)
  ◁-assoc x y nothing  = refl
  ◁-assoc x y (just c) = refl

  ◁-idem : (x : Maybe A) → x ◁ x ≡ x
  ◁-idem nothing  = refl
  ◁-idem (just a) = refl

  open Fold _◁_ nothing ◁-assoc ◁-idˡ ◁-idʳ public

module OverlayOrderMatters where
  open Overlay {ℕ}

  one-then-two : just 1 ◁ just 2 ≡ just 2
  one-then-two = refl

  two-then-one : just 2 ◁ just 1 ≡ just 1
  two-then-one = refl

  not-comm : ¬ ((x y : Maybe ℕ) → x ◁ y ≡ y ◁ x)
  not-comm h with h (just 1) (just 2)
  ... | ()

------------------------------------------------------------------------
-- 6. transformBatch
------------------------------------------------------------------------

module TransformBatch where

  rev : {A : Set} → List A → List A
  rev []       = []
  rev (x ∷ xs) = rev xs ++ (x ∷ [])

  tb : {A B : Set} → (A → B) → List A → List B
  tb f xs = rev (map f xs)

  ++-[] : {A : Set} (xs : List A) → xs ++ [] ≡ xs
  ++-[] []       = refl
  ++-[] (x ∷ xs) = cong (x ∷_) (++-[] xs)

  ++-assoc : {A : Set} (xs ys zs : List A) → (xs ++ ys) ++ zs ≡ xs ++ (ys ++ zs)
  ++-assoc []       ys zs = refl
  ++-assoc (x ∷ xs) ys zs = cong (x ∷_) (++-assoc xs ys zs)

  map-++ : {A B : Set} (f : A → B) (xs ys : List A)
         → map f (xs ++ ys) ≡ map f xs ++ map f ys
  map-++ f []       ys = refl
  map-++ f (x ∷ xs) ys = cong (f x ∷_) (map-++ f xs ys)

  map-∘ : {A B C : Set} (f : A → B) (g : B → C) (xs : List A)
        → map g (map f xs) ≡ map (λ x → g (f x)) xs
  map-∘ f g []       = refl
  map-∘ f g (x ∷ xs) = cong (g (f x) ∷_) (map-∘ f g xs)

  map-id : {A : Set} (xs : List A) → map (λ x → x) xs ≡ xs
  map-id []       = refl
  map-id (x ∷ xs) = cong (x ∷_) (map-id xs)

  rev-++ : {A : Set} (xs ys : List A) → rev (xs ++ ys) ≡ rev ys ++ rev xs
  rev-++ []       ys = sym (++-[] (rev ys))
  rev-++ (x ∷ xs) ys =
    trans (cong (_++ (x ∷ [])) (rev-++ xs ys)) (++-assoc (rev ys) (rev xs) (x ∷ []))

  rev-rev : {A : Set} (xs : List A) → rev (rev xs) ≡ xs
  rev-rev []       = refl
  rev-rev (x ∷ xs) = trans (rev-++ (rev xs) (x ∷ [])) (cong (x ∷_) (rev-rev xs))

  map-rev : {A B : Set} (f : A → B) (xs : List A) → map f (rev xs) ≡ rev (map f xs)
  map-rev f []       = refl
  map-rev f (x ∷ xs) =
    trans (map-++ f (rev xs) (x ∷ [])) (cong (_++ (f x ∷ [])) (map-rev f xs))

  -- identity law fails
  id-run : tb (λ x → x) (1 ∷ 2 ∷ 3 ∷ []) ≡ (3 ∷ 2 ∷ 1 ∷ [])
  id-run = refl

  identity-law-fails : ¬ ((xs : List ℕ) → tb (λ x → x) xs ≡ xs)
  identity-law-fails h with h (1 ∷ 2 ∷ [])
  ... | ()

  -- composition law fails: the planned fusion flips the batch
  two-calls : tb suc (tb suc (1 ∷ 2 ∷ 3 ∷ [])) ≡ (3 ∷ 4 ∷ 5 ∷ [])
  two-calls = refl

  fused-call : tb (λ x → suc (suc x)) (1 ∷ 2 ∷ 3 ∷ []) ≡ (5 ∷ 4 ∷ 3 ∷ [])
  fused-call = refl

  fusion-fails : ¬ ((f g : ℕ → ℕ) (xs : List ℕ) → tb g (tb f xs) ≡ tb (λ x → g (f x)) xs)
  fusion-fails h with h suc suc (1 ∷ 2 ∷ [])
  ... | ()

  -- what two consecutive calls actually equal: a plain, order-preserving map
  two-calls-law : {A B C : Set} (f : A → B) (g : B → C) (xs : List A)
                → tb g (tb f xs) ≡ map (λ x → g (f x)) xs
  two-calls-law f g xs =
    trans (cong rev (map-rev g (map f xs)))
          (trans (rev-rev (map g (map f xs))) (map-∘ f g xs))

  -- a correct fusion: keep ONE reversal, fuse everything before it
  map-then-tb : {A B C : Set} (f : A → B) (g : B → C) (xs : List A)
              → tb g (map f xs) ≡ tb (λ x → g (f x)) xs
  map-then-tb f g xs = cong rev (map-∘ f g xs)

  three-calls-law : {A B C D : Set} (f : A → B) (g : B → C) (h : C → D) (xs : List A)
                  → tb h (tb g (tb f xs)) ≡ tb (λ x → h (g (f x))) xs
  three-calls-law f g h xs =
    trans (cong (tb h) (two-calls-law f g xs)) (map-then-tb (λ x → g (f x)) h xs)

------------------------------------------------------------------------
-- 7. backpressure
------------------------------------------------------------------------

module Backpressure where

  min-0ʳ : (n : ℕ) → min n 0 ≡ 0
  min-0ʳ zero    = refl
  min-0ʳ (suc n) = refl

  min-≤ : (n k : ℕ) → min n k ≤ k
  min-≤ zero    k       = z≤n
  min-≤ (suc n) zero    = z≤n
  min-≤ (suc n) (suc k) = s≤s (min-≤ n k)

  min-of-≤ : {a k : ℕ} → a ≤ k → min a k ≡ a
  min-of-≤ z≤n     = refl
  min-of-≤ (s≤s p) = cong suc (min-of-≤ p)

  -- capping early does not change a later capped sum (any cap k)
  absorb : (x c k : ℕ) → min (min x k + c) k ≡ min (x + c) k
  absorb zero    c k       = refl
  absorb (suc x) c zero    = trans (min-0ʳ c) (sym (min-0ʳ (suc x + c)))
  absorb (suc x) c (suc k) = cong suc (absorb x c k)

  absorbʳ : (a y k : ℕ) → min (a + min y k) k ≡ min (a + y) k
  absorbʳ a y k =
    trans (cong (λ n → min n k) (+-comm a (min y k)))
          (trans (absorb y a k) (cong (λ n → min n k) (+-comm y a)))

  cap-assoc : (k a b c : ℕ) → min (min (a + b) k + c) k ≡ min (a + min (b + c) k) k
  cap-assoc k a b c =
    trans (absorb (a + b) c k)
          (trans (cong (λ n → min n k) (+-assoc a b c)) (sym (absorbʳ a (b + c) k)))

  -- sum-then-cap equals cap-as-you-go: capping is a monoid homomorphism
  cap-hom : (k a b : ℕ) → min (a + b) k ≡ min (min a k + min b k) k
  cap-hom k a b = sym (trans (absorb a (min b k) k) (absorbʳ a b k))

  -- the carrier 0..10 as a type
  ≤-irr : {m n : ℕ} (p q : m ≤ n) → p ≡ q
  ≤-irr z≤n     z≤n     = refl
  ≤-irr (s≤s p) (s≤s q) = cong s≤s (≤-irr p q)

  record Score : Set where
    constructor score
    field
      val   : ℕ
      bound : val ≤ 10
  open Score

  score-≡ : (s t : Score) → val s ≡ val t → s ≡ t
  score-≡ (score v p) (score .v q) refl = cong (score v) (≤-irr p q)

  infixl 6 _⊕_
  _⊕_ : Score → Score → Score
  s ⊕ t = score (min (val s + val t) 10) (min-≤ (val s + val t) 10)

  none : Score
  none = score 0 z≤n

  ⊕-assoc : (a b c : Score) → (a ⊕ b) ⊕ c ≡ a ⊕ (b ⊕ c)
  ⊕-assoc a b c = score-≡ _ _ (cap-assoc 10 (val a) (val b) (val c))

  ⊕-idˡ : (a : Score) → none ⊕ a ≡ a
  ⊕-idˡ a = score-≡ _ _ (min-of-≤ (bound a))

  ⊕-idʳ : (a : Score) → a ⊕ none ≡ a
  ⊕-idʳ a = score-≡ _ _ (trans (cong (λ n → min n 10) (+-identityʳ (val a)))
                                (min-of-≤ (bound a)))

  ⊕-comm : (a b : Score) → a ⊕ b ≡ b ⊕ a
  ⊕-comm a b = score-≡ _ _ (cong (λ n → min n 10) (+-comm (val a) (val b)))

  -- NOT idempotent: a duplicated score is counted twice
  three : Score
  three = score 3 (s≤s (s≤s (s≤s z≤n)))

  duplicate-counts : val (three ⊕ three) ≡ 6
  duplicate-counts = refl

  open Fold _⊕_ none ⊕-assoc ⊕-idˡ ⊕-idʳ public
  open Commutative ⊕-comm public

------------------------------------------------------------------------
-- 8. quota
------------------------------------------------------------------------

module Quota where

  ∸-idʳ : (a : ℕ) → a ∸ 0 ≡ a
  ∸-idʳ a = refl

  0∸ : (a : ℕ) → 0 ∸ a ≡ 0
  0∸ zero    = refl
  0∸ (suc a) = refl

  -- 0 is NOT a left identity
  left-identity-fails : ¬ ((a : ℕ) → 0 ∸ a ≡ a)
  left-identity-fails h with h 1
  ... | ()

  -- NOT associative
  left-grouping : (1 ∸ 1) ∸ 1 ≡ 0
  left-grouping = refl

  right-grouping : 1 ∸ (1 ∸ 1) ≡ 1
  right-grouping = refl

  not-assoc : ¬ ((a b c : ℕ) → (a ∸ b) ∸ c ≡ a ∸ (b ∸ c))
  not-assoc h with h 1 1 1
  ... | ()

  -- the note's plan, quota 10, releases 4 then 3
  sequential-run : (10 ∸ 4) ∸ 3 ≡ 3
  sequential-run = refl

  grouped-run : 10 ∸ (4 ∸ 3) ≡ 9
  grouped-run = refl

  -- folding from the "neutral" 0 forgets everything
  foldl : ℕ → List ℕ → ℕ
  foldl acc []       = acc
  foldl acc (x ∷ xs) = foldl (acc ∸ x) xs

  from-zero : (xs : List ℕ) → foldl 0 xs ≡ 0
  from-zero []       = refl
  from-zero (x ∷ xs) = trans (cong (λ n → foldl n xs) (0∸ x)) (from-zero xs)

  -- what IS true: amounts act on the quota, and the action respects (ℕ, +, 0)
  action : (q a b : ℕ) → (q ∸ a) ∸ b ≡ q ∸ (a + b)
  action q       zero    b = refl
  action zero    (suc a) b = 0∸ b
  action (suc q) (suc a) b = action q a b

  -- the amounts themselves form a commutative monoid under +
  module Amounts where
    open Fold _+_ 0 +-assoc (λ a → refl) +-identityʳ public
    open Commutative +-comm public

  -- so: fold the amounts with + in any grouping, subtract once
  drain : (q : ℕ) (xs : List ℕ) → foldl q xs ≡ q ∸ Amounts.fold xs
  drain q []       = refl
  drain q (x ∷ xs) = trans (drain (q ∸ x) xs) (action q x (Amounts.fold xs))

------------------------------------------------------------------------
-- Repair material for 3 (drift): track (lowest, highest) instead
------------------------------------------------------------------------

module Spread where
  open Watermark using (max-assoc)

  min-assoc : (a b c : ℕ) → min (min a b) c ≡ min a (min b c)
  min-assoc zero    b       c       = refl
  min-assoc (suc a) zero    c       = refl
  min-assoc (suc a) (suc b) zero    = refl
  min-assoc (suc a) (suc b) (suc c) = cong suc (min-assoc a b c)

  -- min has no neutral element inside ℕ (the dual of watermark needs "+∞")
  min-no-unit : (e : ℕ) → ¬ (min e (suc e) ≡ suc e)
  min-no-unit zero    ()
  min-no-unit (suc e) p = min-no-unit e (cong pred p)

  -- generic: an associative operation plus an adjoined "nothing seen yet"
  module Adjoin {S : Set} (_∙_ : S → S → S)
                (∙-assoc : (a b c : S) → (a ∙ b) ∙ c ≡ a ∙ (b ∙ c)) where

    _⊙_ : Maybe S → Maybe S → Maybe S
    nothing ⊙ y       = y
    just a  ⊙ nothing = just a
    just a  ⊙ just b  = just (a ∙ b)

    ⊙-idˡ : (y : Maybe S) → nothing ⊙ y ≡ y
    ⊙-idˡ y = refl

    ⊙-idʳ : (x : Maybe S) → x ⊙ nothing ≡ x
    ⊙-idʳ nothing  = refl
    ⊙-idʳ (just a) = refl

    ⊙-assoc : (x y z : Maybe S) → (x ⊙ y) ⊙ z ≡ x ⊙ (y ⊙ z)
    ⊙-assoc nothing  y        z        = refl
    ⊙-assoc (just a) nothing  z        = refl
    ⊙-assoc (just a) (just b) nothing  = refl
    ⊙-assoc (just a) (just b) (just c) = cong just (∙-assoc a b c)

  Range : Set
  Range = ℕ × ℕ            -- (lowest reading, highest reading)

  hull : Range → Range → Range
  hull r s = min (fst r) (fst s) , max (snd r) (snd s)

  hull-assoc : (r s t : Range) → hull (hull r s) t ≡ hull r (hull s t)
  hull-assoc r s t =
    cong₂ _,_ (min-assoc (fst r) (fst s) (fst t)) (max-assoc (snd r) (snd s) (snd t))

  -- overlay (component 5) is exactly "adjoin a unit to `later wins`"
  module OverlayIsAdjoin {A : Set} where
    open Adjoin {A} (λ a b → b) (λ a b c → refl) renaming (_⊙_ to _⊙′_)
    open Overlay {A}

    same : (x y : Maybe A) → x ⊙′ y ≡ x ◁ y
    same nothing  nothing  = refl
    same nothing  (just b) = refl
    same (just a) nothing  = refl
    same (just a) (just b) = refl

  open Adjoin hull hull-assoc public
  open Fold _⊙_ nothing ⊙-assoc ⊙-idˡ ⊙-idʳ public

  reading : ℕ → Maybe Range
  reading n = just (n , n)

  spread : Maybe Range → ℕ
  spread nothing  = 0
  spread (just r) = snd r ∸ fst r

  -- readings 1,1,2 again: both groupings now give the same spread
  seq : spread ((reading 1 ⊙ reading 1) ⊙ reading 2) ≡ 1
  seq = refl

  shard : spread (reading 1 ⊙ (reading 1 ⊙ reading 2)) ≡ 1
  shard = refl
