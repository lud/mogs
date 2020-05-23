defmodule Mogs.Board do
  use TODO
  alias Mogs.Board.Command
  @callback load(id :: any, load_info :: any) :: {:ok, board :: any} | {:error, reason :: any}
  @callback handle_update(board :: any) :: {:ok, board :: any} | {:stop, reason :: any}
  @callback handle_error(reason :: any, board :: any) ::
              {:ok, board :: any} | {:stop, reason :: any}
  @todo "Define callbacks in different 'plugin' behaviours"
  @callback handle_add_player(board :: any, player_id :: any, data :: any) ::
              {:ok, board :: any} | {:error, reason :: any}
  @callback handle_remove_player(board :: any, player_id :: any, reason :: any) ::
              {:ok, board :: any} | {:stop, reason :: any}

  @callback handle_command(command :: any, board :: any) :: Mogs.Board.Command.Result.t()
  @callback handle_timer(command :: any, board :: any) :: Mogs.Board.Command.Result.t()
  @type board :: any

  @doc """

  ### Options

  #### Board

  - `:load_mode` – Allowed values are `:sync` and `:async`. Sets
    wether the `c:load/2` callback will be called during the board
    server initialization (`:sync`) or after initialization. Defaults
    to `:sync`.

  #### Services

  Those options allow to define the generated modules or services
  associated to a board module. If a module would be generated, the
  option sets both the module name and the process registration name.

  Setting an option to `false` or `nil` will disable the corresponding
  feature and no module will be generated during compilation and/or no
  process will be started nor registered during runtime.

  - `:supervisor` – The name for a generated `Supervisor` module that
    will supervise other components (such as registry, servers
    supervisor). Defaults to `__MODULE__.Supervisor`.
  - `:registry` – The registration name for the `Registry` of
    `Mogs.Board.Server` processes handling boards. Defaults to
    `__MODULE__.Server.Registry`.
  - `:server_sup` – The name for the generated `DynamicSupervisor`
    module that will supervise each `Mogs.Board.Server` server
    process. Defaults to `__MODULE__.Server.DynamicSupervisor`.
  """
  defmacro __using__(opts) do
    board_mod = __CALLER__.module

    # using_schema = %{
    #   load_mode: [inclusion: [:sync, :async], default: :sync],
    #   supervisor: [type: :atom, default: Module.concat([board_mod, Supervisor])],
    #   registry: [type: :atom, default: Module.concat([board_mod, Server.Registry])],
    #   server_sup: [type: :atom, default: Module.concat([board_mod, Server.DynamicSupervisor])],
    #   tracker: [
    #     default: false,
    #     required: true
    #   ]
    # }

    # opts = KeywordValidator.validate!(opts, using_schema)

    # supervisor_name = Keyword.fetch!(opts, :supervisor)

    todo "Move code to a Mogs.Board.Supervisor module and here just forward the child_spec call"

    # if !!supervisor_name do
    #   supervisor_ast =
    #     quote location: :keep, bind_quoted: [board_mod: board_mod] do
    #       @board_mod board_mod

    #       def child_spec(opts) do
    #         children = @board_mod.__mogs__(:services)

    #         default = %{
    #           id: __MODULE__,
    #           start:
    #             {Supervisor, :start_link, [children, [strategy: :rest_for_one, name: __MODULE__]]},
    #           type: :supervisor
    #         }

    #         Supervisor.child_spec(default, opts)
    #       end
    #     end

    #   Module.create(supervisor_name, supervisor_ast, Macro.Env.location(__CALLER__))
    # end

    todo "1.0.0": "remove location-keep"

    todo """
    On Elixir v2 the before_compile check on genserver for
    the init function presence will be removed, check why.
    """

    [
      create_attributes(opts),
      create_supervisor(opts),
      create_functions(opts)
    ]
  end

  defp create_attributes(opts) do
    quote location: :keep, bind_quoted: [opts: opts, __mogs__: __MODULE__] do
      @__mogs__ __mogs__
      @__mogs__load_mode Mogs.Board.check_opt(opts, :load_mode, :sync)
      @__mogs__supervisor Mogs.Board.check_opt(opts, :supervisor, __MODULE__.Supervisor)
      @__mogs__registry Mogs.Board.check_opt(opts, :registry, __MODULE__.Server.Registry)
      @__mogs__server_sup Mogs.Board.check_opt(
                            opts,
                            :server_sup,
                            __MODULE__.Server.DynamicSupervisor
                          )
      @__mogs__tracker_opts Mogs.Board.check_opt(opts, :tracker)
      @__mogs__is_tracking? !!@__mogs__tracker_opts
      @__mogs__has_registry? !!@__mogs__registry
      @__mogs__has_supervisor? !!@__mogs__supervisor
      @__mogs__has_server_sup? !!@__mogs__server_sup

      Module.register_attribute(__MODULE__, :__mogs__service, accumulate: true)

      if @__mogs__has_registry? do
        @__mogs__service {Registry, keys: :unique, name: @__mogs__registry}
      end

      if @__mogs__has_server_sup? do
        @__mogs__service {DynamicSupervisor, strategy: :one_for_one, name: @__mogs__server_sup}
      end

      @__mogs__services Module.get_attribute(__MODULE__, :__mogs__service, [])
                        |> :lists.reverse()
    end
  end

  defp create_supervisor(opts) do
    quote location: :keep, bind_quoted: [] do
      if @__mogs__has_supervisor? do
        supervisor_ast =
          quote location: :keep, bind_quoted: [board_mod: __MODULE__] do
            @board_mod board_mod

            def child_spec(opts) do
              children = @board_mod.__mogs__(:services)

              default = %{
                id: __MODULE__,
                start:
                  {Supervisor, :start_link,
                   [children, [strategy: :rest_for_one, name: __MODULE__]]},
                type: :supervisor
              }

              Supervisor.child_spec(default, opts)
            end
          end

        Module.create(@__mogs__supervisor, supervisor_ast, Macro.Env.location(__ENV__))
      end
    end
  end

  defp create_functions(opts) do
    quote location: :keep do
      @behaviour @__mogs__

      @before_compile @__mogs__

      def __mogs__(:services), do: @__mogs__services
      def __mogs__(:load_mode), do: @__mogs__load_mode

      if @__mogs__has_registry? do
        def __name__(pid) when is_pid(pid), do: pid
        def __name__(id), do: {:via, Registry, {@__mogs__registry, id}}
      end

      if @__mogs__has_server_sup? do
        @doc """
        Starts a Mogs.Board handled by the callback module #{inspect(__MODULE__)}
        """
        def start_server(id, opts \\ []) when is_list(opts) do
          opts =
            if @__mogs__has_registry? do
              Keyword.put_new(opts, :name, __name__(id))
            else
              opts
            end

          opts = Keyword.put_new(opts, :tracker, @__mogs__tracker_opts)
          @__mogs__.start_server(__MODULE__, @__mogs__server_sup, id, opts)
        end
      end

      def stop_server(id, reason \\ :normal, timeout \\ :infinity) do
        GenServer.stop(__name__(id), reason, timeout)
      end

      if @__mogs__has_registry? do
        def whereis_server(id) do
          Registry.whereis_name({@__mogs__registry, id})
        end

        def alive?(id) do
          case whereis_server(id) do
            :undefined -> false
            pid -> true
          end
        end
      end

      def read_state(id) do
        read_state(id, fn state -> state end)
      end

      def read_state(id, fun) when is_function(fun, 1) do
        @__mogs__.read_state(__name__(id), fun)
      end

      def send_command(id, command) do
        @__mogs__.send_command(__name__(id), command)
      end

      @doc """
      The `player_id` and `data` arguments can be anything and will
      be passed to your board `c:handle_add_player/3` callback.

      #### If the tracker feature is enabled.

      Although `player_id` and `data` can be anything, `player_id`
      will be used to identify an unique player and should be kept
      minimal.

      If called with 3 arguments, the calling process pid will be
      tracked. Since player are considered "lefters" after a
      timeout, it is fine to initialize the tracking with a short
      living process (e.g. from a Phoenix controller). On the other
      end it is strongly unadvised to track long living processes
      that do not "belong" to a single player.

      The pid to track can be set as the 4th argument.
      """
      if @__mogs__is_tracking? do
        def add_player(id, player_id, data, track \\ self())
      else
        def add_player(id, player_id, data, track \\ nil)
      end

      def add_player(id, player_id, data, pid) do
        @__mogs__.add_player(__name__(id), player_id, data, pid)
      end

      if @__mogs__is_tracking? do
        def remove_player(id, player_id, reason, clear_tracking? \\ true)
      else
        def remove_player(id, player_id, reason, clear_tracking? \\ false)
      end

      def remove_player(id, player_id, reason, clear_tracking?) do
        @__mogs__.remove_player(__name__(id), player_id, reason, clear_tracking?)
      end

      if @__mogs__is_tracking? do
        @doc """
        Add a pid to the players tracking system. Unlinke add_player, it will
        no call your `c:handle_add_player/3` callback, nor any other callback.
        """
        def track_player(id, player_id, pid \\ self())

        def track_player(id, player_id, pid) when is_pid(pid) do
          @__mogs__.track_player(__name__(id), player_id, pid)
        end
      end

      @doc false
      def handle_command(command, board) do
        @__mogs__.__handle_command__(command, board)
      end

      @doc false
      def handle_timer(timer, board) do
        @__mogs__.__handle_timer__(timer, board)
      end

      @doc false
      def handle_error(_error, board) do
        {:ok, board}
      end

      defoverridable read_state: 2,
                     send_command: 2,
                     handle_command: 2,
                     handle_error: 2
    end
  end

  @doc """
  Validates a Mogs.Board option. raise if the option is not valid or
  is unknown. Returns the option value or a default value if the 
  option supports it.

  This function is intended to be called at compile time.
  """

  def check_opt(opts, key, default \\ nil)

  def check_opt(opts, key, default) do
    v_opt(key, Keyword.get(opts, key, default))
  end

  @known_opts ~w(tracker load_mode supervisor)a
  @todo "v_opt is a bad name"

  defp v_opt(:load_mode, mode) when mode in [:sync, :async] do
    mode
  end

  defp v_opt(key, module)
       when (is_atom(module) or is_nil(module)) and key in [:supervisor, :registry, :server_sup] do
    module
  end

  defp v_opt(:tracker, nil) do
    nil
  end

  defp v_opt(:tracker, opts) when is_list(opts) do
    Mogs.Players.Tracker.validate_opts!(opts)
  end

  defp v_opt(key, nil) when key in @known_opts do
    raise ArgumentError, "The option #{inspect(key)} is required"
  end

  defp v_opt(key, value) when key in @known_opts do
    raise ArgumentError, "Incorrect value for option #{inspect(key)}: #{inspect(value)}"
  end

  defp v_opt(key, _) do
    raise ArgumentError, "The option #{inspect(key)} is unknown"
  end

  defmacro __before_compile__(env) do
    [
      unless Module.defines?(env.module, {:load, 2}) do
        message = """
        function load/1 required by behaviour Mogs.Board is not implemented \
        (in module #{inspect(env.module)}).

        This default implementation will be defined:

          def load(_id, load_info) do
            {:ok, load_info}
          end

        If no :load_info option is given on #{inspect(env.module)}.start_server(id, opts), \
        load_info will be nil.
        """

        IO.warn(message, Macro.Env.stacktrace(env))

        quote do
          @doc false
          def load(_id, load_info) do
            {:ok, load_info}
          end

          defoverridable load: 2
        end
      end,
      unless Module.defines?(env.module, {:handle_update, 1}) do
        message = """
        function handle_update/1 required by behaviour Mogs.Board is \
        not implemented (in module #{inspect(env.module)}).

        This default implementation will be defined:

          def handle_update(board) do
            {:ok, board}
          end
        """

        IO.warn(message, Macro.Env.stacktrace(env))

        quote do
          @doc false
          def handle_update(board) do
            {:ok, board}
          end

          defoverridable handle_update: 1
        end
      end,
      unless Module.defines?(env.module, {:__name__, 1}) do
        message = """
        Registry service is disabled for #{inspect(env.module)}

        Board processes name default to nil according to the \
        following implementation that was injected in your module:

          def __name__(pid) when is_pid(pid) do
            pid
          end

          def __name__(board_id) do
            nil
          end

        Please define your own implementation to suppress this
        warning. You can simply copy this one if you do not need name
        registration for your boards.
        """

        IO.warn(message, Macro.Env.stacktrace(env))

        quote do
          @doc false
          def __name__(pid) when is_pid(pid) do
            pid
          end

          def __name__(board_id) do
            nil
          end

          defoverridable __name__: 1
        end
      end
    ]
  end

  @todo "Move options validations into start_link in server"
  def start_server(module, supervisor, id, opts) do
    opts_schema = %{
      mod: [default: module],
      load_info: [default: nil],
      name: [],
      timers: [type: :boolean, default: false],
      tracker: [required: false, default: nil]
    }

    with {:ok, opts} <- KeywordValidator.validate(opts, opts_schema) do
      DynamicSupervisor.start_child(supervisor, {Mogs.Board.Server, [{:id, id} | opts]})
    end
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

  @doc false
  def __handle_command__(%_struct{} = command, board) do
    Command.run_command(command, board)
  end

  def __handle_command__(command, _board) do
    raise ArgumentError, """

      Bad command format. Default handle_command/2 implementation only
      accepts struct commands and will call
      Mogs.Board.Command.run_command/2 with the given struct and
      board.

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

  def add_player(name_or_pid, player_id, data, pid) when is_pid(pid) or is_nil(pid) do
    GenServer.call(name_or_pid, {:add_player, player_id, data, pid})
  end

  def remove_player(name_or_pid, player_id, reason, clear_tracking?) do
    GenServer.call(name_or_pid, {:remove_player, player_id, reason, clear_tracking?})
  end

  def track_player(name_or_pid, player_id, pid) when is_pid(pid) do
    GenServer.call(name_or_pid, {:track_player, player_id, pid})
  end
end
