{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE RecordWildCards    #-}

module Types.ReaderD where

import           Control.Exception
import qualified Data.Aeson           as A
import           Data.ByteString      (ByteString)
import           Data.Int             (Int64)
import           Data.Maybe           (fromJust)
import           Data.ProtocolBuffers hiding (field)
import qualified Data.Scientific      as S
import           Data.Text            (Text)
import           Data.Typeable
import           Data.TypeLevel       (D1, D2, D3, D4, D5, D6, D7, D8)
import qualified Data.Vector          as V
import           Data.Word            (Word64)
import           GHC.Generics         (Generic)
import           Pipes.Concurrent

-- A request to the reader daemon thread to retrieve a stream of chunks from
-- given range. The chunks are ordered in so far as the earliest point in a
-- later chunk is no earlier than the latest point in the preceding chunk.
data RangeQuery = RangeQuery
    { rangeSource :: [SourceTag]
    , rangeStart  :: Word64
    , rangeEnd    :: Word64
    , rangeOutput :: Output (Either SomeException Range) }

data Range = Burst DataBurst | Done

-- Custom exceptions

data ReaderDException = BurstDecodeFailure String
                      | RetriesExceeded
    deriving (Show, Typeable)
instance Exception ReaderDException

-- Protobufs follow

data SourceTag = SourceTag
    { field :: Required D1 (Value Text)
    , value :: Required D2 (Value Text)
    } deriving (Generic, Eq, Show)
instance Encode SourceTag
instance Decode SourceTag

data DataFrame = DataFrame {
    origin           :: Optional D8 (Value Text),
    source           :: Repeated D1 (Message SourceTag),
    timestamp        :: Required D2 (Value (Fixed Word64)),
    payload          :: Required D3 (Enumeration ValueType),
    valueNumeric     :: Optional D4 (Value Int64),
    valueMeasurement :: Optional D5 (Value Double),
    valueTextual     :: Optional D6 (Value Text),
    valueBlob        :: Optional D7 (Value ByteString)
} deriving (Generic, Eq, Show)
instance Decode DataFrame
instance A.ToJSON DataFrame where
    toJSON DataFrame{..}
        | getField payload == NUMBER = A.Array $ V.fromList
            [ getEpoch
            , A.Number $ S.scientific (fromIntegral $ fromJust $ getField valueNumeric)  1]
        | getField payload == REAL = A.Array $ V.fromList
            [ getEpoch
            , A.Number $ S.fromFloatDigits $ fromJust $ getField valueMeasurement]
        | otherwise = error "Unrepresentable DataFrame type"
      where
        getEpoch =
            let epoch = (fromIntegral $ getField timestamp) `div` 1000000000
            in  A.Number $ S.scientific epoch 1

data DataBurst = DataBurst {
    frames :: Repeated D1 (Message DataFrame)
} deriving (Generic, Eq, Show)
instance Decode DataBurst

data ValueType = EMPTY
                 | NUMBER
                 | REAL
                 | TEXT
                 | BINARY
  deriving (Enum, Generic, Show, Eq)

instance Decode ValueType

data RequestMulti = RequestMulti {
    multiRequestsField :: Repeated D1 (Message RequestSource)
} deriving (Generic, Eq, Show)

instance Encode RequestMulti

data RequestSource = RequestSource {
    requestSourceField :: Repeated D1 (Message SourceTag),
    requestAlphaField  :: Required D2 (Value (Fixed Word64)),
    requestOmegaField  :: Optional D3 (Value (Fixed Word64))
} deriving (Generic, Eq, Show)

instance Encode RequestSource
