defmodule Cli do
  @moduledoc """
  Documentation for Cli.
  """

  @doc """
  Promt user for some input with default value.
  Default version will be returned if user didn't enter enything except of empty string
  """
  @spec promt(binary, binary) :: binary
  def promt(description, default \\ "") do
    description
    |> IO.gets()
    |> String.trim()
    |> default(default)
  end

  @doc """
  Promts user for some input. 
  If user didn't entered anything promt will show again till any input
  """
  @spec promt!(binary) :: binary
  def promt!(description) do
    case promt(description) do
      "" ->
        promt!(description)

      res ->
        res
    end
  end

  @doc """
  Draws selected colored text
  """
  @spec selected(binary) :: binary
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

  defp default("", default), do: default
  defp default(str, _), do: str
end
