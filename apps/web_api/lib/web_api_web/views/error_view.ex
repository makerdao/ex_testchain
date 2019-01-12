defmodule WebApiWeb.ErrorView do
  use WebApiWeb, :view

  # If you want to customize a particular status code
  # for a certain format, you may uncomment below.
  def render("500.json", %{message: message}) do
    %{status: 1, errors: %{detail: message}}
  end

  def render("500.json", _assigns) do
    %{status: 1, errors: %{detail: "Internal Server Error"}}
  end

  def render("404.json", _assigns) do
    %{status: 1, errors: %{detail: "Not Found"}}
  end

  def render("400.json", %{message: message}) do
    %{status: 1, errors: %{detail: message}}
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def template_not_found(template, _assigns) do
    %{status: 1, errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
