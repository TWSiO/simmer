{-
Welcome to a Spago project!
You can edit this file as you like.
-}
{ name = "rough"
, dependencies =
    [ "console"
    , "effect"
    , "psci-support"
    , "string-parsers"
    , "node-readline"
    , "ordered-collections"
    , "spec"
    , "numbers"
    , "purescript-yarn"
    ]
, packages = ./packages.dhall
, sources = [ "src/**/*.purs", "test/**/*.purs" ]
}
