defmodule WebApiWeb.ErrorViewTest do
  use WebApiWeb.ConnCase, async: true

  # Bring render/3 and render_to_string/3 for testing custom views
  import Phoenix.View

  test "renders 404.json" do
    assert render(WebApiWeb.ErrorView, "404.json", []) == %{
             status: 1,
             errors: %{detail: "Not Found"}
           }
  end

  test "renders 500.json" do
    assert render(WebApiWeb.ErrorView, "500.json", []) ==
             %{status: 1, errors: %{detail: "Internal Server Error"}}
  end
end
