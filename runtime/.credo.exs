%{
  configs: [
    %{
      name: "default",
      strict: true,
      files: %{
        included: ["apps/*/lib/", "apps/*/test/"],
        excluded: [~r"/_build/", ~r"/deps/"]
      },
      checks: %{
        enabled: [
          # --- Consistency ---
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Consistency.LineEndings, []},
          {Credo.Check.Consistency.SpaceAroundOperators, []},
          {Credo.Check.Consistency.SpaceInParentheses, []},
          {Credo.Check.Consistency.TabsOrSpaces, []},
          # MultiAliasImportRequireUse — handled by Quokka
          # ParameterPatternMatching — handled by Quokka

          # --- Design ---
          {Credo.Check.Design.DuplicatedCode, false},
          {Credo.Check.Design.TagTODO, [exit_status: 0]},
          {Credo.Check.Design.TagFIXME, []},
          # AliasUsage — handled by Quokka

          # --- Readability ---
          {Credo.Check.Readability.FunctionNames, []},
          {Credo.Check.Readability.MaxLineLength, [max_length: 120]},
          {Credo.Check.Readability.ModuleAttributeNames, []},
          {Credo.Check.Readability.ModuleNames, []},
          {Credo.Check.Readability.PredicateFunctionNames, []},
          {Credo.Check.Readability.TrailingBlankLine, []},
          {Credo.Check.Readability.TrailingWhiteSpace, []},
          {Credo.Check.Readability.VariableNames, []},
          # AliasOrder — handled by Quokka
          # BlockPipe — handled by Quokka
          # LargeNumbers — handled by Quokka
          # ModuleDoc — handled by Quokka
          # MultiAlias — handled by Quokka
          # OneArityFunctionInPipe — handled by Quokka
          # ParenthesesOnZeroArityDefs — handled by Quokka
          # PipeIntoAnonymousFunctions — handled by Quokka
          # PreferImplicitTry — handled by Quokka
          # SinglePipe — handled by Quokka
          # StrictModuleLayout — handled by Quokka
          # StringSigils — handled by Quokka
          # UnnecessaryAliasExpansion — handled by Quokka
          # WithSingleClause — handled by Quokka

          # --- Refactor ---
          {Credo.Check.Refactor.Apply, []},
          {Credo.Check.Refactor.CyclomaticComplexity, []},
          {Credo.Check.Refactor.FunctionArity, []},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {Credo.Check.Refactor.Nesting, []},
          # CaseTrivialMatches — handled by Quokka
          # CondStatements — handled by Quokka
          # FilterCount — handled by Quokka
          # MapInto — handled by Quokka
          # MapJoin — handled by Quokka
          # NegatedConditionsInUnless — handled by Quokka
          # NegatedConditionsWithElse — handled by Quokka
          # PipeChainStart — handled by Quokka
          # RedundantWithClauseResult — handled by Quokka
          # UnlessWithElse — handled by Quokka
          # WithClauses — handled by Quokka

          # --- Warning ---
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, []},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []}
        ]
      }
    }
  ]
}
