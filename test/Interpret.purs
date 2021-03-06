module Test.Interpret where

import Prelude
import Effect (Effect)
import Test.Spec (it, describe, Spec)
import Test.Spec.Assertions (shouldEqual)
import Data.Either (Either(..))
import Data.Map (empty, singleton, fromFoldable)
import Data.Array (uncons)
import Data.Maybe (Maybe(..), fromMaybe)
import Effect.Class (liftEffect)
import Effect.Aff (Aff)
import Data.Tuple (Tuple(..))
import Data.Newtype (over)
import Effect.Class.Console (log)
import Text.Parsing.StringParser.Expr as Op

import Simmer.Interface (convertFn)
import Simmer.AST as AST
import Simmer.Interpret as I

interpretSuite :: Spec Unit
interpretSuite = describe "Interpreter tests" do
    evalSimple
    parseAndEval
    longerTests

emptyEnviron :: I.Environment
emptyEnviron  = I.Environment { values: empty }

simpleFn :: I.SimmerFn
simpleFn = I.Lambda
    { parameters: [ "x" ]
    , body: AST.Ident "x"
    , environment: emptyEnviron
    }

twoParam :: I.SimmerFn
twoParam = I.Foreign handleMaybe
    where
      handleParams :: Array I.Value -> Maybe (Effect (Either String I.Value))
      handleParams params = do
         f <- uncons params
         let first = f.head
         g <- uncons f.tail
         let second = g.head
         let applied = (fn first second) :: Effect (Either String I.Value)
         if g.tail /= [] then Nothing else (Just applied)
      tooMany :: Effect (Either String I.Value)
      tooMany = do
         pure <<< Left $ "Too many parameters"
      handleMaybe :: Array I.Value -> Effect (Either String I.Value)
      handleMaybe params = fromMaybe tooMany (handleParams params)
      fn :: I.Value -> I.Value -> Effect (Either String I.Value)
      fn (I.NumberVal l) (I.NumberVal r) = do
       pure <<< Right <<< I.NumberVal$ l + r
      fn _ _ = do
       pure <<< Left $ "Expected two numbers."

logStr :: String -> Effect (Either String String)
logStr str = do
    _ <- log str
    pure $ Right (str <> " foo")

logLorem :: Effect (Either String String)
logLorem = do
    _ <- log "lorem"
    pure $ Right "lorem"

basicEnv :: I.Environment
basicEnv = I.Environment
    { values: fromFoldable
    [ Tuple "foo" (I.StringVal "bar")
    , Tuple "one" (I.NumberVal 1.0)
    , Tuple "id" (I.FunctionVal simpleFn)
    , Tuple "logStr" (I.FunctionVal <<< I.Foreign <<< convertFn $ logStr)
    , Tuple "logLorem" (I.FunctionVal <<< I.Foreign <<< convertFn $ logLorem)
    ]
    }

basicOps :: I.Operators
basicOps = over I.Operators replace I.emptyOperators 
    where
      replace = _ { first = [ I.Operator twoParam (I.Infix "+" Op.AssocRight) ] }

basicLib :: I.Library
basicLib = Tuple basicEnv basicOps

