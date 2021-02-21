module Parse where

import Prelude
import Control.Alt ((<|>))
import Text.Parsing.StringParser (Parser, fail, runParser, ParseError)
import Text.Parsing.StringParser.CodePoints (string, anyDigit, noneOf, char, eof, whiteSpace, skipSpaces)
import Text.Parsing.StringParser.Combinators (many1, many, between, lookAhead)
import Data.Number (fromString)
import Data.Maybe (Maybe(..))
import Data.String.Yarn (fromChars)
import Data.Foldable (fold)
import Data.String.CodeUnits (singleton)
import Data.Either (Either(..))

import Ast (Expression(..))

{-
    Comments? Maybe do a single initial pass eliminating them from the input.
        Have to make sure they're not in a string literal though.
            Or maybe having it be part of Expression would be alright?
    -}

identifyString :: Parser String
identifyString = do
    str <- fromChars <$> between (char '"') (char '"') (many $ noneOf ['"'])
    pure $ "\"" <> str <> "\""

comment :: Parser String
comment = do
    _ <- fromChars <$> between (char '#') end (many $ noneOf ['\n'])
    pure ""
    where
      end = lookAhead $ (singleton <$> char '\n') <|> ((\_ -> "") <$> eof)

removeComments :: Parser String
removeComments = fold <$> many (identifyString <|> comment <|> untilSignificant)
    where untilSignificant = fromChars <$> (many1 $ noneOf ['"', '#'])

-- Just removes comments
parse :: String -> Either ParseError Expression
parse source = uncommented >>= runParser expression
    where
      uncommented = runParser removeComments source

expression :: Parser Expression
expression = do
    _ <- (\_ -> String "") <$> skipSpaces
    numberExpr
        <|> stringExpr
        <|> identExpr
    where
        toExp = (\ws -> String ws) <$> whiteSpace

toNumber :: Parser Number
toNumber = do
    neg <- string "-" <|> pure ""
    whole <- many1 anyDigit
    dec <- string "." <|> pure ""
    less <- if dec == "." then fromChars <$> (many1 anyDigit) else pure ""
    let numString = neg <> fromChars whole <> dec <> less
    case fromString numString  of
        Just num -> pure num
        Nothing -> fail "Couldn't parse number"

numberExpr :: Parser Expression
numberExpr = Number <$> toNumber

stringExpr :: Parser Expression
stringExpr = do
    _ <- String <$> (string "\"")
    value <- (String <<< fromChars) <$> (many $ noneOf ['"'])
    _ <- String <$> string "\""
    pure value

identExpr :: Parser Expression
identExpr = (Ident <<< fromChars) <$> (many $ noneOf ['"'])
