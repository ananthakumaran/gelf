defmodule GelfBench do
  use Benchfella
  require Logger

  Logger.add_backend(Gelf)
  Logger.remove_backend(:console)
  Logger.configure(truncate: :infinity, utc_log: true)
  Logger.configure_backend(Gelf, metadata: [:line, :module])

  def random_string(size) do
    :crypto.strong_rand_bytes(size) |> :base64.encode_to_string |> to_string
  end

  bench "str size 100", [str: random_string(100)] do
    Logger.info str
  end

  bench "str size 1000", [str: random_string(1000)] do
    Logger.warn str
  end

  bench "str size 10000", [str: random_string(10000)] do
    Logger.error str
  end
end
