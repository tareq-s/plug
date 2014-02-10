defmodule Plug.Builder do
  @moduledoc """
  Conveniences for building plugs.

  This module can be used into a module in order to build
  a plug stack:

      defmodule MyApp do
        use Plug.Builder

        plug :hello, upper: true

        def hello(conn, opts) do
          body = if opts[:upper], do: "WORLD", else: "world"
          conn.send_resp(200, body)
        end
      end

  `Plug.Builder` will then define a function named `call/2` that allows
  this builder to be handed to a web server or used as part of another
  stack.

  Note this module also exports a `compile/1` function for those willing
  to collect and compile their plugs manually.
  """

  @doc false
  defmacro __using__(_) do
    quote do
      import Plug.Builder, only: [plug: 1, plug: 2]
      Module.register_attribute(__MODULE__, :plugs, accumulate: true)
      @before_compile Plug.Builder
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    plugs = Module.get_attribute(env.module, :plugs)
    { conn, body } = Plug.Builder.compile(plugs)
    quote do
      def call(unquote(conn), _), do: unquote(body)
    end
  end

  @doc """
  A macro that stores a new plug.
  """
  defmacro plug(plug, opts \\ []) do
    quote do
      @plugs { unquote(plug), unquote(opts) }
    end
  end

  @doc """
  Compiles a plug stack.

  It expects a reversed stack (with the last plug coming first)
  and returns a tuple containing the reference to the connection
  as first argument and the compiled quote stack.
  """
  @spec compile([{ Plug.t, Plug.opts }]) :: { Macro.t, Macro.t }
  def compile(stack) do
    conn = quote do: conn
    { conn, Enum.reduce(stack, conn, &quote_plug(init_plug(&1), &2)) }
  end

  defp init_plug({ plug, opts }) do
    case atom_to_list(plug) do
      'Elixir.' ++ _ ->
        init_module_plug(plug, opts)
      _ ->
        init_fun_plug(plug, opts)
    end
  end

  defp init_module_plug(plug, opts) do
    opts  = plug.init(opts)
    call? = function_exported?(plug, :call, 2)
    wrap? = function_exported?(plug, :wrap, 3)

    cond do
      call? and wrap? ->
        raise ArgumentError,
          message: "#{inspect plug} plug implements both call/2 and wrap/3"
      call? ->
        { :call, plug, opts }
      wrap? ->
        { :wrap, plug, opts }
      true ->
        raise ArgumentError,
          message: "#{inspect plug} plug must implement call/2 or wrap/3"
    end
  end

  defp init_fun_plug(plug, opts) do
    { :fun, plug, opts }
  end

  defp quote_plug({ :wrap, plug, opts }, acc) do
    quote do
      unquote(plug).wrap(conn, unquote(opts), fn conn ->
        unquote(acc)
      end)
    end
  end

  defp quote_plug({ :call, plug, opts }, acc) do
    quote do
      case unquote(plug).call(conn, unquote(opts)) do
        Plug.Conn[] = conn -> unquote(acc)
        _                  -> raise "expected #{unquote(inspect plug)}.call/2 to return a Plug.Conn"
      end
    end
  end

  defp quote_plug({ :fun, plug, opts }, acc) do
    quote do
      case unquote(plug)(conn, unquote(opts)) do
        Plug.Conn[] = conn -> unquote(acc)
        _                  -> raise "expected #{unquote(inspect plug)}/2 to return a Plug.Conn"
      end
    end
  end
end