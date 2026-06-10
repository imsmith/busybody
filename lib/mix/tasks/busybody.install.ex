defmodule Mix.Tasks.Busybody.Install do
  @shortdoc "Install the Busybody client into this Phoenix app"
  @moduledoc """
  Installs the Busybody dev directory client into a Phoenix application.

      mix busybody.install

  Adds `{:busybody, path: "../busybody", only: :dev}` and wires
  `Busybody.Client` into the supervision tree behind a
  `Code.ensure_loaded?/1` guard so prod/test compile without the dep.

  ## Options

    * `--name` - app name to register (default: OTP app name)
    * `--path` - path to busybody (default `../busybody`)
    * `--git`  - use a git dep instead of a path dep
  """

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :busybody,
      example: "mix busybody.install --name my_app",
      schema: [name: :string, path: :string, git: :string]
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    opts = igniter.args.options
    app_name = opts[:name] || to_string(Igniter.Project.Application.app_name(igniter))
    {igniter, endpoint} = endpoint_module(igniter)

    igniter
    |> Igniter.Project.Deps.add_dep(busybody_dep(opts))
    |> wire_supervision(app_name, endpoint)
  end

  defp endpoint_module(igniter) do
    {igniter, router} = Igniter.Libs.Phoenix.select_router(igniter)
    {igniter, endpoint} = Igniter.Libs.Phoenix.select_endpoint(igniter, router)
    {igniter, endpoint}
  end

  defp wire_supervision(igniter, app_name, endpoint) do
    app_module = Igniter.Project.Application.app_module(igniter)

    igniter
    |> append_children_call(app_module)
    |> add_helper(app_module, app_name, endpoint)
  end

  defp append_children_call(igniter, app_module) do
    Igniter.Project.Module.find_and_update_module!(igniter, app_module, fn zipper ->
      with {:ok, zipper} <- Igniter.Code.Function.move_to_def(zipper, :start, 2),
           {:ok, zipper} <-
             Igniter.Code.Function.move_to_function_call_in_current_scope(
               zipper,
               :=,
               2,
               fn call ->
                 Igniter.Code.Function.argument_matches_predicate?(call, 0, fn arg ->
                   match?({:children, _, ctx} when is_atom(ctx), Sourceror.Zipper.node(arg))
                 end)
               end
             ),
           {:ok, list_zipper} <- Igniter.Code.Function.move_to_nth_argument(zipper, 1) do
        if already_appended?(list_zipper) do
          {:ok, list_zipper}
        else
          {:ok,
           Sourceror.Zipper.update(list_zipper, fn list_ast ->
             quote do
               unquote(list_ast) ++ busybody_children()
             end
           end)}
        end
      else
        _ -> :error
      end
    end)
  end

  defp already_appended?(zipper) do
    match?({:++, _, [_, {:busybody_children, _, _}]}, zipper.node)
  end

  defp add_helper(igniter, app_module, app_name, endpoint) do
    Igniter.Project.Module.find_and_update_module!(igniter, app_module, fn zipper ->
      case Igniter.Code.Function.move_to_defp(zipper, :busybody_children, 0) do
        {:ok, _} ->
          {:ok, zipper}

        _ ->
          {:ok,
           Igniter.Code.Common.add_code(zipper, """
           defp busybody_children do
             if Code.ensure_loaded?(Busybody.Client) do
               [{Busybody.Client, name: "#{app_name}", endpoint: #{inspect(endpoint)}}]
             else
               []
             end
           end
           """)}
      end
    end)
  end

  defp busybody_dep(opts) do
    cond do
      opts[:git] -> {:busybody, git: opts[:git], only: :dev}
      true -> {:busybody, path: opts[:path] || "../busybody", only: :dev}
    end
  end
end
