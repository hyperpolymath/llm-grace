module Laws where

-- Self-contained (no standard library).

data _≡_ {A : Set} (x : A) : A → Set where
  refl : x ≡ x
infix 4 _≡_

data ⊥ : Set where

cong : {A B : Set} (f : A → B) {x y : A} → x ≡ y → f x ≡ f y
cong f refl = refl

trans : {A : Set} {x y z : A} → x ≡ y → y ≡ z → x ≡ z
trans refl q = q

sym : {A : Set} {x y : A} → x ≡ y → y ≡ x
sym refl = refl

data ℕ : Set where
  zero : ℕ
  suc  : ℕ → ℕ
{-# BUILTIN NATURAL ℕ #-}

data Maybe (A : Set) : Set where
  absent  : Maybe A
  present : A → Maybe A

data List (A : Set) : Set where
  []  : List A
  _∷_ : A → List A → List A
infixr 5 _∷_

id : {A : Set} → A → A
id x = x

_∘_ : {A B C : Set} → (B → C) → (A → B) → A → C
(g ∘ f) x = g (f x)

------------------------------------------------------------------------
-- 1. enrich: the Maybe functor's action on arrows

enrich : {A B : Set} → (A → B) → Maybe A → Maybe B
enrich f absent      = absent
enrich f (present x) = present (f x)

enrich-id : {A : Set} (m : Maybe A) → enrich id m ≡ m
enrich-id absent      = refl
enrich-id (present x) = refl

enrich-∘ : {A B C : Set} (f : A → B) (g : B → C) (m : Maybe A)
         → enrich g (enrich f m) ≡ enrich (g ∘ f) m
enrich-∘ f g absent      = refl
enrich-∘ f g (present x) = refl

------------------------------------------------------------------------
-- 5. overlay: later layer wins if present; absent is neutral

overlay : {A : Set} → Maybe A → Maybe A → Maybe A   -- overlay earlier later
overlay e absent      = e
overlay e (present y) = present y

overlay-idˡ : {A : Set} (m : Maybe A) → overlay absent m ≡ m
overlay-idˡ absent      = refl
overlay-idˡ (present x) = refl

overlay-idʳ : {A : Set} (m : Maybe A) → overlay m absent ≡ m
overlay-idʳ m = refl

overlay-assoc : {A : Set} (a b c : Maybe A)
              → overlay (overlay a b) c ≡ overlay a (overlay b c)
overlay-assoc a b absent      = refl
overlay-assoc a b (present z) = refl

-- not commutative: order of layers must be kept
overlay-not-comm : overlay (present 1) (present 2) ≡ overlay (present 2) (present 1) → ⊥
overlay-not-comm ()

------------------------------------------------------------------------
-- 6. transformBatch: map, then reverse

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

-- identity law fails
tb-id-fails : transformBatch id (1 ∷ 2 ∷ []) ≡ (1 ∷ 2 ∷ []) → ⊥
tb-id-fails ()

-- the planned fusion fails
tb-fuse-lhs : transformBatch suc (transformBatch suc (1 ∷ 2 ∷ [])) ≡ 3 ∷ 4 ∷ []
tb-fuse-lhs = refl

tb-fuse-rhs : transformBatch (suc ∘ suc) (1 ∷ 2 ∷ []) ≡ 4 ∷ 3 ∷ []
tb-fuse-rhs = refl

tb-fusion-fails : transformBatch suc (transformBatch suc (1 ∷ 2 ∷ []))
                ≡ transformBatch (suc ∘ suc) (1 ∷ 2 ∷ []) → ⊥
tb-fusion-fails ()

-- what is true in general: map is a functor, reverse is a natural involution,
-- so two transformBatch calls equal ONE map and NO reversal.

map-∘ : {A B C : Set} (f : A → B) (g : B → C) (xs : List A)
      → map g (map f xs) ≡ map (g ∘ f) xs
map-∘ f g []       = refl
map-∘ f g (x ∷ xs) = cong (g x' ∷_) (map-∘ f g xs)
  where x' = f x

map-id : {A : Set} (xs : List A) → map id xs ≡ xs
map-id []       = refl
map-id (x ∷ xs) = cong (x ∷_) (map-id xs)

map-++ : {A B : Set} (f : A → B) (xs ys : List A)
       → map f (xs ++ ys) ≡ (map f xs ++ map f ys)
map-++ f []       ys = refl
map-++ f (x ∷ xs) ys = cong (f x ∷_) (map-++ f xs ys)

-- naturality of reverse
reverse-natural : {A B : Set} (f : A → B) (xs : List A)
                → map f (reverse xs) ≡ reverse (map f xs)
reverse-natural f []       = refl
reverse-natural f (x ∷ xs) =
  trans (map-++ f (reverse xs) (x ∷ []))
        (cong (_++ (f x ∷ [])) (reverse-natural f xs))

reverse-snoc : {A : Set} (xs : List A) (x : A)
             → reverse (xs ++ (x ∷ [])) ≡ x ∷ reverse xs
reverse-snoc []       x = refl
reverse-snoc (y ∷ ys) x = cong (_++ (y ∷ [])) (reverse-snoc ys x)

reverse-involutive : {A : Set} (xs : List A) → reverse (reverse xs) ≡ xs
reverse-involutive []       = refl
reverse-involutive (x ∷ xs) =
  trans (reverse-snoc (reverse xs) x) (cong (x ∷_) (reverse-involutive xs))

tb-two-calls : {A B C : Set} (f : A → B) (g : B → C) (xs : List A)
             → transformBatch g (transformBatch f xs) ≡ map (g ∘ f) xs
tb-two-calls f g xs =
  trans (cong reverse (reverse-natural g (map f xs)))
        (trans (reverse-involutive (map g (map f xs))) (map-∘ f g xs))

------------------------------------------------------------------------
-- 4. attempts: concrete failure of both unit laws, on closed terms

record _×_ (A B : Set) : Set where
  constructor _,_
  field
    fst : A
    snd : B
open _×_

_+_ : ℕ → ℕ → ℕ
zero  + n = n
suc m + n = suc (m + n)

pure : {A : Set} → A → A × ℕ
pure v = v , 1

_>>=_ : {A B : Set} → A × ℕ → (A → B × ℕ) → B × ℕ
(v , n) >>= f = fst (f v) , (n + snd (f v))

step : ℕ → ℕ × ℕ
step v = suc v , 1

left-identity-fails : (pure 5 >>= step) ≡ step 5 → ⊥
left-identity-fails ()

right-identity-fails : (step 5 >>= pure) ≡ step 5 → ⊥
right-identity-fails ()

+-assoc : (a b c : ℕ) → (a + b) + c ≡ a + (b + c)
+-assoc zero    b c = refl
+-assoc (suc a) b c = cong suc (+-assoc a b c)

bind-assoc : {A B C : Set} (m : A × ℕ) (f : A → B × ℕ) (g : B → C × ℕ)
           → ((m >>= f) >>= g) ≡ (m >>= (λ x → f x >>= g))
bind-assoc (v , n) f g =
  cong (fst (g (fst (f v))) ,_) (+-assoc n (snd (f v)) (snd (g (fst (f v)))))

------------------------------------------------------------------------
-- 6 (continued). reverse is an anti-homomorphism for concatenation, so
-- transformBatch on a split batch returns the pieces in swapped order.

++-[] : {A : Set} (xs : List A) → (xs ++ []) ≡ xs
++-[] []       = refl
++-[] (x ∷ xs) = cong (x ∷_) (++-[] xs)

++-assoc : {A : Set} (xs ys zs : List A) → ((xs ++ ys) ++ zs) ≡ (xs ++ (ys ++ zs))
++-assoc []       ys zs = refl
++-assoc (x ∷ xs) ys zs = cong (x ∷_) (++-assoc xs ys zs)

reverse-++ : {A : Set} (xs ys : List A)
           → reverse (xs ++ ys) ≡ (reverse ys ++ reverse xs)
reverse-++ []       ys = sym (++-[] (reverse ys))
reverse-++ (x ∷ xs) ys =
  trans (cong (_++ (x ∷ [])) (reverse-++ xs ys))
        (++-assoc (reverse ys) (reverse xs) (x ∷ []))

tb-++ : {A B : Set} (f : A → B) (xs ys : List A)
      → transformBatch f (xs ++ ys) ≡ (transformBatch f ys ++ transformBatch f xs)
tb-++ f xs ys = trans (cong reverse (map-++ f xs ys)) (reverse-++ (map f xs) (map f ys))
