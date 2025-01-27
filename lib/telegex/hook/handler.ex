defmodule Telegex.Hook.Handler do
  @moduledoc """
  Generate your webhook handler, which includes a supervisor with a Plug-based child.
  """

  defmacro __using__(_) do
    quote do
      @behaviour unquote(__MODULE__)

      use Supervisor

      alias Telegex.Hook.Adapter

      require Logger

      def start_link(_) do
        config = on_boot()

        config =
          if config.on_update do
            config
          else
            %{config | on_update: &on_update/1}
          end

        children = [
          Adapter.impl().child_spec(config)
        ]

        opts = [strategy: :one_for_one, name: unquote(__CALLER__.module).Supervisor]
        Supervisor.start_link(children, opts)
      end

      @impl Supervisor
      def init(state) do
        {:ok, state}
      end

      @impl unquote(__MODULE__)
      def on_boot, do: %Telegex.Hook.Config{}

      @impl unquote(__MODULE__)
      def on_update(_update) do
        Logger.warning(
          "New update from Telegram Bot API Server, but `on_update/1` is not implemented"
        )
      end

      defoverridable on_boot: 0, on_update: 1
    end
  end

  @callback on_boot :: Telegex.Hook.Config.t()
  @callback on_update(Telegex.Type.Update.t()) :: :ok | Telegex.Chain.result()
end
