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

  @doc """
  Marking text as error message in CLI
  """
  @spec error(binary) :: binary
  def error(text) do
    """
    #{IO.ANSI.red()}error:#{IO.ANSI.reset()} #{text}
    """
  end

  @doc """
  Colorize text as comment
  """
  @spec comment(binary) :: binary
  def comment(text) do
    IO.ANSI.light_black() <> text <> IO.ANSI.reset()
  end
end
