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
    Igniter.Project.Deps.add_dep(igniter, busybody_dep(igniter.args.options))
  end

  defp busybody_dep(opts) do
    cond do
      opts[:git] -> {:busybody, git: opts[:git], only: :dev}
      true -> {:busybody, path: opts[:path] || "../busybody", only: :dev}
    end
  end
end
