{-# OPTIONS --safe --without-K #-}
-- Machine-checked claims for the Ledgerline design-note review.
-- Only Agda's built-in modules are used (no standard library).
module Ledger where

open import Agda.Builtin.Nat
open import Agda.Builtin.Equality
open import Agda.Builtin.List

------------------------------------------------------------------------
-- Small prelude

data ⊥ : Set where

¬_ : Set → Set
¬ A = A → ⊥

sym : {A : Set} {x y : A} → x ≡ y → y ≡ x
sym refl = refl

trans : {A : Set} {x y z : A} → x ≡ y → y ≡ z → x ≡ z
trans refl q = q

cong : {A B : Set} (f : A → B) {x y : A} → x ≡ y → f x ≡ f y
cong f refl = refl

id : {A : Set} → A → A
id x = x

_∘_ : {A B C : Set} → (B → C) → (A → B) → A → C
(g ∘ f) x = g (f x)

data Maybe (A : Set) : Set where
  nothing : Maybe A
  just    : A → Maybe A

record _×_ (A B : Set) : Set where
  constructor _,_
  field
    fst : A
    snd : B
open _×_

+-idr : (n : Nat) → n + 0 ≡ n
+-idr zero    = refl
+-idr (suc n) = cong suc (+-idr n)

+-suc : (m n : Nat) → m + suc n ≡ suc (m + n)
+-suc zero    n = refl
+-suc (suc m) n = cong suc (+-suc m n)

+-assoc : (a b c : Nat) → (a + b) + c ≡ a + (b + c)
+-assoc zero    b c = refl
+-assoc (suc a) b c = cong suc (+-assoc a b c)

suc-inj : {m n : Nat} → suc m ≡ suc n → m ≡ n
suc-inj refl = refl

suc≢ : (n : Nat) → ¬ (suc n ≡ n)
suc≢ zero    ()
suc≢ (suc n) p = suc≢ n (suc-inj p)

------------------------------------------------------------------------
-- 1. enrich : the Maybe functor.  Both functor laws hold.

enrich : {A B : Set} → (A → B) → Maybe A → Maybe B
enrich f nothing  = nothing
enrich f (just x) = just (f x)

enrich-id : {A : Set} (m : Maybe A) → enrich id m ≡ m
enrich-id nothing  = refl
enrich-id (just x) = refl

enrich-∘ : {A B C : Set} (f : A → B) (g : B → C) (m : Maybe A)
         → enrich g (enrich f m) ≡ enrich (g ∘ f) m
enrich-∘ f g nothing  = refl
enrich-∘ f g (just x) = refl

------------------------------------------------------------------------
-- 2. watermark : (Nat, max, 0) is a monoid (also commutative, idempotent).

max : Nat → Nat → Nat
max zero    n       = n
max (suc m) zero    = suc m
max (suc m) (suc n) = suc (max m n)

max-idl : (n : Nat) → max 0 n ≡ n
max-idl n = refl

max-idr : (n : Nat) → max n 0 ≡ n
max-idr zero    = refl
max-idr (suc n) = refl

max-assoc : (a b c : Nat) → max (max a b) c ≡ max a (max b c)
max-assoc zero    b       c       = refl
max-assoc (suc a) zero    c       = refl
max-assoc (suc a) (suc b) zero    = refl
max-assoc (suc a) (suc b) (suc c) = cong suc (max-assoc a b c)

max-comm : (a b : Nat) → max a b ≡ max b a
max-comm zero    zero    = refl
max-comm zero    (suc b) = refl
max-comm (suc a) zero    = refl
max-comm (suc a) (suc b) = cong suc (max-comm a b)

------------------------------------------------------------------------
-- 3. drift : |a - b| with 0.  Unit laws and commutativity hold,
--    associativity FAILS, so it is not a monoid.

dist : Nat → Nat → Nat
dist zero    n       = n
dist (suc m) zero    = suc m
dist (suc m) (suc n) = dist m n

dist-idl : (n : Nat) → dist 0 n ≡ n
dist-idl n = refl

dist-idr : (n : Nat) → dist n 0 ≡ n
dist-idr zero    = refl
dist-idr (suc n) = refl

dist-comm : (a b : Nat) → dist a b ≡ dist b a
dist-comm zero    zero    = refl
dist-comm zero    (suc b) = refl
dist-comm (suc a) zero    = refl
dist-comm (suc a) (suc b) = dist-comm a b

-- (|1-2|) vs 3 gives 2, but 1 vs (|2-3|) gives 0.
drift-left  : dist (dist 1 2) 3 ≡ 2
drift-left  = refl
drift-right : dist 1 (dist 2 3) ≡ 0
drift-right = refl

2≢0 : ¬ (2 ≡ 0)
2≢0 ()

drift-not-assoc : ¬ ((a b c : Nat) → dist (dist a b) c ≡ dist a (dist b c))
drift-not-assoc h = 2≢0 (h 1 2 3)

------------------------------------------------------------------------
-- 4. attempts : (value, attempts) with pure v = (v , 1).
--    Bind is associative, but BOTH unit laws fail -- on every input.

Att : Set → Set
Att A = A × Nat

pure₁ : {A : Set} → A → Att A
pure₁ v = v , 1

bind : {A B : Set} → Att A → (A → Att B) → Att B
bind m f = fst (f (fst m)) , (snd m + snd (f (fst m)))

bind-assoc : {A B C : Set} (m : Att A) (f : A → Att B) (g : B → Att C)
           → bind (bind m f) g ≡ bind m (λ x → bind (f x) g)
bind-assoc m f g =
  cong (λ k → fst (g (fst (f (fst m)))) , k)
       (+-assoc (snd m) (snd (f (fst m))) (snd (g (fst (f (fst m))))))

-- Left identity fails for every v and every f: the count is one too high.
left-id-fails : {A B : Set} (v : A) (f : A → Att B) → ¬ (bind (pure₁ v) f ≡ f v)
left-id-fails v f p = suc≢ (snd (f v)) (cong snd p)

-- Right identity fails for every m.
right-id-fails : {A : Set} (m : Att A) → ¬ (bind m pure₁ ≡ m)
right-id-fails m p =
  suc≢ (snd m) (trans (sym (trans (+-suc (snd m) 0) (cong suc (+-idr (snd m))))) (cong snd p))

-- Concrete instance of the planned rewrite  pure(v) >>= f  ~>  f(v).
step : Nat → Att Nat
step v = v , 3

rewrite-before : bind (pure₁ 7) step ≡ (7 , 4)
rewrite-before = refl
rewrite-after  : step 7 ≡ (7 , 3)
rewrite-after  = refl

-- The repair: pure v = (v , 0) is the Writer monad over (Nat, +, 0).
pure₀ : {A : Set} → A → Att A
pure₀ v = v , 0

fixed-left-id : {A B : Set} (v : A) (f : A → Att B) → bind (pure₀ v) f ≡ f v
fixed-left-id v f = refl

fixed-right-id : {A : Set} (m : Att A) → bind m pure₀ ≡ m
fixed-right-id m = cong (λ k → fst m , k) (+-idr (snd m))

-- The plain "map the value, keep the count" is still a lawful functor.
amap : {A B : Set} → (A → B) → Att A → Att B
amap f m = f (fst m) , snd m

amap-id : {A : Set} (m : Att A) → amap id m ≡ m
amap-id m = refl

amap-∘ : {A B C : Set} (f : A → B) (g : B → C) (m : Att A)
       → amap g (amap f m) ≡ amap (g ∘ f) m
amap-∘ f g m = refl

------------------------------------------------------------------------
-- 5. overlay : "later layer wins if present".  A monoid (the Last monoid),
--    not commutative.

overlay : {A : Set} → Maybe A → Maybe A → Maybe A      -- earlier, later
overlay e nothing  = e
overlay e (just x) = just x

overlay-idl : {A : Set} (l : Maybe A) → overlay nothing l ≡ l
overlay-idl nothing  = refl
overlay-idl (just x) = refl

overlay-idr : {A : Set} (e : Maybe A) → overlay e nothing ≡ e
overlay-idr e = refl

overlay-assoc : {A : Set} (a b c : Maybe A)
              → overlay (overlay a b) c ≡ overlay a (overlay b c)
overlay-assoc a b nothing  = refl
overlay-assoc a b (just x) = refl

just-inj : {A : Set} {x y : A} → just x ≡ just y → x ≡ y
just-inj refl = refl

2≢1 : ¬ (2 ≡ 1)
2≢1 ()

overlay-not-comm : ¬ ((a b : Maybe Nat) → overlay a b ≡ overlay b a)
overlay-not-comm h = 2≢1 (just-inj (h (just 1) (just 2)))

------------------------------------------------------------------------
-- 6. transformBatch : map then reverse.  NOT a functor: both laws fail.

map : {A B : Set} → (A → B) → List A → List B
map f []       = []
map f (x ∷ xs) = f x ∷ map f xs

_++_ : {A : Set} → List A → List A → List A
[]       ++ ys = ys
(x ∷ xs) ++ ys = x ∷ (xs ++ ys)

reverse : {A : Set} → List A → List A
reverse []       = []
reverse (x ∷ xs) = reverse xs ++ (x ∷ [])

transformBatch : {A B : Set} → (A → B) → List A → List B
transformBatch f xs = reverse (map f xs)

-- Identity law fails.
tb-id-lhs : transformBatch id (1 ∷ 2 ∷ 3 ∷ []) ≡ (3 ∷ 2 ∷ 1 ∷ [])
tb-id-lhs = refl

-- Composition law fails: two stages restore the order, the fused stage reverses it.
suc' : Nat → Nat
suc' = suc

tb-two-stages : transformBatch suc' (transformBatch suc' (1 ∷ 2 ∷ 3 ∷ [])) ≡ (3 ∷ 4 ∷ 5 ∷ [])
tb-two-stages = refl
tb-fused      : transformBatch (suc' ∘ suc') (1 ∷ 2 ∷ 3 ∷ []) ≡ (5 ∷ 4 ∷ 3 ∷ [])
tb-fused      = refl

