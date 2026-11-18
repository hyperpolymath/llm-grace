module GroundTruth where

infix  4 _≡_
infix  3 ¬_
infixl 6 _+_ _∸_
infixr 5 _<>_ _++_
infixr 9 _∘_
infixr 2 _×_
infixr 4 _,_

data _≡_ {A : Set} (x : A) : A → Set where
  refl : x ≡ x

data ⊥ : Set where

¬_ : Set → Set
¬ A = A → ⊥

cong : {A B : Set} (f : A → B) {x y : A} → x ≡ y → f x ≡ f y
cong f refl = refl

data ℕ : Set where
  zero : ℕ
  suc  : ℕ → ℕ
{-# BUILTIN NATURAL ℕ #-}

_+_ : ℕ → ℕ → ℕ
zero  + n = n
suc m + n = suc (m + n)

data Maybe (A : Set) : Set where
  nothing : Maybe A
  just    : A → Maybe A

data List (A : Set) : Set where
  []  : List A
  _∷_ : A → List A → List A
infixr 5 _∷_

data _×_ (A B : Set) : Set where
  _,_ : A → B → A × B

fst : {A B : Set} → A × B → A
fst (a , _) = a
snd : {A B : Set} → A × B → B
snd (_ , b) = b

id : {A : Set} → A → A
id x = x

_∘_ : {A B C : Set} → (B → C) → (A → B) → A → C
(g ∘ f) x = g (f x)

-- 1. enrich: optional-field map. TRUE: functor laws hold.
enrich : {A B : Set} → (A → B) → Maybe A → Maybe B
enrich f nothing  = nothing
enrich f (just x) = just (f x)

enrich-id : {A : Set} (m : Maybe A) → enrich id m ≡ m
enrich-id nothing  = refl
enrich-id (just x) = refl

enrich-fusion : {A B C : Set} (g : B → C) (f : A → B) (m : Maybe A)
              → enrich (g ∘ f) m ≡ enrich g (enrich f m)
enrich-fusion g f nothing  = refl
enrich-fusion g f (just x) = refl

-- 2. watermark: max with 0. TRUE: monoid.
max : ℕ → ℕ → ℕ
max zero    n       = n
max (suc m) zero    = suc m
max (suc m) (suc n) = suc (max m n)

max-idr : (n : ℕ) → max n zero ≡ n
max-idr zero    = refl
max-idr (suc n) = refl

max-idl : (n : ℕ) → max zero n ≡ n
max-idl n = refl

max-assoc : (a b c : ℕ) → max (max a b) c ≡ max a (max b c)
max-assoc zero    b       c       = refl
max-assoc (suc a) zero    c       = refl
max-assoc (suc a) (suc b) zero    = refl
max-assoc (suc a) (suc b) (suc c) = cong suc (max-assoc a b c)

-- 3. drift: absolute difference with 0. FALSE: not associative.
dist : ℕ → ℕ → ℕ
dist zero    n       = n
dist (suc m) zero    = suc m
dist (suc m) (suc n) = dist m n

dist-not-assoc : ¬ ((a b c : ℕ) → dist (dist a b) c ≡ dist a (dist b c))
dist-not-assoc h with h 1 2 3
... | ()

-- 4. attempts: pure v = (v , 1), chaining adds attempts. FALSE: left identity fails.
pure : {A : Set} → A → A × ℕ
pure a = a , 1

bind : {A B : Set} → A × ℕ → (A → B × ℕ) → B × ℕ
bind (a , n) f = fst (f a) , (n + snd (f a))

attempts-no-left-identity : ¬ ((a : ℕ) (f : ℕ → ℕ × ℕ) → bind (pure a) f ≡ f a)
attempts-no-left-identity h with h 0 (λ x → x , 0)
... | ()

-- 5. overlay: later present setting wins, absent is neutral. TRUE: monoid.
_<>_ : {A : Set} → Maybe A → Maybe A → Maybe A
a <> nothing = a
a <> just y  = just y

overlay-idl : {A : Set} (a : Maybe A) → nothing <> a ≡ a
overlay-idl nothing  = refl
overlay-idl (just x) = refl

overlay-idr : {A : Set} (a : Maybe A) → a <> nothing ≡ a
overlay-idr a = refl

overlay-assoc : {A : Set} (a b c : Maybe A) → (a <> b) <> c ≡ a <> (b <> c)
overlay-assoc a b nothing  = refl
overlay-assoc a b (just z) = refl

-- 6. transformBatch: map then reverse. FALSE: identity law fails, so fusion is invalid.
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

transformBatch-no-identity : ¬ ((xs : List ℕ) → transformBatch id xs ≡ xs)
transformBatch-no-identity h with h (0 ∷ 1 ∷ [])
... | ()

transformBatch-no-fusion : ¬ ((xs : List ℕ) → transformBatch (id ∘ id) xs ≡ transformBatch id (transformBatch id xs))
transformBatch-no-fusion h with h (0 ∷ 1 ∷ [])
... | ()

-- 8. quota: truncated subtraction with 0. FALSE: no left identity.
_∸_ : ℕ → ℕ → ℕ
m     ∸ zero  = m
zero  ∸ suc n = zero
suc m ∸ suc n = m ∸ n

quota-no-left-identity : ¬ ((n : ℕ) → (0 ∸ n) ≡ n)
quota-no-left-identity h with h 1
... | ()
