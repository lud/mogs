defmodule Mogs.Board do
  alias Supervisor, as: OTPSupervisor
  @callback load_mode() :: :sync | :async
  @callback load(id :: any, load_info :: any) :: {:ok, board :: any} | {:error, reason :: any}

  @type board :: any

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

    # @todo remove location-keep
    quote location: :keep do
      @behaviour unquote(__MODULE__)
      # @todo On Elixir v2 before_compile check on genserver will be removed,
      # check why.
      @before_compile unquote(__MODULE__)

      def __via__(id) do
        {:via, Registry, {unquote(registry_name), id}}
      end

      @doc false
      def stop_server(id, reason \\ :normal, timeout \\ :infinity) do
        GenServer.stop(__via__(id), reason, timeout)
      end

      @doc false
      def start_server(opts) when is_list(opts) do
        unquote(__MODULE__).start_server(unquote(board_mod), unquote(dynsup_name), opts)
      end

      @doc false
      def load_mode() do
        :sync
      end

      def read_state(id) do
        read_state(id, fn state -> state end)
      end

      def read_state(id, fun) when is_function(fun, 1) do
        unquote(__MODULE__).read_state(__via__(id), fun)
      end

      def send_command(id, command) do
        unquote(__MODULE__).send_command(__via__(id), command)
      end

      def handle_command(command, board) do
        unquote(__MODULE__).handle_command(command, board)
      end

      defoverridable load_mode: 0, read_state: 2, send_command: 2, handle_command: 2
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

  def start_server(module, supervisor, opts) do
    # Any board server requires an ID
    id =
      case Keyword.fetch(opts, :id) do
        {:ok, id} ->
          id

        :error ->
          raise ArgumentError, "#{module}.start_server/1 requires an :id option"
      end

    # We set the name, module as defaults, a user that knows what she's
    # doing can override at will. We also set a default load_info as the
    # ID so it is easier to load the board state from an external source.
    defaults = [
      name: module.__via__(id),
      mod: module,
      load_info: id
    ]

    opts1 = Keyword.merge(defaults, opts)

    DynamicSupervisor.start_child(supervisor, {Mogs.Board.Server, opts1})
  end

  def read_state(name_or_pid, fun) do
    GenServer.call(name_or_pid, {:read_board_state, fun})
  end

  # We do not check the format of the command as we could pass it to a custom
  # handle_command function. It will fail server-side but send_command is
  # overridable in the custom module.
  def send_command(name_or_pid, command) do
    GenServer.call(name_or_pid, {:run_command, command})
  end

  @doc """
  Default implementation for handling commands.

  Accepts to command styles : Structs and {Module, data}.

  * If a struct is given, the struct module `run_command/2` function will be
    called with the struct itself and the board as arguments.
  * If a 2-tuple {module, data}, the module `run_command/2` will be called with
    the data and the board as arguments
  """
  def handle_command(%_{} = command, board) do
    Mogs.Board.Command.run_command(command, board)
  end

  def handle_command(command, _board) do
    raise ArgumentError, """

      Bad command format. Default handle_command/2 implementation only accepts
      struct commands and will call Mogs.Board.Command.run_command/2 with the
      given struct and board.

      Command received: #{inspect(command)}

      It is possible to define a custom handle_command/2 function in you board
      module to handle custom commands.
    """
  end

  @doc """
  Returns an empty timers structure to initialize timers in a board. This
  structure will contain the timers that commands may set on the board.

  The timers (implemented by the TimeQueue module) can be serialized (e.g with
  term_to_binary)
  """
  @spec timers :: Mogs.Board.Timers.timers()
  def timers() do
    TimeQueue.new()
  end
end