∷-inj-head : {A : Set} {x y : A} {xs ys : List A} → (x ∷ xs) ≡ (y ∷ ys) → x ≡ y
∷-inj-head refl = refl

3≢5 : ¬ (3 ≡ 5)
3≢5 ()

tb-fusion-unsound :
  ¬ ((f g : Nat → Nat) (xs : List Nat)
     → transformBatch g (transformBatch f xs) ≡ transformBatch (g ∘ f) xs)
tb-fusion-unsound h = 3≢5 (∷-inj-head (h suc' suc' (1 ∷ 2 ∷ 3 ∷ [])))

-- What IS true: two transformBatch stages equal ONE plain map (no reversal).
++-[] : {A : Set} (xs : List A) → xs ++ [] ≡ xs
++-[] []       = refl
++-[] (x ∷ xs) = cong (x ∷_) (++-[] xs)

++-assoc : {A : Set} (xs ys zs : List A) → (xs ++ ys) ++ zs ≡ xs ++ (ys ++ zs)
++-assoc []       ys zs = refl
++-assoc (x ∷ xs) ys zs = cong (x ∷_) (++-assoc xs ys zs)

reverse-++ : {A : Set} (xs ys : List A) → reverse (xs ++ ys) ≡ reverse ys ++ reverse xs
reverse-++ []       ys = sym (++-[] (reverse ys))
reverse-++ (x ∷ xs) ys =
  trans (cong (_++ (x ∷ [])) (reverse-++ xs ys))
        (++-assoc (reverse ys) (reverse xs) (x ∷ []))

