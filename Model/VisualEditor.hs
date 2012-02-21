module Model.VisualEditor
  ( Annotation (..)
  , VEChar (..)
  , VEDocument (..)
  , VEOperation (..)
  , VETransaction (..)
  , applyTransaction
  ) where

import Prelude
import qualified Data.Text as T
import qualified Data.Vector as V
import Data.Aeson
import Data.Aeson.Types (Parser)
import Control.Applicative ((<$>))
import Control.Monad (mzero)

data Annotation = Annotation
  { annotationType :: T.Text
  } deriving (Eq, Show, Read)

data ListStyle = Bullet
               | ListNumber
               deriving (Eq, Show, Read)

data VEChar = VEChar Char [Annotation]
            | StartParagraph
            | EndParagraph
            | StartHeading Int
            | EndHeading
            | StartPre
            | EndPre
            | StartList
            | EndList
            | StartListItem [ListStyle]
            | EndListItem
            deriving (Eq, Show, Read)
type VEText = [VEChar]

data VEOperation = Retain Int
                 | Insert VEText
                 | Delete VEText
                 | StartAnnotation Annotation
                 | StopAnnotation Annotation
                 deriving (Eq, Show, Read)

data VETransaction = VETransaction Int [VEOperation] deriving (Eq, Show, Read)

newtype VEDocument = VEDocument [VEChar] deriving (Eq, Show, Read)

applyTransaction :: VEDocument -> VETransaction -> VEDocument
applyTransaction (VEDocument chars) (VETransaction _ operations) = VEDocument $ go operations chars
  where
    go :: [VEOperation] -> [VEChar] -> [VEChar]
    go [] [] = []
    go [] _  = error "unretained input"
    go (Retain 0 : ops) chs = go ops chs
    go (Retain n : ops) (ch:chs) = ch:(go (Retain (n-1) : ops) chs)
    go (Retain _ : _) [] = [] --error "no input left to retain"
    go (Insert [] : ops) chs = go ops chs
    go (Insert (a:as) : ops) chs = a:(go (Insert as : ops) chs)
    go (Delete (a:as) : ops) (ch:chs) | a == ch = go (Delete as : ops) chs
                                      | otherwise = error "Char to delete and actual char don't match"
    -- TODO: other operations
    go (_:ops) chs = go ops chs

instance ToJSON Annotation where
  toJSON (Annotation type') = object
    [ "type" .= type'
    ]

instance FromJSON Annotation where
  parseJSON (Object o) = Annotation <$> o .: "type"
  parseJSON _ = mzero

instance ToJSON ListStyle where
  toJSON Bullet = String "bullet"
  toJSON ListNumber = String "number"

instance FromJSON ListStyle where
  parseJSON (String s) = case s of
    "bullet" -> return Bullet
    "number" -> return ListNumber
    _        -> mzero
  parseJSON _ = mzero

instance ToJSON VEChar where
  toJSON (VEChar ch []) = toJSON ch
  toJSON (VEChar ch as) = toJSON $ (toJSON ch):(map toJSON as)
  toJSON StartParagraph = object [ "type" .= String "paragraph" ]
  toJSON EndParagraph   = object [ "type" .= String "/paragraph" ]
  toJSON (StartHeading l) = object
    [ "type" .= String "heading", "attributes" .= object [ "level" .= l ] ]
  toJSON EndHeading = object [ "type" .= String "/heading" ]
  toJSON StartPre = object [ "type" .= String "pre" ]
  toJSON EndPre   = object [ "type" .= String "/pre" ]
  toJSON StartList = object [ "type" .= String "list" ]
  toJSON EndList   = object [ "type" .= String "/list" ]
  toJSON (StartListItem ls) = object
    [ "type" .= String "listItem", "attributes" .= object [ "styles" .= ls ] ]
  toJSON EndListItem = object [ "type" .= String "/listItem" ]

instance FromJSON VEChar where
  parseJSON (Array a) | not (V.null a) = do
    ch <- parseJSON $ V.head a
    as <- parseJSON $ Array (V.tail a)
    return $ VEChar ch as
  parseJSON (String s) = (\ch -> VEChar ch []) <$> parseJSON (String s)
  parseJSON (Object o) = do
    type' <- o .: "type"
    case type' :: T.Text of
      "paragraph" -> return StartParagraph
      "/paragraph" -> return EndParagraph
      "heading" -> StartHeading <$> attribute "level"
      "/heading" -> return EndHeading
      "pre" -> return StartPre
      "/pre" -> return EndPre
      "list" -> return StartList
      "/list" -> return EndList
      "listItem" -> StartListItem <$> attribute "styles"
      "/listItem" -> return EndListItem
      _ -> mzero
    where
      attribute :: FromJSON a => T.Text -> Parser a
      attribute attr = do
        attributes <- o .: "attributes"
        case attributes of
          Object oo -> oo .: attr
          _         -> mzero 
  parseJSON _ = mzero

instance ToJSON VEOperation where
  toJSON (Retain n) = object
    [ "type" .= String "retain"
    , "length" .= n
    ]
  toJSON (Insert text) = object
    [ "type" .= String "insert"
    , "data" .= text
    ]
  toJSON (Delete text) = object
    [ "type" .= String "remove"
    , "data" .= text
    ]
  toJSON (StartAnnotation a) = object
    [ "type" .= String "annotate"
    , "bias" .= String "start"
    , "annotation" .= a
    ]
  toJSON (StopAnnotation a) = object
    [ "type" .= String "annotate"
    , "bias" .= String "stop"
    , "annotation" .= a
    ]

instance FromJSON VEOperation where
  parseJSON (Object o) = do
    type' <- o .: "type"
    case type' of
      String "retain" -> Retain <$> o .: "length"
      String "insert" -> Insert <$> o .: "data"
      String "remove" -> Delete <$> o .: "data"
      String "annotate" -> do
        bias <- o .: "bias"
        annotation <- o .: "annotation"
        case bias :: T.Text of
          "start" -> return $ StartAnnotation annotation
          "stop"  -> return $ StopAnnotation  annotation
          _       -> mzero
      _ -> mzero
  parseJSON _ = mzero

instance ToJSON VETransaction where
  toJSON (VETransaction sizediff ops) = object
    [ "lengthDifference" .= sizediff
    , "operations" .= ops
    ]

instance FromJSON VETransaction where
  parseJSON (Object o) = do
    lengthDifference <- o .: "lengthDifference"
    operations <- o .: "operations"
    return $ VETransaction lengthDifference operations 
  parseJSON _ = mzero

instance ToJSON VEDocument where
  toJSON (VEDocument chs) = toJSON chs

instance FromJSON VEDocument where
  parseJSON j = VEDocument <$> parseJSON j