defmodule CoberturaCover do
  # ============ private functions
  defp cover_modules(module_filters) when is_map(module_filters) do
    Enum.flat_map(module_filters[:include], fn(expr) ->
      regex = "^Elixir.#{expr}"
        |> String.replace(".", "\\.")
        |> String.replace("*", ".*")
        |> Regex.compile
        |> elem(1)

      Enum.filter(:cover.modules, fn(mod) -> String.match?("#{mod}", regex) end)
    end)
  end
  defp cover_modules(_), do: :cover.modules

  defp packages(modules) do
    [{:package, [name: "", 'line-rate': 0, 'branch-rate': 0, complexity: 1], [
      classes: Enum.map(modules, fn mod ->
        class_name = inspect(mod)
        # <class branch-rate="0.634920634921" complexity="0.0"
        #  filename="PSPDFKit/PSPDFConfiguration.m" line-rate="0.976377952756"
        #  name="PSPDFConfiguration_m">

        {:ok, {_, {lines_covered, lines_uncovered}}} = :cover.analyse(mod, :coverage, :module)

        {:class,
          [
            name: inspect(mod),
            filename: Path.relative_to_cwd(mod.module_info(:compile)[:source]),
            "line-rate": lines_covered / (lines_covered + lines_uncovered), "branch-rate": 0, complexity: 1,
          ],
          [methods: methods(mod), lines: lines(mod)]
        }
      end)
    ]}]
  end

  defp methods(mod) do
    {:ok, functions} = :cover.analyse(mod, :coverage, :function)

    Enum.filter_map(
      functions,
      fn({{_, fn_name, _}, _}) ->
        !String.match?("#{fn_name}", ~r{^__.*})
      end,
      fn({{_, fn_name, fn_arity}, {lines_covered, lines_uncovered}}) ->
        {:method, [name: "#{fn_name}", signature: "#{fn_name}/#{fn_arity}", "line-rate": lines_covered / (lines_covered + lines_uncovered), "branch-rate": 0], []}
      end
    )
  end

  defp lines(mod) do
    {:ok, lines} = :cover.analyse(mod, :coverage, :line)

    lines
      |> Stream.filter(fn {{_m, line}, _hits} -> line != 0 end)
      |> Enum.map(fn {{_m, line}, {hits, _}} ->
        # <line branch="false" hits="21" number="76"/>
        {:line, [branch: false, hits: hits, number: line], []}
      end)
  end

  defp timestamp do
    {mega, seconds, micro} = :os.timestamp()
    mega * 1000000000 + seconds * 1000 + div(micro, 1000)
  end

  # ============= public functions
  def start(compile_path, opts) do
    Mix.shell.info "Cover compiling modules ... "
    _ = :cover.start

    case :cover.compile_beam_directory(compile_path |> to_char_list) do
      results when is_list(results) ->
        :ok
      {:error, _} ->
        Mix.raise "Failed to cover compile directory: " <> compile_path
    end

    fn() ->
      modules_to_cover = cover_modules(opts[:modules])

      generate_cobertura(modules_to_cover)

      if html_output = opts[:html_output], do: generate_html(html_output, modules_to_cover)
    end
  end

  def generate_html(output, modules_to_cover) do
    File.mkdir_p!(output)
    Mix.shell.info "\nGenerating cover HTML output..."
    Enum.each modules_to_cover, fn(mod) ->
      {:ok, _} = :cover.analyse_to_file(mod, '#{output}/#{mod}.html', [:html])
    end
  end

  def generate_cobertura(modules_to_cover) when is_list(modules_to_cover) do
    Mix.shell.info "\nGenerating cobertura.xml... "

    prolog = [
      ~s(<?xml version="1.0" encoding="utf-8"?>\n),
      ~s(<!DOCTYPE coverage SYSTEM "http://cobertura.sourceforge.net/xml/coverage-04.dtd">\n)
    ]

    root = {:coverage, [
        {:timestamp, timestamp()},
        {:"line-rate", 0},
        {:"lines-covered", 0},
        {:"lines-valid", 0},
        {:"branch-rate", 0},
        {:"branches-covered", 0},
        {:"branches-valid", 0},
        {:complexity, 0},
        {:version, "1.9"},
      ], [
        sources: [],
        packages: []
      ]
    }

    IO.puts "----------- root: #{inspect root}"
    report = :xmerl.export_simple([root], :xmerl_xml, prolog: prolog)
    File.write("coverage.xml", report)
  end
end
