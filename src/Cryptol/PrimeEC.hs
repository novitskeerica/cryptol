-----------------------------------------------------------------------------
-- |
-- Module    : Cryptol.PrimeEC
-- Copyright : (c) Galois, Inc.
-- License   : BSD3
-- Maintainer: rdockins@galois.com
-- Stability : experimental
--
-----------------------------------------------------------------------------

{-# LANGUAGE BangPatterns #-}

module Cryptol.PrimeEC
  ( PrimeModulus(..)
  , AffinePoint(..)
  , ProjectivePoint(..)

  , ec_double
  , ec_add
  , ec_mult
  , ec_twin_mult
  ) where


import Data.Bits
import Data.Euclidean (gcdExt)
import Data.List (foldl')

import Cryptol.TypeCheck.Solver.InfNat (widthInteger)


newtype PrimeModulus = PrimeModulus { primeMod :: Integer }
 deriving (Show, Eq)

data AffinePoint =
  AffinePoint
  { ax :: !Integer
  , ay :: !Integer
  }
 deriving (Show, Eq)

data ProjectivePoint =
  ProjectivePoint
  { px :: !Integer
  , py :: !Integer
  , pz :: !Integer
  }
 deriving (Show, Eq)


mod_add :: PrimeModulus -> Integer -> Integer -> Integer
mod_add (PrimeModulus p) !x !y = if r >= p then r - p else r
  where r = x+y

mod_half :: PrimeModulus -> Integer -> Integer
mod_half (PrimeModulus p) x = if r == 0 then q else (x+p) `div` 2
  where
  (q,r) = divMod x 2

mod_mul :: PrimeModulus -> Integer -> Integer -> Integer
mod_mul (PrimeModulus p) !x !y = (x*y) `mod` p

mod_sub :: PrimeModulus -> Integer -> Integer -> Integer
mod_sub (PrimeModulus p) !x !y = mod_add (PrimeModulus p) x (p - y)

mod_square :: PrimeModulus -> Integer -> Integer
mod_square p x = mod_mul p x x

mul2 :: PrimeModulus -> Integer -> Integer
mul2 p x = mod_add p x x

mul3 :: PrimeModulus -> Integer -> Integer
mul3 (PrimeModulus p) x = if rmp >= p then rmp - p else if r >= p then rmp else r
  where
    r   = 3*x
    rmp = r - p

mul4 :: PrimeModulus -> Integer -> Integer
mul4 p x = mul2 p (mul2 p x)

mul8 :: PrimeModulus -> Integer -> Integer
mul8 p x = mul2 p (mul4 p x)

ec_double :: PrimeModulus -> ProjectivePoint -> ProjectivePoint
ec_double p (ProjectivePoint sx sy sz) =
     if sz == 0 then
       ProjectivePoint 1 1 0
     else
       ProjectivePoint r18 r23 r13

  where
  r7  = mod_square p sz                   {-  7: t4 <- (t3)^2  -}
  r8  = mod_sub    p sx r7                {-  8: t5 <- t1 - t4 -}
  r9  = mod_add    p sx r7                {-  9: t4 <- t1 + t4 -}
  r10 = mod_mul    p r9 r8                {- 10: t5 <- t4 * t5 -}
  r11 = mul3       p r10                  {- 11: t4 <- 3 * t5 -}
  r12 = mod_mul    p sz sy                {- 12: t3 <- t3 * t2 -}
  r13 = mul2       p r12                  {- 13: t3 <- 2 * t3 -}
  r14 = mod_square p sy                   {- 14: t2 <- (t2)^2 -}
  r15 = mod_mul    p sx r14               {- 15: t5 <- t1 * t2 -}
  r16 = mul4       p r15                  {- 16: t5 <- 4 * t5 -}
  r17 = mod_square p r11                  {- 17: t1 <- (t4)^2 -}
  r18 = mod_sub    p r17 (mul2 p r16)     {- 18: t1 <- t1 - 2 * t5 -}
  r19 = mod_square p r14                  {- 19: t2 <- (t2)^2 -}
  r20 = mul8       p r19                  {- 20: t2 <- 8 * t2 -}
  r21 = mod_sub    p r16 r18              {- 21: t5 <- t5 - t1 -}
  r22 = mod_mul    p r11 r21              {- 22: t5 <- t4 * t5 -}
  r23 = mod_sub    p r22 r20              {- 23: t2 <- t5 - t2 -}

ec_full_add :: PrimeModulus -> ProjectivePoint -> ProjectivePoint -> ProjectivePoint
ec_full_add p s t
  | pz s == 0 = t
  | pz t == 0 = s
  | r == ProjectivePoint 0 0 0 = ec_double p s
  | otherwise = r

 where r = ec_add p s t

ec_full_sub :: PrimeModulus -> ProjectivePoint -> ProjectivePoint -> ProjectivePoint
ec_full_sub p s t = ec_full_add p s u
  where u = t{ py = negate (py t) }


ec_add :: PrimeModulus -> ProjectivePoint -> ProjectivePoint -> ProjectivePoint
ec_add p (ProjectivePoint sx sy sz) (ProjectivePoint tx ty tz) =
    if r13 == 0 then
      if r14 == 0 then
        ProjectivePoint 0 0 0
      else
        ProjectivePoint 1 1 0
    else
      ProjectivePoint r32 r37 r27

  where
  tz2 = mod_square p tz
  tz3 = mod_mul p tz tz2

  r5  = if tz == 1 then sx else mod_mul p sx tz2
  r7  = if tz == 1 then sy else mod_mul p sy tz3

  r9  = mod_square p sz                  {-  9: t7 <- (t3)^2 -}
  r10 = mod_mul    p tx r9               {- 10: t4 <- t4 * t7 -}
  r11 = mod_mul    p sz r9               {- 11: t7 <- t3 * t7 -}
  r12 = mod_mul    p ty r11              {- 12: t5 <- t5 * t7 -}
  r13 = mod_sub    p r5 r10              {- 13: t4 <- t1 - t4 -}
  r14 = mod_sub    p r7 r12              {- 14: t5 <- t2 - t5 -}

  r22 = mod_sub    p (mul2 p r5) r13     {- 22: t1 <- 2*t1 - t4 -}
  r23 = mod_sub    p (mul2 p r7) r14     {- 23: t2 <- 2*t2 - t5 -}

  r25 = if tz == 1 then sz else mod_mul p sz tz

  r27 = mod_mul    p r25 r13             {- 27: t3 <- t3 * t4 -}
  r28 = mod_square p r13                 {- 28: t7 <- (t4)^2 -}
  r29 = mod_mul    p r13 r28             {- 29: t4 <- t4 * t7 -}
  r30 = mod_mul    p r22 r28             {- 30: t7 <- t1 * t7 -}
  r31 = mod_square p r14                 {- 31: t1 <- (t5)^2 -}
  r32 = mod_sub    p r31 r30             {- 32: t1 <- t1 - t7 -}
  r33 = mod_sub    p r30 (mul2 p r32)    {- 33: t7 <- t7 - 2*t1 -}
  r34 = mod_mul    p r14 r33             {- 34: t5 <- t5 * t7 -}
  r35 = mod_mul    p r23 r29             {- 35: t4 <- t2 * t4 -}
  r36 = mod_sub    p r34 r35             {- 36: t2 <- t5 - t4 -}
  r37 = mod_half   p r36                 {- 37: t2 <- t2/2 -}


ec_normalize :: PrimeModulus -> ProjectivePoint -> ProjectivePoint
ec_normalize (PrimeModulus p) s@(ProjectivePoint x y z)
  | z == 1 = s
  | otherwise = ProjectivePoint (x*l2) (y*l3) 1
 where
  (_g,w) = gcdExt z p
  l = w `mod` p
  l2 = l*l
  l3 = l*l2

ec_mult :: PrimeModulus -> Integer -> ProjectivePoint -> ProjectivePoint
ec_mult p d s
  | d == 0    = zro
  | d == 1    = s
  | pz s == 0 = zro
  | otherwise = foldl' step zro (reverse [ 1 .. highbit ])

 where
   zro = ProjectivePoint 1 1 0
   s' = ec_normalize p s
   h  = 3*d

   highbit
     | w <= toInteger (maxBound :: Int) = fromInteger w
     | otherwise = error "ec_mult: Integer width too large"
    where w = widthInteger h

   step r i
     | testBit h i && not (testBit d i) = ec_full_add p r2 s'
     | not (testBit h i) && testBit d i = ec_full_sub p r2 s'
     | otherwise = r2
    where
      r2 = ec_double p r

ec_twin_mult :: PrimeModulus ->
  Integer -> ProjectivePoint ->
  Integer -> ProjectivePoint ->
  ProjectivePoint
ec_twin_mult p d0 s d1 t = ec_full_add p (ec_mult p d0 s) (ec_mult p d1 t) -- TODO fix this
{-

  go m init_c0 init_c1 zro

 where
  zro = ProjectivePoint 1 1 0

  s' = ec_normalize p s
  t' = ec_normalize p t

  spt  = ec_full_add p s' t'
  spt' = ec_normalize p spt

  smt  = ec_full_sub p s' t'
  smt' = ec_normalize p smt

  m0 = widthInteger d0 + 1
  m1 = widthInteger d1 + 1
  m | max m0 m1 <= toInteger (maxBound :: Int) = fromInteger (max m0 m1)
    | otherwise = error "ec_twin_mult: Integer width too large"

  init_c0 = C False False (tst d0 (m-1)) (tst d0 (m-2)) (tst d0 (m-3)) (tst d0 (m-4))
  init_c1 = C False False (tst d1 (m-1)) (tst d1 (m-2)) (tst d1 (m-3)) (tst d1 (m-4))

  tst x i
    | i >= 0    = testBit x i
    | otherwise = False

  f i
    | 18 <= i && i < 22 = 9
    | 14 <= i && i < 18 = 10
    | 22 <= i && i < 24 = 11
    |  4 <= i && i < 12 = 14
    | otherwise         = 12

  go 0  _  _ r = r
  go k c0 c1 r = go (k-1) c0' c1' r'
    where
      h0  = cStateToH c0
      h1  = cStateToH c1
      u0  = if h0 < f h1 then 0 else (if cHead c0 then -1 else 1)
      u1  = if h1 < f h0 then 0 else (if cHead c1 then -1 else 1)
      c0' = cStateUpdate u0 c0 (tst d0 (k-5))
      c1' = cStateUpdate u1 c1 (tst d1 (k-5))

      r2 = ec_double p r

      r' | u0 == -1 && u1 == -1 = ec_full_sub p r2 spt'
         | u0 == -1 && u1 ==  0 = ec_full_sub p r2 s'
         | u0 == -1 && u1 ==  1 = ec_full_sub p r2 smt'
         | u0 ==  0 && u1 == -1 = ec_full_sub p r2 t'
         | u0 ==  0 && u1 ==  1 = ec_full_add p r2 t'
         | u0 ==  1 && u1 == -1 = ec_full_add p r2 smt'
         | u0 ==  1 && u1 ==  0 = ec_full_add p r2 s'
         | u0 ==  1 && u1 ==  1 = ec_full_add p r2 spt'
         | otherwise = r2

data CState = C !Bool !Bool !Bool !Bool !Bool !Bool

cHead :: CState -> Bool
cHead (C c0 _ _ _ _ _) = c0

cStateToH :: CState -> Int
cStateToH c@(C c0 _ _ _ _ _) =
  if c0 then 31 - cStateToInt c else cStateToInt c

cStateToInt :: CState -> Int
cStateToInt (C _ c1 c2 c3 c4 c5) =
  if c1 then 16 else 0 +
  if c2 then  8 else 0 +
  if c3 then  4 else 0 +
  if c4 then  2 else 0 +
  if c5 then  1 else 0

cStateUpdate :: Int -> CState -> Bool -> CState
cStateUpdate u (C _ c1 c2 c3 c4 c5) e =
  C ((u/=0) `xor` c1) c2 c3 c4 c5 e
-}