[
  import_deps: [:cratis_arc, :phoenix],
  # Chronicle's declaration macros, kept free of parentheses like Arc's.
  locals_without_parens: [unique: 1, unique: 2, from: 2],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
