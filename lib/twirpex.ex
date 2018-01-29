defmodule Twirpex do
  @moduledoc false
  require Logger

  defmacro __using__(opts) do
    {_, _, module_name} = Keyword.fetch!(opts, :protos_module)
    package_name = Keyword.fetch!(opts, :package_name)
    module_name = Module.concat(module_name)
    {:module, _} = Code.ensure_compiled(module_name)

    plug_quotes =
      apply(module_name, :defs, [])
      |> Enum.filter(&is_service?/1)
      |> Enum.reduce([], fn service, acc ->
        {{:service, _service_name}, rpcs} = service
        plug_quotes = create_plug_modules(rpcs, module_name)

        acc ++ plug_quotes
      end)

    server_quotes =
      apply(module_name, :defs, [])
      |> Enum.filter(&is_service?/1)
      |> Enum.reduce([], fn service, acc ->
        {{:service, service_name}, rpcs} = service
        [service_name | _] = service_name |> Module.split() |> Enum.reverse()
        quotes = create_functions(rpcs, package_name, service_name)
        acc ++ quotes
      end)
    
    client_quotes =
      apply(module_name, :defs, [])
      |> Enum.filter(&is_service?/1)
      |> Enum.reduce([], fn service, acc ->
        {{:service, service_name}, rpcs} = service
        [service_name | _] = service_name |> Module.split() |> Enum.reverse()
        client_quotes = create_client_functions(rpcs, package_name, service_name, module_name)

        acc ++ client_quotes
      end)

    plug_quotes ++
      [
        quote do
          defmodule Server do
            use Plug.Router

            plug(:match)
            plug(:dispatch)

            unquote(server_quotes)

            # match _ do
            #   send_resp(conn, 404, "oops")
            # end
          end
        end
      ] ++ [
        quote do
          defmodule Client do
            unquote(client_quotes)
          end
        end
      ]
  end

  def create_plug_modules(rpcs, module_name) do
    for {:rpc, rpc_name, request, response, _, _, _} <- rpcs do
      function_name = "new_#{Macro.underscore(to_string(rpc_name))}_server"
      plug_module_name = Module.concat(["Twirpex.Rpcs", :"#{rpc_name}"])

      quote do
        defmodule unquote(plug_module_name) do
          import Plug.Conn

          def init(opts), do: opts

          def call(conn, _opts) do
            {:ok, body, conn} = read_body(conn)

            request =
              apply(Module.concat(unquote(module_name), unquote(request)), :decode, [body])

            {:ok, response} = apply(unquote(module_name), :"#{unquote(function_name)}", [request])

            response = apply(Module.concat(unquote(module_name), unquote(response)), :encode, [response])

            conn
            |> send_resp(200, response)
          end
        end
      end
    end
  end

  def create_functions(rpcs, package_name, service_name) do
    for {:rpc, rpc_name, _request, _response, _, _, _} <- rpcs do
      plug_module_name = Module.concat([:"#{rpc_name}"])

      quote do
        match(
          "/#{unquote(package_name)}.#{unquote(service_name)}/#{unquote(rpc_name)}",
          to: Module.concat(["Twirpex.Rpcs", unquote(plug_module_name)])
        )
      end
    end
  end

  def create_client_functions(rpcs, package_name, service_name, module_name) do
    for {:rpc, rpc_name, request, response, _, _, _} <- rpcs do
      function_name = "new_#{Macro.underscore(to_string(rpc_name))}_client"
      
      quote do
        def unquote(:"#{function_name}")(url, request) do
          body = apply(Module.concat([unquote(module_name), unquote(request)]), :encode, [request])
          {:ok, resp} = HTTPoison.post("#{url}/#{unquote(package_name)}.#{unquote(service_name)}/#{unquote(rpc_name)}", body, [{"Content-Type", "application/protobuf"}])
          if resp.status_code == 200 do
            {:ok, apply(Module.concat([unquote(module_name), unquote(response)]), :decode, [resp.body])}
          else
            :error
          end
        end
      end
    end
  end

  def is_service?({{:service, _}, _}) do
    true
  end

  def is_service?(_) do
    false
  end
end
