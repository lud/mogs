defmodule Mogs.Board do
  alias Supervisor, as: OTPSupervisor
  @callback load_mode() :: :sync | :async
  @callback load(id :: any, load_info :: any) :: {:ok, board :: any} | {:error, reason :: any}

  defmacro __using__(_opts) do
    board_mod = __CALLER__.module
    supervisor_name = Module.concat([board_mod, Supervisor])
    registry_name = Module.concat([board_mod, Server.Registry])
    dynsup_name = Module.concat([board_mod, Server.DynamicSupervisor])

    supervisor_ast =
      quote do
        use OTPSupervisor
        require Logger

        def start_link(init_arg) do
          Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
        end

        def init(_init_arg) do
          children = [
            {Registry, keys: :unique, name: unquote(registry_name)},
            unquote(dynsup_name)
          ]

          Supervisor.init(children, strategy: :rest_for_one)
        end
      end

    dynsup_ast =
      quote do
        use DynamicSupervisor

        def start_link(init_arg) do
          DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
        end

        @impl true
        def init(_init_arg) do
          DynamicSupervisor.init(strategy: :one_for_one)
        end
      end

    Module.create(supervisor_name, supervisor_ast, Macro.Env.location(__CALLER__))
    Module.create(dynsup_name, dynsup_ast, Macro.Env.location(__CALLER__))

    quote do
      @behaviour Mogs.Board
      # @todo On Elixir v2 before_compile check on genserver will be removed,
      # check why.
      @before_compile Mogs.Board

      defp __via__(id) do
        {:via, Registry, {unquote(registry_name), id}}
      end

      @doc false
      def start_server(opts) do
        # Any board server requires an ID
        id =
          case Keyword.fetch(opts, :id) do
            {:ok, id} ->
              id

            :error ->
              raise ArgumentError, "#{unquote(board_mod)}.start_server/1 requires an :id option"
          end

        # We set the name, module as defaults, a user that knows what she's
        # doing can override at will. We also set a default load_info as the
        # ID so it is easier to load the board state from an external source.
        defaults = [
          name: __via__(id),
          mod: __MODULE__,
          load_info: id
        ]

        opts1 = Keyword.merge(defaults, opts)

        DynamicSupervisor.start_child(
          unquote(dynsup_name),
          {Mogs.Board.Server, opts1}
        )
      end

      @doc false
      def load_mode() do
        :sync
      end

      defoverridable load_mode: 0

      def read_state(id, fun) when is_function(fun, 1) do
        GenServer.call(__via__(id), {:read_board_state, fun})
      end

      defoverridable read_state: 2
    end
  end

  defmacro __before_compile__(env) do
    unless Module.defines?(env.module, {:load, 2}) do
      message = """
      function load/1 required by behaviour Mogs.Board is not implemented \
      (in module #{inspect(env.module)}).

      This default implementation will be defined:

        def load(_id, load_info) do
          {:ok, load_info}
        end

      If no load_info option is given on #{inspect(env.module)}.start_server(opts),
      this function will receive the id defined in opts.
      """

      IO.warn(message, Macro.Env.stacktrace(env))

      quote do
        @doc false
        def load(_id, load_info) do
          {:ok, load_info}
        end

        defoverridable load: 2
      end
    end
  end
end
