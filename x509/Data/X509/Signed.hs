-- |
-- Module      : Data.X509.Signed
-- License     : BSD-style
-- Maintainer  : Vincent Hanquez <vincent@snarc.org>
-- Stability   : experimental
-- Portability : unknown
--
-- Exposes helpers for X509 certificate and revocation list, signed structures.
--
-- Signed structures are of the form:
--      Sequence {
--          object              a
--          signatureAlgorithm  AlgorithmIdentifier
--          signatureValue      BitString
--      }
--
-- Unfortunately as lots of signed objects published have been signed on an
-- arbitrary BER ASN1 encoding (instead of using the unique DER encoding) or in
-- a non-valid DER implementation, we need to keep the raw data being signed,
-- as we can't recompute the bytestring used to sign for non compliant cases.
--
-- Signed represent the pure data type for compliant cases, and SignedExact
-- the real world situation of having to deal with compliant and non-compliant cases.
--
module Data.X509.Signed
    (
    -- * Types
      Signed(..)
    , SignedExact
    -- * SignedExact to Signed
    , getSigned
    -- * Marshalling function
    , encodeSignedObject
    , decodeSignedObject
    -- * Object to Signed and SignedExact
    , objectToSignedExact
    , objectToSigned
    , signedToExact
    ) where

import Control.Arrow (first)
import Data.ByteString (ByteString)
import qualified Data.ByteString as B
import Data.X509.AlgorithmIdentifier
import Data.ASN1.Types
import Data.ASN1.Encoding
import Data.ASN1.BinaryEncoding
import Data.ASN1.Stream
import Data.ASN1.BitArray
import qualified Data.ASN1.BinaryEncoding.Raw as Raw (toByteString)

-- | Represent a signed object using a traditional X509 structure.
--
-- When dealing with external certificate, use the SignedExact structure
-- not this one.
data (Eq a, ASN1Object a) => Signed a = Signed
    { signedObject    :: a            -- ^ Object to sign
    , signedAlg       :: SignatureALG -- ^ Signature Algorithm used
    , signedSignature :: B.ByteString -- ^ Signature as bytes
    } deriving (Eq)

-- | Represent the signed object plus the raw data that we need to
-- keep around for non compliant case to be able to verify signature.
data (Eq a, ASN1Object a) => SignedExact a = SignedExact
    { getSigned          :: Signed a     -- ^ get the decoded Signed data
    , exactObjectRaw     :: B.ByteString -- ^ The raw representation of the object a
                                         -- TODO: in later version, replace with offset in exactRaw
    , encodeSignedObject :: B.ByteString -- ^ The raw representation of the whole signed structure
    }

-- | make a 'SignedExact' copy of a 'Signed' object
--
-- As the signature is already generated, expect the
-- encoded object to have been made on a compliant DER ASN1 implementation.
--
-- It's better to use 'objectToSignedExact' instead of this.
signedToExact :: Signed a -> SignedExact a
signedToExact signed = undefined

-- | Transform an object into a 'SignedExact' object
objectToSignedExact :: (Eq a, ASN1Object a)
                    => (ByteString -> (ByteString, SignatureALG, r)) -- ^ signature function
                    -> a                                             -- ^ object to encode
                    -> (SignedExact a, r)
objectToSignedExact signatureFunction object = undefined

-- | Transform an object into a 'Signed' object.
objectToSigned :: (Eq a, ASN1Object a) => (ByteString -> (ByteString, SignatureALG, r)) -> a -> (Signed a, r)
objectToSigned signatureFunction object = first getSigned $ objectToSignedExact signatureFunction object

-- | Try to parse a bytestring that use the typical X509 signed structure format
decodeSignedObject :: (Eq a, ASN1Object a) => ByteString -> Either String (SignedExact a)
decodeSignedObject b = either (Left . show) parseSigned $ decodeASN1Repr' BER b
  where -- the following implementation is very inefficient.
        -- uses reverse and containing, move to a better solution eventually
        parseSigned l = onContainer (fst $ getConstructedEndRepr l) $ \l2 ->
            let (objRepr,rem1)   = getConstructedEndRepr l2
                (sigAlgSeq,rem2) = getConstructedEndRepr rem1
                (sigSeq,_)       = getConstructedEndRepr rem2
                obj              = onContainer objRepr (either Left (Right . fst) . fromASN1 . map fst)
             in case (obj, map fst sigSeq) of
                    (Right o, [BitString signature]) ->
                        let rawObj = Raw.toByteString $ concatMap snd objRepr
                         in case fromASN1 $ map fst sigAlgSeq of
                                Left s           -> Left ("signed object error sigalg: " ++ s)
                                Right (sigAlg,_) ->
                                    let signed = Signed
                                                    { signedObject    = o
                                                    , signedAlg       = sigAlg
                                                    , signedSignature = bitArrayGetData signature
                                                    }
                                     in Right $ SignedExact
                                                { getSigned          = signed
                                                , exactObjectRaw     = rawObj
                                                , encodeSignedObject = b
                                                }
                    (Left err, _) -> Left $ ("signed object error: " ++ show err)
                    _             -> Left $ "signed object structure error"
        onContainer ((Start _, _) : l) f =
            case reverse l of
                ((End _, _) : l2) -> f $ reverse l2
                _                 -> f []
        onContainer _ f = f []