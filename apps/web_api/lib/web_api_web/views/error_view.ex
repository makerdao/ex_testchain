defmodule WebApiWeb.ErrorView do
  use WebApiWeb, :view

  # If you want to customize a particular status code
  # for a certain format, you may uncomment below.
  def render("500.json", %{message: message}) do
    %{errors: %{detail: message}}
  end

  def render("500.json", _assigns) do
    %{errors: %{detail: "Internal Server Error"}}
  end

  def render("404.json", _assigns) do
    %{errors: %{detail: "Not Found"}}
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.json" becomes
  # "Not Found".
  def template_not_found(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
