defmodule Gelf.Mixfile do
  use Mix.Project

  @version "0.1.0"

  def project do
    [app: :gelf,
     version: @version,
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     package: package(),
     docs: docs(),
     deps: deps()]
  end

  def application do
    [applications: [:logger]]
  end

  defp deps do
    [{:poison, "~> 1.5 or ~> 2.0"},
     {:benchfella, "~> 0.3.0", only: :dev},
     {:exprof, "~> 0.2.0", only: :dev},
     {:ex_doc, "~> 0.12", only: :dev},]
  end

  defp package do
    %{licenses: ["MIT"],
      links: %{"Github" => "https://github.com/ananthakumaran/gelf"},
      maintainers: ["ananthakumaran@gmail.com"]}
  end

  defp docs do
    [source_url: "https://github.com/ananthakumaran/gelf",
     source_ref: "v#{@version}",
     main: Gelf,
     extras: ["README.md"]]
  end
end
