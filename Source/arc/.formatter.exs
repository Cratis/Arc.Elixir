# The macros Arc exports to your formatter: with `import_deps: [:cratis_arc]` in your
# .formatter.exs, `field :name, :string` stays free of parentheses.
locals_without_parens = [
  field: 2,
  field: 3,
  authorize: 1,
  response: 1
]

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