reverse-reverse : {A : Set} (xs : List A) → reverse (reverse xs) ≡ xs
reverse-reverse []       = refl
reverse-reverse (x ∷ xs) =
  trans (reverse-++ (reverse xs) (x ∷ [])) (cong (x ∷_) (reverse-reverse xs))

map-++ : {A B : Set} (f : A → B) (xs ys : List A) → map f (xs ++ ys) ≡ map f xs ++ map f ys
map-++ f []       ys = refl
map-++ f (x ∷ xs) ys = cong (f x ∷_) (map-++ f xs ys)

map-reverse : {A B : Set} (f : A → B) (xs : List A) → map f (reverse xs) ≡ reverse (map f xs)
map-reverse f []       = refl
map-reverse f (x ∷ xs) =
  trans (map-++ f (reverse xs) (x ∷ [])) (cong (_++ (f x ∷ [])) (map-reverse f xs))

-- The list functor (plain map) is lawful.
map-id : {A : Set} (xs : List A) → map id xs ≡ xs
map-id []       = refl
map-id (x ∷ xs) = cong (x ∷_) (map-id xs)

map-∘ : {A B C : Set} (f : A → B) (g : B → C) (xs : List A)
      → map g (map f xs) ≡ map (g ∘ f) xs
map-∘ f g []       = refl
map-∘ f g (x ∷ xs) = cong (g (f x) ∷_) (map-∘ f g xs)

tb-two-is-plain-map : {A B C : Set} (f : A → B) (g : B → C) (xs : List A)
                    → transformBatch g (transformBatch f xs) ≡ map (g ∘ f) xs
tb-two-is-plain-map f g xs =
  trans (cong reverse (map-reverse g (map f xs)))
        (trans (reverse-reverse (map g (map f xs))) (map-∘ f g xs))

-- Correct factoring: transformBatch f = reverse after the lawful map.
tb-factor : {A B : Set} (f : A → B) (xs : List A)
          → transformBatch f xs ≡ map f (reverse xs)
tb-factor f xs = sym (map-reverse f xs)

------------------------------------------------------------------------
-- 8. quota : truncated subtraction (builtin _-_ on Nat is monus) with 0.
--    Right unit holds; left unit and associativity FAIL.

monus-idr : (n : Nat) → n - 0 ≡ n
monus-idr n = refl

1≢0 : ¬ (1 ≡ 0)
1≢0 ()

monus-no-left-unit : ¬ ((n : Nat) → 0 - n ≡ n)
monus-no-left-unit h = 1≢0 (sym (h 1))

quota-left  : (5 - 3) - 2 ≡ 0
quota-left  = refl
quota-right : 5 - (3 - 2) ≡ 4
quota-right = refl

0≢4 : ¬ (0 ≡ 4)
0≢4 ()

monus-not-assoc : ¬ ((a b c : Nat) → (a - b) - c ≡ a - (b - c))
monus-not-assoc h = 0≢4 (h 5 3 2)

-- What IS true: quota is acted on (from the right) by the monoid (Nat, +, 0)
-- of amounts.  Sum the amounts in any grouping, subtract once.
0-monus : (n : Nat) → 0 - n ≡ 0
0-monus zero    = refl
0-monus (suc n) = refl

monus-action : (q a b : Nat) → (q - a) - b ≡ q - (a + b)
monus-action q       zero    b = refl
monus-action zero    (suc a) b = 0-monus b
monus-action (suc q) (suc a) b = monus-action q a b
