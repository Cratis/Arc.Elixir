# Copyright (c) Cratis. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

defmodule Arc.ProxyGenerator.Render do
  @moduledoc false

  # Renders the TypeScript of commands, queries and types. The output follows the C# proxy
  # generator's templates, so the same `@cratis/arc` and `@cratis/arc.react` packages consume it.

  alias Arc.{Descriptor, Naming}
  alias Arc.ProxyGenerator.TypeScript, as: TS

  @notice "// **DO NOT EDIT** - This file is an automatically generated file."

  # Commands

  def command(%Descriptor{} = d, opts) do
    skip = opts.layout
    folder = TS.folder(d.module, skip)
    props = Enum.map(d.fields, &property(&1, skip))
    response = d.response && TS.map(d.response, skip)
    rules = rules(d.fields)
    has_rules? = rules != []

    context = %{
      name: d.name,
      props: props,
      response: response,
      response_generic: response_generic(response),
      has_rules?: has_rules?
    }

    imports = TS.imports(Enum.map(props, & &1.mapping) ++ List.wrap(response), folder, skip)

    join(
      command_head(has_rules?) ++
        import_lines(imports) ++
        [""] ++
        command_interface(d, props) ++
        validator_block(d.name, rules, has_rules?, "CommandValidator<I#{d.name}>") ++
        command_class_head(d, context.response_generic) ++ command_body(d, opts, context)
    )
  end

  defp command_head(has_rules?) do
    command_imports = if has_rules?, do: "Command, CommandValidator", else: "Command"

    [
      @notice,
      "import { #{command_imports} } from '@cratis/arc/commands';",
      "import { type ClearCommandValues, type SetCommandValues, useCommand } from '@cratis/arc.react/commands';",
      "import { SliceLocation as ArcSliceLocation, PropertyDescriptor } from '@cratis/arc/reflection';"
    ]
  end

  defp command_interface(d, props) do
    doc_block(d.doc) ++
      ["export interface I#{d.name} {"] ++
      Enum.flat_map(props, fn p ->
        doc_member(p.field.doc) ++ ["    #{p.camel}?: #{p.ts};"]
      end) ++ ["}", ""]
  end

  defp response_generic(nil), do: ""
  defp response_generic(r), do: ", #{r.type}#{if r.enumerable?, do: "[]"}"

  defp command_class_head(d, response_generic) do
    doc_block(d.doc) ++
      [
        "export class #{d.name} extends Command<I#{d.name}#{response_generic}> implements I#{d.name} {"
      ]
  end

  defp command_body(d, opts, context) do
    command_metadata(d, opts, context) ++
      command_properties(context.props) ++
      command_constructor(context.response) ++
      command_request_parameters() ++
      Enum.flat_map(context.props, &command_accessor/1) ++ command_use(context)
  end

  defp command_metadata(d, opts, %{name: name, has_rules?: has_rules?}) do
    {module, feature, slice} = Descriptor.slice_location(d, opts.segments_to_skip)
    route = Descriptor.command_route(d, route_opts(opts))

    [
      "    static readonly sliceLocation: ArcSliceLocation = new ArcSliceLocation('#{module}', '#{feature}', '#{slice}');",
      "    readonly route: string = '#{route}';"
    ] ++
      if(has_rules?,
        do: ["    readonly validation: CommandValidator = new #{name}Validator();"],
        else: []
      ) ++
      [
        "    readonly treatWarningsAsErrors: boolean = false;",
        "    readonly roles: string[] = [#{roles(d.authorization)}];"
      ]
  end

  defp command_properties(props) do
    ["    readonly propertyDescriptors: PropertyDescriptor[] = ["] ++
      Enum.map(props, fn p ->
        "        new PropertyDescriptor('#{p.camel}', #{p.mapping.ctor}, #{p.field.nullable?}),"
      end) ++
      ["    ];", ""] ++
      Enum.map(props, fn p ->
        "    ##{p.camel}#{if p.field.nullable?, do: "?", else: "!"}: #{p.ts};"
      end) ++
      [""]
  end

  defp command_constructor(nil),
    do: ["    constructor() {", "        super(Object, false);", "    }"]

  defp command_constructor(r),
    do: ["    constructor() {", "        super(#{r.ctor}, #{r.enumerable?});", "    }"]

  defp command_request_parameters do
    [
      "",
      "    get requestParameters(): string[] {",
      "        return [",
      "        ];",
      "    }",
      ""
    ]
  end

  defp command_accessor(p) do
    nullable = if p.field.nullable?, do: " | undefined", else: ""

    doc_member(p.field.doc) ++
      [
        "    get #{p.camel}(): #{p.ts}#{nullable} {",
        "        return this.##{p.camel};",
        "    }",
        "",
        "    set #{p.camel}(value: #{p.ts}#{nullable}) {",
        "        this.##{p.camel} = value;",
        "        this.propertyChanged('#{p.camel}');",
        "    }"
      ]
  end

  defp command_use(%{name: name, response_generic: response_generic}) do
    [
      "",
      "    static use(initialValues?: I#{name}): [#{name}, SetCommandValues<I#{name}>, ClearCommandValues] {",
      "        return useCommand<#{name}, I#{name}#{response_generic}>(#{name}, initialValues);",
      "    }",
      "}"
    ]
  end

  # Queries

  def query(%Descriptor{} = d, %Descriptor.Query{} = q, opts) do
    context = query_context(d, q, opts)

    join(
      query_imports(context) ++
        import_lines(context.imports) ++
        [""] ++
        query_sort_classes(context) ++
        query_parameters_block(d.doc, context) ++
        query_class_head(q.doc, context) ++ query_body(d, q, opts, context)
    )
  end

  defp query_context(d, q, opts) do
    skip = opts.layout
    model_map = TS.map(d.model, skip)
    model_fields = TS.model_fields(d.model, d.model_types)
    params = Enum.map(q.params, &property(&1, skip))
    rules = rules(q.params)

    %{
      name: Naming.pascal(q.name),
      model_map: model_map,
      model: model_map.type,
      model_type: if(q.many?, do: "#{model_map.type}[]", else: model_map.type),
      model_fields: model_fields,
      params: params,
      params?: params != [],
      many?: q.many?,
      observable?: q.observable?,
      has_sort?: q.many? and model_fields != [],
      rules: rules,
      has_rules?: rules != [],
      http: http_method(q.http_method),
      imports:
        TS.imports([model_map | Enum.map(params, & &1.mapping)], TS.folder(d.module, skip), skip)
    }
  end

  defp query_sort_classes(%{many?: false}), do: []

  defp query_sort_classes(context) do
    sort_cls =
      if context.observable?,
        do: "SortingActionsForObservableQuery",
        else: "SortingActionsForQuery"

    sortby_classes(context.name, context.model_type, context.model_fields, sort_cls)
  end

  defp query_parameters_block(doc, %{name: name, params: params} = context) do
    if context.params? do
      param_interface(name, doc, params) ++
        validator_block(
          name,
          context.rules,
          context.has_rules?,
          "QueryValidator<#{name}Parameters>"
        )
    else
      validator_block(name, context.rules, context.has_rules?, "QueryValidator<object>")
    end
  end

  defp query_class_head(doc, %{name: name, model_type: model_type} = context) do
    base = if context.observable?, do: "ObservableQueryFor", else: "QueryFor"
    generics = if context.params?, do: "#{model_type}, #{name}Parameters", else: model_type
    doc_block(doc) ++ ["export class #{name} extends #{base}<#{generics}> {"]
  end

  defp query_body(d, q, opts, context) do
    query_metadata(d, q, opts, context) ++
      query_defaults(context) ++
      query_constructor(context) ++
      query_parameter_members(context.params) ++
      query_sort_accessors(context) ++ use_methods(context) ++ ["}"]
  end

  defp query_metadata(d, q, opts, %{name: name, has_rules?: has_rules?}) do
    {module, feature, slice} = Descriptor.slice_location(d, opts.segments_to_skip)
    route = Descriptor.query_route(d, q, route_opts(opts))

    [
      "    static readonly sliceLocation: ArcSliceLocation = new ArcSliceLocation('#{module}', '#{feature}', '#{slice}');",
      "    readonly route: string = '#{route}';",
      "    readonly queryName: string = '#{Descriptor.query_name(d, q)}';"
    ] ++
      if(has_rules?,
        do: ["    readonly validation: QueryValidator = new #{name}Validator();"],
        else: []
      ) ++
      [
        "    readonly treatWarningsAsErrors: boolean = false;",
        "    readonly roles: string[] = [#{roles(q.authorization)}];"
      ]
  end

  defp query_defaults(%{many?: true, name: name, model: model}) do
    [
      "    readonly defaultValue: #{model}[] = [];",
      "    private readonly _sortBy: #{name}SortBy;",
      "    private static readonly _sortBy: #{name}SortByWithoutQuery = new #{name}SortByWithoutQuery();"
    ]
  end

  defp query_defaults(%{model: model}),
    do: ["    readonly defaultValue: #{model} = {} as #{model};"]

  defp query_constructor(%{name: name, many?: many?, http: http, model_map: model_map}) do
    ["", "    constructor() {", "        super(#{model_map.ctor}, #{many?});"] ++
      if(many?, do: ["        this._sortBy = new #{name}SortBy(this);"], else: []) ++
      if(http, do: ["        this.setHttpMethod(QueryHttpMethod.#{http});"], else: []) ++
      ["    }"]
  end

  defp query_parameter_members(params) do
    ["", "    get requiredRequestParameters(): string[] {", "        return ["] ++
      for(p <- params, not p.field.nullable?, do: "            '#{p.camel}',") ++
      [
        "        ];",
        "    }",
        "",
        "    readonly parameterDescriptors: ParameterDescriptor[] = ["
      ] ++
      for(
        p <- params,
        do:
          "        new ParameterDescriptor('#{p.camel}', #{p.mapping.ctor}, #{p.mapping.enumerable?}),"
      ) ++
      ["    ];", ""] ++
      for(p <- params, do: "    #{p.camel}!: #{p.ts};") ++
      if(params != [], do: [""], else: [])
  end

  defp query_sort_accessors(%{many?: false}), do: []

  defp query_sort_accessors(%{name: name}) do
    [
      "    get sortBy(): #{name}SortBy {",
      "        return this._sortBy;",
      "    }",
      "",
      "    static get sortBy(): #{name}SortByWithoutQuery {",
      "        return this._sortBy;",
      "    }",
      ""
    ]
  end

  defp query_imports(%{
         many?: many?,
         observable?: observable?,
         has_sort?: has_sort?,
         has_rules?: has_rules?,
         http: http
       }) do
    method = if http, do: ", QueryHttpMethod", else: ""
    validator = if has_rules?, do: ", QueryValidator", else: ""
    base = if observable?, do: "ObservableQueryFor", else: "QueryFor"

    {first, second} =
      cond do
        many? and observable? ->
          sorting =
            if has_sort?, do: ", SortingActions, SortingActionsForObservableQuery", else: ""

          {"import { type ChangeSet, #{base}, Paging#{method}, QueryResultWithState#{validator}, Sorting#{sorting} } from '@cratis/arc/queries';",
           "import { ObservableQueryWhen, type SetPage, type SetPageSize, type SetSorting, useChangeStream, useObservableQuery, useObservableQueryWithPaging, useSuspenseObservableQuery, useSuspenseObservableQueryWithPaging } from '@cratis/arc.react/queries';"}

        many? ->
          sorting = if has_sort?, do: ", SortingActions, SortingActionsForQuery", else: ""

          {"import { Paging, #{base}#{method}, QueryResultWithState#{validator}, Sorting#{sorting} } from '@cratis/arc/queries';",
           "import { type PerformQuery, QueryWhen, type SetPage, type SetPageSize, type SetSorting, useQuery, useQueryWithPaging, useSuspenseQuery, useSuspenseQueryWithPaging } from '@cratis/arc.react/queries';"}

        observable? ->
          {"import { #{base}#{method}, QueryResultWithState#{validator} } from '@cratis/arc/queries';",
           "import { ObservableQueryWhen, useObservableQuery, useSuspenseObservableQuery } from '@cratis/arc.react/queries';"}

        true ->
          {"import { #{base}#{method}, QueryResultWithState#{validator} } from '@cratis/arc/queries';",
           "import { type PerformQuery, QueryWhen, type SetSorting, useQuery, useSuspenseQuery } from '@cratis/arc.react/queries';"}
      end

    [
      @notice,
      first,
      second,
      "import { SliceLocation as ArcSliceLocation, ParameterDescriptor } from '@cratis/arc/reflection';"
    ]
  end

  defp sortby_classes(name, model_type, fields, sort_cls) do
    [
      "class #{name}SortBy {"
    ] ++
      for(f <- fields, do: "    private _#{Naming.camel(f.name)}: #{sort_cls}<#{model_type}>;") ++
      ["", "    constructor(readonly query: #{name}) {"] ++
      for(
        f <- fields,
        do:
          "        this._#{Naming.camel(f.name)} = new #{sort_cls}<#{model_type}>('#{Naming.camel(f.name)}', query);"
      ) ++
      ["    }", ""] ++
      Enum.flat_map(fields, fn f ->
        c = Naming.camel(f.name)

        [
          "    get #{c}(): #{sort_cls}<#{model_type}> {",
          "        return this._#{c};",
          "    }",
          ""
        ]
      end) ++
      ["}", "", "class #{name}SortByWithoutQuery {"] ++
      for(
        f <- fields,
        do:
          "    private _#{Naming.camel(f.name)}: SortingActions  = new SortingActions('#{Naming.camel(f.name)}');"
      ) ++
      [""] ++
      Enum.flat_map(fields, fn f ->
        c = Naming.camel(f.name)
        ["    get #{c}(): SortingActions {", "        return this._#{c};", "    }", ""]
      end) ++ ["}", ""]
  end

  defp param_interface(name, doc, params) do
    doc_block(doc) ++
      ["export interface #{name}Parameters {"] ++
      Enum.flat_map(params, fn p ->
        [if(p.field.nullable?, do: "    #{p.camel}?: #{p.ts};", else: "    #{p.camel}: #{p.ts};")]
      end) ++ ["}", ""]
  end

  defp validator_block(_name, _rules, false, _generic), do: []

  defp validator_block(name, rules, true, generic) do
    [
      "export class #{name}Validator extends #{generic} {",
      "    constructor() {",
      "        super();"
    ] ++
      rule_lines(rules) ++ ["    }", "}", ""]
  end

  defp use_methods(%{name: name, params?: params?} = context) do
    context =
      Map.merge(context, %{
        args_decl: if(params?, do: "args?: #{name}Parameters", else: nil),
        args_pass: if(params?, do: "args", else: "undefined"),
        generic_args: if(params?, do: ", #{name}Parameters", else: "")
      })

    cond do
      context.many? and context.observable? -> observable_many_use_methods(context)
      context.many? -> many_use_methods(context)
      context.observable? -> observable_use_methods(context)
      true -> single_use_methods(context)
    end
  end

  defp observable_many_use_methods(%{
         name: name,
         model: model,
         args_decl: args_decl,
         args_pass: args_pass,
         generic_args: generic_args
       }) do
    sig = fn extra -> join_args([args_decl | extra]) end

    [
      "    static use(#{sig.(["sorting?: Sorting"])}): [QueryResultWithState<#{model}[]>, SetSorting] {",
      "        return useObservableQuery<#{model}[], #{name}#{generic_args}>(#{name}, #{args_pass}, sorting);",
      "    }",
      "",
      "    static useWithPaging(#{join_args(["pageSize: number", args_decl, "sorting?: Sorting"])}): [QueryResultWithState<#{model}[]>, SetSorting, SetPage, SetPageSize] {",
      "        return useObservableQueryWithPaging<#{model}[], #{name}>(#{name}, new Paging(0, pageSize), #{args_pass}, sorting);",
      "    }",
      "",
      "    static useSuspense(#{sig.(["sorting?: Sorting"])}): [QueryResultWithState<#{model}[]>, SetSorting] {",
      "        return useSuspenseObservableQuery<#{model}[], #{name}#{generic_args}>(#{name}, #{args_pass}, sorting);",
      "    }",
      "",
      "    static useSuspenseWithPaging(#{join_args(["pageSize: number", args_decl, "sorting?: Sorting"])}): [QueryResultWithState<#{model}[]>, SetSorting, SetPage, SetPageSize] {",
      "        return useSuspenseObservableQueryWithPaging<#{model}[], #{name}>(#{name}, new Paging(0, pageSize), #{args_pass}, sorting);",
      "    }",
      "",
      "    static useChangeStream(#{join_args([args_decl, "getKey?: (item: #{model}) => unknown", "sorting?: Sorting"])}): ChangeSet<#{model}> {",
      "        return useChangeStream<#{model}, #{name}#{generic_args}>(#{name}, #{args_pass}, getKey, sorting);",
      "    }",
      "",
      "    static when(condition: boolean): ObservableQueryWhen<#{name}, #{model}[]#{generic_args}> {",
      "        return new ObservableQueryWhen<#{name}, #{model}[]#{generic_args}>(#{name}, condition);",
      "    }"
    ]
  end

  defp many_use_methods(%{
         name: name,
         model: model,
         params?: params?,
         args_decl: args_decl,
         args_pass: args_pass,
         generic_args: generic_args
       }) do
    [
      "    static use(#{join_args([args_decl, "sorting?: Sorting"])}): [QueryResultWithState<#{model}[]>, PerformQuery#{if params?, do: "<#{name}Parameters>"}, SetSorting] {",
      "        return useQuery<#{model}[], #{name}#{generic_args}>(#{name}, #{args_pass}, sorting);",
      "    }",
      "",
      "    static useWithPaging(#{join_args(["pageSize: number", args_decl, "sorting?: Sorting"])}): [QueryResultWithState<#{model}[]>, PerformQuery, SetSorting, SetPage, SetPageSize] {",
      "        return useQueryWithPaging<#{model}[], #{name}>(#{name}, new Paging(0, pageSize), #{args_pass}, sorting);",
      "    }",
      "",
      "    static useSuspense(#{join_args([args_decl, "sorting?: Sorting"])}): [QueryResultWithState<#{model}[]>, PerformQuery#{if params?, do: "<#{name}Parameters>"}, SetSorting] {",
      "        return useSuspenseQuery<#{model}[], #{name}#{generic_args}>(#{name}, #{args_pass}, sorting);",
      "    }",
      "",
      "    static useSuspenseWithPaging(#{join_args(["pageSize: number", args_decl, "sorting?: Sorting"])}): [QueryResultWithState<#{model}[]>, PerformQuery, SetSorting, SetPage, SetPageSize] {",
      "        return useSuspenseQueryWithPaging<#{model}[], #{name}>(#{name}, new Paging(0, pageSize), #{args_pass}, sorting);",
      "    }",
      "",
      "    static when(condition: boolean): QueryWhen<#{name}, #{model}[]#{generic_args}> {",
      "        return new QueryWhen<#{name}, #{model}[]#{generic_args}>(#{name}, condition);",
      "    }"
    ]
  end

  defp observable_use_methods(%{
         name: name,
         model: model,
         params?: params?,
         args_decl: args_decl,
         generic_args: generic_args
       }) do
    [
      "    static use(#{args_decl || ""}): [QueryResultWithState<#{model}>] {",
      "        const [result] = useObservableQuery<#{model}, #{name}#{generic_args}>(#{name}#{if params?, do: ", args"});",
      "        return [result];",
      "    }",
      "",
      "    static useSuspense(#{args_decl || ""}): [QueryResultWithState<#{model}>] {",
      "        const [result] = useSuspenseObservableQuery<#{model}, #{name}#{generic_args}>(#{name}#{if params?, do: ", args"});",
      "        return [result];",
      "    }",
      "",
      "    static when(condition: boolean): ObservableQueryWhen<#{name}, #{model}#{generic_args}> {",
      "        return new ObservableQueryWhen<#{name}, #{model}#{generic_args}>(#{name}, condition);",
      "    }"
    ]
  end

  defp single_use_methods(%{
         name: name,
         model: model,
         params?: params?,
         args_decl: args_decl,
         generic_args: generic_args
       }) do
    [
      "    static use(#{args_decl || ""}): [QueryResultWithState<#{model}>, PerformQuery#{if params?, do: "<#{name}Parameters>"}, SetSorting] {",
      "        return useQuery<#{model}, #{name}#{generic_args}>(#{name}#{if params?, do: ", args"});",
      "    }",
      "",
      "    static useSuspense(#{args_decl || ""}): [QueryResultWithState<#{model}>, PerformQuery#{if params?, do: "<#{name}Parameters>"}, SetSorting] {",
      "        return useSuspenseQuery<#{model}, #{name}#{generic_args}>(#{name}#{if params?, do: ", args"});",
      "    }",
      "",
      "    static when(condition: boolean): QueryWhen<#{name}, #{model}#{generic_args}> {",
      "        return new QueryWhen<#{name}, #{model}#{generic_args}>(#{name}, condition);",
      "    }"
    ]
  end

  defp join_args(list), do: list |> Enum.reject(&is_nil/1) |> Enum.join(", ")

  # Types

  def type(module, fields, opts) do
    skip = opts.layout
    folder = TS.folder(module, skip)
    {_ns, name} = Arc.Naming.module_parts(module)
    props = Enum.map(fields, &property(&1, skip))

    imports =
      TS.imports(Enum.map(props, & &1.mapping), folder, skip)
      |> Enum.reject(&(elem(&1, 0) == name))

    head =
      if props == [],
        do: [@notice],
        else: [@notice, "import { field } from '@cratis/fundamentals';"]

    join(
      head ++
        Enum.map(imports, fn {type, path} -> "import { #{type} } from '#{path}';" end) ++
        [""] ++
        ["export class #{name} {"] ++
        Enum.flat_map(props, fn p ->
          decorator =
            if p.mapping.enumerable?,
              do: "    @field(#{p.mapping.ctor}, true)",
              else: "    @field(#{p.mapping.ctor})"

          mark = if p.field.nullable?, do: "?", else: "!"
          doc_member(p.field.doc) ++ [decorator, "    #{p.camel}#{mark}: #{p.ts};"]
        end) ++ ["}"]
    )
  end

  # Shared

  defp property(field, skip) do
    mapping = TS.map(field.type, skip)

    %{
      field: field,
      camel: Naming.camel(field.name),
      mapping: mapping,
      ts: mapping.type <> if(mapping.enumerable?, do: "[]", else: "")
    }
  end

  defp import_lines(imports),
    do: Enum.map(imports, fn {type, path} -> "import { #{type} } from '#{path}';" end)

  defp roles(%{roles: roles}), do: roles |> Enum.map(&"'#{&1}'") |> Enum.join(", ")

  defp http_method(nil), do: nil
  defp http_method(:get), do: "Get"
  defp http_method(:query), do: "Query"

  defp route_opts(opts),
    do: [route_prefix: opts.route_prefix, segments_to_skip: opts.segments_to_skip]

  defp doc_block(nil), do: []
  defp doc_block(doc), do: ["/**", " * #{doc}", " */"]

  defp doc_member(nil), do: []
  defp doc_member(doc), do: ["", "    /**", "     * #{doc}", "     */"]

  # Client-side rules, restricted to the field types the matching TypeScript rule supports.
  defp rules(fields) do
    for field <- fields,
        rs = client_rules(field),
        rs != [],
        do: {Naming.camel(field.name), rs}
  end

  defp client_rules(%{type: :string, rules_source: opts}) when is_list(opts),
    do: Arc.Validation.rules(opts)

  defp client_rules(%{type: type, rules_source: opts})
       when type in [:integer, :float] and is_list(opts),
       do:
         opts
         |> Arc.Validation.rules()
         |> Enum.filter(&(&1.name in ~w(greaterThan greaterThanOrEqual lessThan lessThanOrEqual)))

  defp client_rules(_), do: []

  defp rule_lines(rules) do
    for {property, rs} <- rules, rule <- rs do
      "        this.ruleFor(c => c.#{property}).#{rule.name}(#{args(rule.args)});"
    end
  end

  defp args(args), do: Enum.map_join(args, ", ", &arg/1)
  defp arg({:regex, pattern}), do: "/" <> String.replace(pattern, "/", "\\/") <> "/"
  defp arg(n) when is_number(n), do: to_string(n)

  defp join(lines), do: Enum.join(lines, "\n") <> "\n"
end
