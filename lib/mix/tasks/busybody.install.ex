defmodule Mix.Tasks.Busybody.Install do
  @moduledoc """
  Installs the Busybody client into a Phoenix application.

  Run from inside your Phoenix project:

      mix busybody.install

  This task:

    1. Adds `{:busybody, path: "../busybody", only: :dev}` to your deps
       (if not already present)
    2. Adds `Busybody.Client` to your supervision tree with a
       `Code.ensure_loaded?/1` guard so it only runs when the dep
       is available

  ## Options

    * `--name` - app name to register (defaults to your OTP app name)
    * `--path` - path to busybody (defaults to `../busybody`)
    * `--git`  - use a git dep instead of a path dep

  ## Examples

      mix busybody.install
      mix busybody.install --name my_cool_app
      mix busybody.install --git https://github.com/imsmith/busybody.git

  """

  @shortdoc "Install Busybody client into this Phoenix app"

  use Mix.Task

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [name: :string, path: :string, git: :string]
      )

    app_name = opts[:name] || to_string(Mix.Project.config()[:app])
    dep_source = dep_source(opts)

    mix_file = Path.join(File.cwd!(), "mix.exs")
    app_file = find_application_ex()
    endpoint = infer_endpoint()

    patch_mix_exs(mix_file, dep_source)
    patch_application_ex(app_file, app_name, endpoint)

    Mix.shell().info("""

    Done! Next steps:

      1. Run `mix deps.get`
      2. Start busybody: `cd #{busybody_path(opts)} && mix phx.server`
      3. Start this app: `mix phx.server`
      4. Visit http://localhost:5150
    """)
  end

  # -- mix.exs patching --

  defp patch_mix_exs(mix_file, dep_source) do
    contents = File.read!(mix_file)

    if contents =~ ":busybody" do
      Mix.shell().info("mix.exs already contains :busybody dep, skipping")
    else
      new_contents = inject_dep(contents, dep_source)
      File.write!(mix_file, new_contents)
      Mix.shell().info("Added :busybody dep to mix.exs")
    end
  end

  defp inject_dep(contents, dep_string) do
    # Find the last line before the closing ] of the deps list.
    # The deps list ends with `    ]` on its own line.
    # We insert our dep before that closing bracket.
    #
    # We also ensure the previous dep has a trailing comma.
    lines = String.split(contents, "\n")

    # Find the deps function and its closing bracket
    {in_deps, bracket_idx} = find_deps_bracket(lines)

    unless in_deps do
      Mix.raise("""
      Could not find deps function in mix.exs.
      Add this manually to your deps:

          #{dep_string}
      """)
    end

    # Ensure the line before the bracket ends with a comma
    prev_idx = bracket_idx - 1
    prev_line = Enum.at(lines, prev_idx)

    lines =
      if String.trim(prev_line) != "" and not String.ends_with?(String.trim_trailing(prev_line), ",") do
        List.replace_at(lines, prev_idx, String.trim_trailing(prev_line) <> ",")
      else
        lines
      end

    # Insert the new dep
    lines
    |> List.insert_at(bracket_idx, "      #{dep_string}")
    |> Enum.join("\n")
  end

  defp find_deps_bracket(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce({false, nil, 0}, fn {line, idx}, {in_deps, found, depth} ->
      cond do
        found ->
          {in_deps, found, depth}

        not in_deps and line =~ ~r/defp? deps do/ ->
          {true, nil, depth}

        in_deps and line =~ ~r/\[/ ->
          new_depth = depth + count_char(line, ?[) - count_char(line, ?])

          if new_depth <= 0 do
            {true, idx, 0}
          else
            {true, nil, new_depth}
          end

        in_deps and line =~ ~r/\]/ ->
          new_depth = depth + count_char(line, ?[) - count_char(line, ?])

          if new_depth <= 0 do
            {true, idx, 0}
          else
            {true, nil, new_depth}
          end

        true ->
          {in_deps, found, depth}
      end
    end)
    |> then(fn {in_deps, bracket_idx, _} -> {in_deps, bracket_idx} end)
  end

  defp count_char(string, char) do
    string |> to_charlist() |> Enum.count(&(&1 == char))
  end

  # -- application.ex patching --

  defp patch_application_ex(app_file, app_name, endpoint) do
    contents = File.read!(app_file)

    if contents =~ "Busybody.Client" do
      Mix.shell().info("application.ex already references Busybody.Client, skipping")
    else
      new_contents =
        contents
        |> inject_children_concat()
        |> inject_helper_function(app_name, endpoint)

      File.write!(app_file, new_contents)
      Mix.shell().info("Added Busybody.Client to supervision tree in #{app_file}")
    end
  end

  defp inject_children_concat(contents) do
    # Find `    ]\n\n` after the children list — the ] is at 4-space indent,
    # followed by a blank line or a line starting with spaces and # or opts or Supervisor
    case Regex.replace(
           ~r/(    \])\n(\n\s+(#|opts|Supervisor))/,
           contents,
           "\\1 ++ busybody_children()\n\\2",
           global: false
         ) do
      ^contents ->
        Mix.raise("Could not find children list in application.ex. Add Busybody.Client manually.")

      updated ->
        updated
    end
  end

  defp inject_helper_function(contents, app_name, endpoint) do
    helper = """

      defp busybody_children do
        if Code.ensure_loaded?(Busybody.Client) do
          [{Busybody.Client, name: "#{app_name}", endpoint: #{endpoint}}]
        else
          []
        end
      end
    """

    # Insert before the final `end` of the module
    String.replace(contents, ~r/\nend\s*\z/, "\n" <> helper <> "end\n")
  end

  # -- option helpers --

  defp dep_source(opts) do
    cond do
      opts[:git] ->
        "{:busybody, git: \"#{opts[:git]}\", only: :dev}"

      true ->
        path = opts[:path] || "../busybody"
        "{:busybody, path: \"#{path}\", only: :dev}"
    end
  end

  defp busybody_path(opts) do
    if opts[:git], do: "busybody", else: opts[:path] || "../busybody"
  end

  defp find_application_ex do
    app = Mix.Project.config()[:app]
    path = Path.join(["lib", to_string(app), "application.ex"])

    unless File.exists?(path) do
      Mix.raise("Could not find #{path}")
    end

    path
  end

  defp infer_endpoint do
    app = Mix.Project.config()[:app]

    app
    |> to_string()
    |> Macro.camelize()
    |> then(&"#{&1}Web.Endpoint")
  end
end
