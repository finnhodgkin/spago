module Spago.Prelude
  ( module Spago.Core.Prelude
  , HexString(..)
  , parseLenientVersion
  , parallelise
  , parseUrl
  , partitionEithers
  , shaToHex
  , unsafeFromRight
  , unsafeLog
  , unsafeStringify
  ) where

import Spago.Core.Prelude

import Control.Parallel as Parallel
import Data.Argonaut.Core as Argonaut
import Data.Array as Array
import Data.Either as Either
import Data.Function.Uncurried (Fn3, runFn3)
import Data.Int as Int
import Data.Maybe as Maybe
import Data.String as String
import Effect.Aff as Aff
import Node.Buffer as Buffer
import Partial.Unsafe (unsafeCrashWith)
import Registry.Sha256 as Registry.Sha256
import Registry.Version as Version

import Unsafe.Coerce (unsafeCoerce)

unsafeFromRight :: forall e a. Either e a -> a
unsafeFromRight v = Either.fromRight' (\_ -> unsafeCrashWith $ "Unexpected Left: " <> unsafeStringify v) v

parseUrl :: String -> Either String URL
parseUrl = runFn3 parseUrlImpl Left (Right <<< unsafeCoerce)

type URL = { href :: String }

foreign import parseUrlImpl :: forall r. Fn3 (String -> r) (String -> r) String r

foreign import unsafeLog :: forall a. a -> Effect Unit

parallelise :: forall env a. Array (Spago env a) -> Spago env Unit
parallelise actions = do
  env <- ask
  fibers <- liftAff $ Parallel.parSequence (map (Aff.forkAff <<< runSpago env) actions :: Array _)
  liftAff $ for_ fibers Aff.joinFiber

shaToHex :: Sha256 -> Effect HexString
shaToHex s = do
  (buffer :: Buffer.Buffer) <- Buffer.fromString (Registry.Sha256.print s) UTF8
  string <- Buffer.toString Hex buffer
  pure $ HexString string

newtype HexString = HexString String

-- | Partition an array of `Either` values into failure and success  values
partitionEithers :: forall e a. Array (Either.Either e a) -> { fail :: Array e, success :: Array a }
partitionEithers = Array.foldMap case _ of
  Either.Left err -> { fail: [ err ], success: [] }
  Either.Right res -> { fail: [], success: [ res ] }

-- | Unsafely stringify a value by coercing it to `Json` and stringifying it.
unsafeStringify :: forall a. a -> String
unsafeStringify a = Argonaut.stringify (unsafeCoerce a :: Argonaut.Json)

parseLenientVersion :: String -> Either String Version.Version
parseLenientVersion input = Version.parse do
  -- First we ensure there are no leading or trailing spaces.
  String.trim input
    -- Then we remove a 'v' prefix, if present.
    # maybeIdentity (String.stripPrefix (String.Pattern "v"))
    -- Then we group by where the version digits ought to be...
    # String.split (String.Pattern ".")
    -- ...so that we can trim any leading zeros
    # map (maybeIdentity dropLeadingZeros)
    -- and rejoin the string.
    # String.joinWith "."
  where
  maybeIdentity k x = Maybe.fromMaybe x (k x)
  dropLeadingZeros = map (Int.toStringAs Int.decimal) <<< Int.fromString
