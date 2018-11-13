defmodule JsonRpc.HttpApi do
  use HTTPoison.Base

  require Logger

  def process_response_body(body) do
    IO.inspect(body)

    body
    |> Poison.decode!(keys: :atoms)
  end

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

    post(url, req, [{"Content-Type", "application/json"}])
    |> fetch_body()
  end

  defp fetch_body({:ok, %HTTPoison.Response{status_code: 200, body: %{result: result}}}),
    do: {:ok, result}

  defp fetch_body(
         {:ok,
          %HTTPoison.Response{status_code: 200, body: %{error: %{code: code, message: message}}}}
       ),
       do: {:error, %{code: code, message: message}}

  defp fetch_body(res), do: res
end
