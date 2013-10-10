{-# OPTIONS_GHC -fno-warn-unused-binds #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE OverloadedStrings #-}

{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE EmptyDataDecls #-}
module SqliteTest (specs) where

import Control.Monad.IO.Class
import qualified Data.Conduit as C
import qualified Data.Conduit.List as CL
import qualified Data.Map as Map
import qualified Data.Text as T

import Database.Persist.Sqlite
import Control.Concurrent

import Init
import MigrationSql

-- Test lower case names
share [mkPersist sqlSettings, mkMigrate "lowerCaseMigrate"] [persistLowerWithSql|
LowerCaseTable id=my_id
    fullName Text
    Triggers
        tableIdTrig AFTER INSERT
        tableTrig BEFORE DELETE
    Indexes
        tableIndex full_name
RefTable
    someVal Int sql=something_else
    lct LowerCaseTableId
    UniqueRefTable someVal
|]

specs :: Spec
specs = describe "rename specs" $ do
  it "Check extra blocks" $ do
      entityExtra (entityDef (Nothing :: Maybe LowerCaseTable)) @?=
          Map.fromList
              [ ( "Indexes"
                , map T.words ["tableIndex full_name"])
              , ( "Triggers"
                , map T.words [ "tableIdTrig AFTER INSERT"
                              , "tableTrig BEFORE DELETE"])
              ]
  it "Create the tables and run additional migration" $ asIO $ do
    runConn' (getSqlCode,triggers) $ do
      runMigration lowerCaseMigrate
  it "Activates the insertion trigger" $ asIO $ do
    runConn' (getSqlCode,triggers) $ do
      liftIO $ threadDelay 2000000
      C.runResourceT $
        rawExecute "INSERT INTO lower_case_table (full_name) VALUES ('abc');" [] C.$$ CL.sinkNull
      value <- C.runResourceT $
        rawQuery "SELECT something_else, lct FROM ref_table ORDER BY id DESC LIMIT 1" []
          C.$$ CL.consume
      liftIO $ map (drop 1) value `shouldBe` [[PersistInt64 1]]


asIO :: IO a -> IO a
asIO = id


