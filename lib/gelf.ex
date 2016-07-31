defmodule Gelf do
  @moduledoc """
  """

  use GenEvent

  defstruct [level: nil, host: nil, port: nil, app: nil, sock: nil, address: nil, compress: nil, metadata: nil]

  def init(__MODULE__) do
    {:ok, sock} = :gen_udp.open(0, [active: false])
    state = configure([], %__MODULE__{})
    {:ok, address} = :inet.getaddr(state.host, :inet)
    {:ok, %{state | sock: sock, address: address}}
  end

  def handle_call({:configure, options}, state) do
    {:ok, :ok, configure(options, state)}
  end

  def handle_event({_level, gl, _event}, state) when node(gl) != node() do
    {:ok, state}
  end
  def handle_event({level, _gl, _event}, %{level: :error} = state)
  when level == :debug or level == :info or level == :warn do
    {:ok, state}
  end
  def handle_event({level, _gl, _event}, %{level: :warn} = state)
  when level == :debug or level == :info do
    {:ok, state}
  end
  def handle_event({level, _gl, _event}, %{level: :info} = state)
  when level == :debug do
    {:ok, state}
  end

  def handle_event({level, _gl, {Logger, msg, ts, md}}, state) do
    log(level, msg, ts, md, state)
    {:ok, state}
  end

  def handle_event(:flush, state) do
    {:ok, state}
  end

  def handle_event(_, state) do
    {:ok, state}
  end

  defp configure(options, state) do
    config =
      Application.get_env(:logger, __MODULE__, [])
      |> Keyword.merge(options)

    Application.put_env(:logger, __MODULE__, config)

    level = Keyword.get(config, :level)
    port = Keyword.get(config, :port, 12201)
    host = Keyword.get(config, :host, 'localhost')
    compress = Keyword.get(config, :compress, :zlib)
    host = if is_binary(host), do: String.to_char_list(host), else: host
    app = Keyword.get(config, :app, to_string(node()))
    metadata = Keyword.get(config, :metadata, [])
    %{state | level: level, port: port, host: host, app: app, compress: compress, metadata: metadata}
  end

  defp log(level, msg, ts, md, state = %{app: app, address: address, port: port, sock: sock, compress: compress_method}) do
    build_message(app, level, msg, ts, filter_metadata(md, state))
    |> compress(compress_method)
    |> chunk
    |> Enum.map(&send_message(&1, sock, address, port))
  end

  defp build_message(app, level, message, ts, md) do
    utf_message = IO.chardata_to_string(message)
    msg = Map.merge(%{
      "version": "1.1",
      "timestamp": epoch(ts),
      "level": level_number(level),
      "host": app,
      "short_message": String.slice(utf_message, 0..79),
    }, md)
    msg = if byte_size(utf_message) > 80 do
      Map.put(msg, "message", utf_message)
    else
      msg
    end
    Poison.encode_to_iodata!(msg)
  end

  defp filter_metadata(md, %{metadata: allowed}) do
    Enum.filter_map(md, fn {k, _v} -> k in allowed end, fn {k, v} -> {"_" <> to_string(k), v} end)
    |> Enum.into(%{})
  end

  defp compress(data, :zlib), do: :zlib.compress(data)
  defp compress(data, :gzip), do: :zlib.gzip(data)
  defp compress(data, :none), do: data

  defp level_number(:debug), do: 7
  defp level_number(:info), do: 6
  defp level_number(:warn), do: 4
  defp level_number(:error), do: 3

  @start :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})
  defp epoch({d, {h, m, s, u}}) do
    Integer.to_string(:calendar.datetime_to_gregorian_seconds({d, {h, m, s}}) - @start) <> "." <> Integer.to_string(u) |> Float.parse |> elem(0)
  end

  defp send_message(message, sock, address, port) do
    :gen_udp.send(sock, address, port, message)
  end

  @chunk_size Keyword.get(Application.get_env(:logger, __MODULE__, []), :chunk_size, 8192 - 48)
  defp chunk(message) when byte_size(message) <= @chunk_size do
    [message]
  end
  defp chunk(message) do
    break(message, [])
  end

  @part_size @chunk_size - 12
  defp break(<< part::binary-size(@part_size), rest::binary >> = message, parts) when byte_size(message) > @part_size do
    break(rest, [part | parts])
  end
  defp break(message, parts) do
    parts = [message | parts]
    parts_count = Enum.count(parts)
    message_id = :crypto.strong_rand_bytes(8)
    parts
    |> Enum.reverse
    |> Enum.with_index
    |> Enum.map(fn ({part, index}) ->
    [<<0x1e, 0x0f, message_id::binary-size(8), index, parts_count>>, part]
    end)
  end
end
