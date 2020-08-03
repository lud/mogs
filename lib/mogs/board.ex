defmodule Mogs.Board do
  use TODO
  alias Mogs.Board.Command
  @callback server_name(id :: pid | any) :: pid() | GenServer.name()
  @callback load(id :: any, load_info :: any) :: {:ok, board :: any} | {:error, reason :: any}
  @callback load(id :: any, load_info :: any) :: {:ok, board :: any} | {:error, reason :: any}
  @callback handle_command(command :: any, board :: any) :: Mogs.Board.Command.Result.t()
  @callback handle_update(board :: any) :: {:ok, board :: any} | {:stop, reason :: any}
  @callback handle_error(reason :: any, board :: any) ::
              {:ok, board :: any} | {:stop, reason :: any}
  @todo "Define callbacks in different 'plugin' behaviours"
  @callback handle_add_player(board :: any, player_id :: any, data :: any) ::
              {:ok, board :: any} | {:error, reason :: any}
  @callback handle_remove_player(board :: any, player_id :: any, reason :: any) ::
              {:ok, board :: any} | {:stop, reason :: any}

  @callback handle_timer(command :: any, board :: any) :: Mogs.Board.Command.Result.t()

  @type board :: any
  @type start_options :: Keyword.t()

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)
      require Mogs.Board.Callbacks
      Mogs.Board.Callbacks.defaults()
    end
  end

  @todo "validate name option format"

  @start_opts_schema [
    name: [
      doc: """
      Will be set as `module.server_name(id)` if not set. `c:server_name/1` can
      return `nil` to disable process registration. 
      """
    ],
    load_mode: [
      type: {:one_of, [:sync, :async]},
      doc: """
      Sets the server data initialization mode.
          - If `:sync`, the `c:load/2` callback will be set during the board
            initialization, before it returns to the process calling `boot/3`.
          - If `:async`, the callback will be called afterwards.
          -
      """,
      default: :sync
    ],
    load_info: [
      doc: """
      Data that will be passed to `c:load/2` as the second argument (the first
      argument being the `id`). It should be the minimum information required to
      load the board data on boot, since this value will be kept in memory by
      the supervisor to be able to restart the process in case of crash.
      """,
      default: nil
    ],
    timers: [
      type: :boolean,
      default: false,
      doc: """
      A flag that enables handling timers in the board. When `true`, the board
      data managed by the server (initially returned by `c:load/2`) must implement
      the `Mogs.Timers.Store` protocol.
      """
    ],
    tracker: [
      default: nil,
      type: :non_empty_keyword_list,
      keys: Mogs.Players.Tracker.opts_schema(),
      doc: """
      Options to configure the players tracker implemented by
      `Mogs.Players.Tracker`. Set to `nil` to disable players tracking.
      """
    ]
  ]

  @full_start_opts_schema [
                            module: [
                              type: :atom,
                              required: true
                            ],
                            id: [
                              required: true
                            ]
                          ] ++ @start_opts_schema

  @doc """
  Starts a board implemented by the given module under the default supervisor:
  `Mogs.Board.Supvervisor`

  ### Options

  #{NimbleOptions.docs(@start_opts_schema)}
  """
  @spec boot(module :: atom, id :: any, opts :: start_options()) ::
          DynamicSupervisor.on_start_child()
  def boot(module, id, opts \\ []) when is_atom(module) and is_list(opts) do
    name =
      case Keyword.fetch(opts, :name) do
        :error -> module.server_name(id)
        {:ok, name} -> name
      end

    opts = [{:module, module}, {:id, id}, {:name, name} | opts]

    DynamicSupervisor.start_child(Mogs.Board.DynamicSupervisor, {__MODULE__, opts})
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient
    }
  end

  def start_link(opts) when is_list(opts) do
    case NimbleOptions.validate(opts, @full_start_opts_schema) do
      {:ok, opts} -> __MODULE__.Server.start_link(opts)
      other -> other
    end
  end

  def stop(module, id) when is_atom(module) do
    GenServer.stop(module.server_name(id))
  end

  def read_state(module, id, fun) when is_atom(module) and is_function(fun, 1) do
    read_state(module.server_name(id), fun)
  end

  def read_state(name_or_pid, fun) when is_function(fun, 1) do
    GenServer.call(name_or_pid, {:read_board_state, fun})
  end

  def get_state(module, id) when is_atom(module) do
    read_state(module, id, & &1)
  end

  def send_command(module, id, command) when is_atom(module) do
    send_command(module.server_name(id), command)
  end

  def send_command(name_or_pid, command) do
    GenServer.call(name_or_pid, {:run_command, command})
  end

  @doc false
  def __handle_command__(%_struct{} = command, board) do
    Command.run_command(command, board)
  end

  def __handle_command__(command, _board) do
    raise ArgumentError, """

      Bad command format. Default handle_command/2 implementation only accepts
      structs and will call Mogs.Board.Command.run_command/2 with the given
      struct and board.

      Command received: #{inspect(command)}

      It is possible to define a custom handle_command/2 function in
      you board module to handle custom commands.
    """
  end

  @doc false
  def __handle_timer__({:mogs_command_timer, command_mod, data}, board) do
    Command.run_timer(command_mod, data, board)
  end

  def __handle_timer__(timer, _board) do
    raise ArgumentError, """

      Bad timer format. Default handle_timer/2 implementation only
      accepts tuples like `{:mogs_command_timer, command_mod, data}`
      where `command_mod` is a module that exports a handle_timer/2
      function.

      Timer received: #{inspect(timer)}

      It is possible to define a custom handle_timer/2 function in you
      board module to handle custom timers.
    """
  end

  def add_player(module, id, player_id, data) when is_atom(module) do
    add_player(module.server_name(id), player_id, data)
  end

  def add_player(name_or_pid, player_id, data) do
    GenServer.call(name_or_pid, {:add_player, player_id, data})
  end

  def remove_player(module, id, player_id, reason) when is_atom(module) do
    remove_player(module.server_name(id), player_id, reason)
  end

  def remove_player(name_or_pid, player_id, reason) do
    GenServer.call(name_or_pid, {:remove_player, player_id, reason})
  end

  def track_player(module, id, player_id, pid) when is_atom(module) and is_pid(pid) do
    track_player(module.server_name(id), player_id, pid)
  end

  def track_player(name_or_pid, player_id, pid) when is_pid(pid) do
    GenServer.call(name_or_pid, {:track_player, player_id, pid})
  end

  def alive?(module, id) do
    case GenServer.whereis(module.server_name(id)) do
      nil -> false
      _ -> true
    end
  end
end
