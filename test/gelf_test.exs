defmodule UDPServer do
  use GenServer

  def start_link() do
    GenServer.start(__MODULE__, [], name: __MODULE__)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  def messages() do
    GenServer.call(__MODULE__, :messages)
  end

  def init([]) do
    {:ok, sock} = :gen_udp.open(12201, [{:active, true}, :binary, {:recbuf, 8192*10}])
    {:ok, %{sock: sock, messages: [], chunks: %{}}}
  end

  def handle_call(:messages, _from, state = %{messages: messages}) do
    {:reply, messages, %{state | messages: []}}
  end

  def handle_info({:udp, _socket, _ip, _port, packet}, state) do
    {:noreply, decode_messages(packet, state)}
  end

  def terminate(_reason, %{sock: sock}) do
    if sock do
      :ok = :gen_udp.close(sock)
    end
  end

  defp decode_messages(<<0x1e, 0x0f, message_id::binary-size(8), index, chunk_count, chunk::binary>>, state = %{chunks: chunks}) do
    received = if Map.has_key?(chunks, message_id) do
      Map.get(chunks, message_id)
    else
      Enum.map(1..chunk_count, fn _ -> 0 end)
    end
    received = List.replace_at(received, index, chunk)

    if Enum.all?(received, &is_binary/1) do
      decode_messages(IO.iodata_to_binary(received), %{state | chunks: Map.pop(chunks, message_id)})
    else
      %{state | chunks: Map.put(chunks, message_id, received)}
    end
  end

  defp decode_messages(packet = <<0x78, compression, _rest::binary>>, state = %{messages: messages})
  when compression == 0x01 or compression == 0x9c or compression == 0xda do
    message = :zlib.uncompress(packet)
    |> Poison.decode!
    %{state | messages: messages ++ [message]}
  end

  defp decode_messages(packet = <<0x1f, 0x8b, _rest::binary>>, state = %{messages: messages}) do
    message = :zlib.gunzip(packet)
    |> Poison.decode!
    %{state | messages: messages ++ [message]}
  end

  defp decode_messages(packet, state = %{messages: messages}) do
    message = Poison.decode!(packet)
    %{state | messages: messages ++ [message]}
  end
end

defmodule GelfTest do
  use ExUnit.Case, async: false
  require Logger

  defmacro assert_messages(messages) do
    quote do
      Process.sleep(50)
      assert unquote(messages) = UDPServer.messages
    end
  end

  defmacro assert_message(message) do
    quote do: assert_messages([unquote(message)])
  end


  setup_all do
    Logger.add_backend(Gelf)
    Logger.remove_backend(:console)
    Logger.configure(truncate: :infinity)
    :ok
  end

  setup context do
    Application.put_env(:logger, Gelf, [])
    if config = context[:logger] do
      Logger.configure_backend(Gelf, config)
    else
      Logger.configure_backend(Gelf, [])
    end
    {:ok, _} = UDPServer.start_link
    on_exit fn ->
      UDPServer.stop
    end
    :ok
  end

  test "logs everything by default" do
    Logger.debug "hello"
    assert_message %{"host" => "nonode@nohost", "level" => 7, "short_message" => "hello", "timestamp" => timestamp, "version" => "1.1"}
    assert is_float(timestamp)
  end

  @tag logger: [level: :warn]
  test "level config" do
    Logger.info "info"
    assert_messages []
    Logger.warn "warn"
    assert_message %{"short_message" => "warn"}
    Logger.error "error"
    assert_message %{"short_message" => "error"}
  end

  @tag logger: [host: "localhost"]
  test "binary host" do
    Logger.info "hello"
    assert_message %{"short_message" => "hello"}
  end

  @tag logger: [app: "rocket_launcher"]
  test "app option" do
    Logger.info "hello"
    assert_message %{"short_message" => "hello", "host" => "rocket_launcher"}
  end

  test "messages in chunks" do
    big_string = random_string(1000)
    Logger.info big_string
    assert_message %{"full_message" => ^big_string}
  end

  test "drop if the message is too big" do
    big_string = random_string(100 * 128 + 10)
    Logger.info big_string
    assert_message %{"short_message" => warning}
    assert warning =~ ~r/Message too large/i
  end

  @tag logger: [compress: :gzip]
  test "gzip compression" do
    Logger.info "hello"
    assert_message %{"short_message" => "hello"}
  end

  @tag logger: [compress: :none]
  test "no compression" do
    Logger.info "hel\nlo"
    assert_message %{"short_message" => "hel\nlo"}
  end

  test "error" do
    spawn(fn ->
      raise "errr"
    end)
    assert_message %{"full_message" => message}
    assert message =~ ~r/errr/i
  end

  test "sasl errors" do
    :proc_lib.spawn(fn ->
      1/0
    end)
    assert_message %{"full_message" => message}
    assert message =~ ~r/arithmetic/i
  end

  @line __ENV__.line
  @tag logger: [metadata: [:line]]
  test "metadata" do
    Logger.info "hello"
    assert_message %{"short_message" => "hello", "_line" => @line + 3}
  end

  test "iodata" do
    Logger.info ["h", 'e', 'l', "lo"]
    assert_message %{"short_message" => "hello"}
  end

  @utf_text "जानते उदेशीत हुआआदी आपके हमारी होने जिम्मे"
  test "utf" do
    Logger.info @utf_text
    assert_message %{"short_message" => @utf_text}
  end

  defp random_string(size) do
    :crypto.strong_rand_bytes(size) |> :base64.encode_to_string |> to_string
  end
end
