defmodule Cratis.Arc.DisplayNamesTest do
  use ExUnit.Case, async: true

  alias Cratis.Arc.Naming

  test "an id is shown in PascalCase by default" do
    assert Naming.display("register-author") == "RegisterAuthor"
  end

  test "an id can be shown as declared, in kebab-case or by a function" do
    assert Naming.display("register-author", :as_declared) == "register-author"
    assert Naming.display("register-author", :kebab_case) == "register-author"
    assert Naming.display("register-author", &String.upcase/1) == "REGISTER-AUTHOR"
  end
end
