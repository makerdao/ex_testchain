defmodule JsonRpc.HttpApi do
  @moduledoc """
  Base http layer
  """
  use HTTPoison.Base

  require Logger

  @doc false
  def process_response_body(""), do: %{}

  def process_response_body(body) do
    case Poison.decode(body, keys: :atoms) do
      {:ok, parsed} ->
        parsed

      {:error, err} ->
        Logger.error("Error parsing response #{inspect(body)} with error: #{inspect(err)}")
        body
    end
  end

  @doc """
  Send function will send JSONRPC request to given url with JSON request.

  Example: 

      iex> JsonRpc.HttpApi.send("http://localhost:8545", "eth_coinbase")
      {:ok, "0xe9f5eb57243c1c791e0c14b16f0b67c01cdc1992"}

  """
  @spec send(binary, binary, term(), non_neg_integer()) :: {:ok, term()} | {:error, term()}
  def send(url, method, params \\ nil, id \\ 0) do
    req =
      %{
        jsonrpc: "2.0",
        method: method,
        params: params,
        id: id
      }
      |> Poison.encode!()

    Logger.debug("#{__MODULE__}: #{inspect(req)}")

    url
    |> post(req, [{"Content-Type", "application/json"}])
    |> fetch_body()
  end

  # Pick only needed information
  defp fetch_body({:ok, %HTTPoison.Response{status_code: 200, body: %{result: result}}}),
    do: {:ok, result}

  defp fetch_body(
         {:ok,
          %HTTPoison.Response{status_code: 200, body: %{error: %{code: code, message: message}}}}
       ),
       do: {:error, %{code: code, message: message}}

  defp fetch_body(res), do: res
end
