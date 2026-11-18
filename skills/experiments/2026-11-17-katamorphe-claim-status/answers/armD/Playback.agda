{-# OPTIONS --safe --without-K #-}
-- Statement playback: the generic grouping/reordering theorems, re-stated at
-- each concrete component, so the instantiated types can be read directly.
module Playback where
open import Ledgerline

-- 2. watermark: any two groupings of the same marks agree; so does any reordering
wm-group : (t u : Watermark.Tree) → Watermark.flatten t ≡ Watermark.flatten u
         → Watermark.foldT t ≡ Watermark.foldT u
wm-group = Watermark.regroup

wm-seq : (t : Watermark.Tree) → Watermark.foldT t ≡ Watermark.foldl 0 (Watermark.flatten t)
wm-seq = Watermark.grouping-vs-sequential

wm-shards : (xss : List (List ℕ))
          → Watermark.fold (map Watermark.fold xss) ≡ Watermark.fold (concat xss)
wm-shards = Watermark.fold-shards

wm-order : {xs ys : List ℕ} → Watermark.Perm xs ys → Watermark.fold xs ≡ Watermark.fold ys
wm-order = Watermark.fold-perm

-- 5. overlay: any grouping, order kept
ov-group : {A : Set} (t u : Overlay.Tree {A}) → Overlay.flatten t ≡ Overlay.flatten u
         → Overlay.foldT t ≡ Overlay.foldT u
ov-group = Overlay.regroup

ov-seq : {A : Set} (t : Overlay.Tree {A})
       → Overlay.foldT t ≡ Overlay.foldl nothing (Overlay.flatten t)
ov-seq = Overlay.grouping-vs-sequential

-- 7. backpressure: any grouping, any order
bp-group : (t u : Backpressure.Tree) → Backpressure.flatten t ≡ Backpressure.flatten u
         → Backpressure.foldT t ≡ Backpressure.foldT u
bp-group = Backpressure.regroup

bp-seq : (t : Backpressure.Tree)
       → Backpressure.foldT t ≡ Backpressure.foldl Backpressure.none (Backpressure.flatten t)
bp-seq = Backpressure.grouping-vs-sequential

bp-order : {xs ys : List Backpressure.Score} → Backpressure.Perm xs ys
         → Backpressure.fold xs ≡ Backpressure.fold ys
bp-order = Backpressure.fold-perm

-- 8. quota, repaired: amounts fold under + in any grouping and order,
--    and the sequential drain equals one subtraction of the total
q-order : {xs ys : List ℕ} → Quota.Amounts.Perm xs ys
        → Quota.Amounts.fold xs ≡ Quota.Amounts.fold ys
q-order = Quota.Amounts.fold-perm

q-drain : (q : ℕ) (xs : List ℕ) → Quota.foldl q xs ≡ q ∸ Quota.Amounts.fold xs
q-drain = Quota.drain

-- 3. drift, repaired: (lowest, highest) ranges fold in any grouping
sp-group : (t u : Spread.Tree) → Spread.flatten t ≡ Spread.flatten u
         → Spread.foldT t ≡ Spread.foldT u
sp-group = Spread.regroup
