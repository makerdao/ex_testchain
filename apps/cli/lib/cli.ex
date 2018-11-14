defmodule Cli do
  @moduledoc """
  Documentation for Cli.
  """

  def promt(description, default \\ "") do
    description
    |> IO.gets()
    |> String.trim()
    |> default(default)
  end

  def promt!(description) do
    case promt(description) do
      "" ->
        promt!(description)

      res ->
        res
    end
  end

  def default("", default), do: default
  def default(str, _), do: str

  def selected(text \\ ""), do: "#{IO.ANSI.underline()}#{IO.ANSI.cyan()}#{text}#{IO.ANSI.reset()}"
end