evalSimple :: Spec Unit
evalSimple = describe "Simple eval stuff" do
    it "Test eval ident smoke" do
       result <- (liftEffect $ I.eval (I.Environment { values: singleton "foo" (I.StringVal "bar") }) (AST.Ident "foo")) :: Aff (Either String I.Value)
       result `shouldEqual` Right (I.StringVal "bar")
    it "Test eval num smoke" do
       result <- (liftEffect $ I.eval emptyEnviron (AST.Number 123.0)) :: Aff (Either String I.Value)
       result `shouldEqual` Right (I.NumberVal 123.0)
    it "Test eval string smoke" do
       result <- (liftEffect $ I.eval emptyEnviron (AST.String "Foo")) :: Aff (Either String I.Value)
       result `shouldEqual` Right (I.StringVal "Foo")
    it "Test eval assign smoke" do
       result <- (liftEffect $ I.eval emptyEnviron (AST.Assignment "Foo" (AST.Number 123.0) (AST.Number 789.0))) :: Aff (Either String I.Value)
       result `shouldEqual` Right (I.NumberVal 789.0)
    it "Test eval prefix smoke" do
       result <- (liftEffect $ I.eval (I.Environment { values: singleton "*" (I.FunctionVal simpleFn) }) (AST.Call (AST.Ident "*") (AST.String "bar")))
       result `shouldEqual` Right (I.StringVal "bar")
    it "Test eval postfix smoke" do
       result <- (liftEffect $ I.eval (I.Environment { values: singleton "!" (I.FunctionVal simpleFn) }) (AST.Call (AST.Ident "!") (AST.String "bar")))
       result `shouldEqual` Right (I.StringVal "bar")
    it "Test eval infix smoke" do
       result <- (liftEffect $ I.eval (I.Environment { values: singleton "+" (I.FunctionVal twoParam) }) (AST.Call (AST.Call (AST.Ident "+") (AST.Number 2.0)) (AST.Number 3.0)))
       result `shouldEqual` Right (I.NumberVal 5.0)
    it "Test eval with too many parameters" do
       result <- (liftEffect $ I.eval (I.Environment { values: singleton "+" (I.FunctionVal twoParam) }) (AST.Call (AST.Call (AST.Call (AST.Ident "+") (AST.Number 2.0)) (AST.Number 3.0)) (AST.Number 3.0)))
       result `shouldEqual` (Left "Too many parameters")

parseAndEval :: Spec Unit
parseAndEval = describe "Parsing then evaluating" do
    it "Test eval' smoke" do
       result <- (liftEffect $ I.eval' [ basicLib ] "\"lorem\"")
       result `shouldEqual` Right (I.StringVal "lorem")
    it "Test eval' foo" do
       result <- (liftEffect $ I.eval' [ basicLib ] "foo")
       result `shouldEqual` Right (I.StringVal "bar")
    it "Test eval' id" do
       result <- (liftEffect $ I.eval' [ basicLib ] "id 7")
       result `shouldEqual` Right (I.NumberVal 7.0)
    it "Test eval' plus" do
       result <- (liftEffect $ I.eval' [ basicLib ] "3 + 7")
       result `shouldEqual` Right (I.NumberVal 10.0)
    it "Test eval' logStr" do
       result <- (liftEffect $ I.eval' [ basicLib ] "logStr \"Hello world\"")
       result `shouldEqual` Right (I.StringVal "Hello world foo")
    it "Test eval' logLorem. Should also say lorem above this test" do
       result <- (liftEffect $ I.eval' [ basicLib ] "logLorem!")
       result `shouldEqual` Right (I.StringVal "lorem")
    it "Test plus in paren" do
       result <- (liftEffect $ I.eval' [ basicLib ] "(3 + 7)")
       result `shouldEqual` Right (I.NumberVal 10.0)
    it "Test id on paren" do
       result <- (liftEffect $ I.eval' [ basicLib ] "id (3 + 7)")
       result `shouldEqual` Right (I.NumberVal 10.0)
    it "Test semicolon" do
       result <- (liftEffect $ I.eval' [ basicLib ] "logStr \"lorem\"; logStr \"ipsum\"; id 5; id 7")
       result `shouldEqual` Right (I.NumberVal 7.0)
    it "Test nonsense operator" do
       -- TODO This should fail. It's not a recognized operator
       result <- (liftEffect $ I.eval' [ basicLib ] "logStr \"lorem\"~ logStr \"ipsum\"~ id 5~ id 7")
       result `shouldEqual` Left "I don't remember what the message should be but it should be left"

longerTests :: Spec Unit
longerTests = describe "Some longer tests" do
    it "Longer test with lambda" do
       result <- basicEval longerInput1
       result `shouldEqual` Right (I.NumberVal 7.0)
    where
      basicEval = liftEffect <$> I.eval' [ basicLib ]

longerInput1 :: String
longerInput1 = """
    let a = 5 in
    let b = 2 in
    (\x -> x + b) a
    """
