defmodule Ludo.GameServer do
  use GenServer
  require Logger

  @max_jugadores 4
  @timeout_sala :timer.minutes(60)

  defmodule Estado do
    @enforce_keys [:codigo, :host_id]
    defstruct [
      :codigo,
      :host_id,
      jugadores: [],
      # :esperando | :jugando | :finalizada
      fase: :esperando,
      turno_idx: 0,
      dado: nil,
      # jugador_id => [%{id, pos}]
      tablero: %{},
      # ids de fichas que pueden moverse este turno (set after rolling)
      fichas_movibles: []
    ]
  end

  # ── Public API ───────────────────────────────────────────────────────────────

  def start_link(opts) do
    codigo = Keyword.fetch!(opts, :codigo)
    GenServer.start_link(__MODULE__, opts, name: via(codigo), timeout: @timeout_sala)
  end

  def get_estado(codigo),          do: GenServer.call(via(codigo), :get_estado)
  def unirse(codigo, jugador),     do: GenServer.call(via(codigo), {:unirse, jugador})
  def salir(codigo, jugador_id),   do: GenServer.cast(via(codigo), {:salir, jugador_id})
  def iniciar(codigo, host_id),    do: GenServer.call(via(codigo), {:iniciar, host_id})
  def tirar_dado(codigo, jugador_id), do: GenServer.call(via(codigo), {:tirar_dado, jugador_id})
  def mover_ficha(codigo, jugador_id, ficha_id),
    do: GenServer.call(via(codigo), {:mover_ficha, jugador_id, ficha_id})

  # ── Callbacks ────────────────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    codigo  = Keyword.fetch!(opts, :codigo)
    host_id = Keyword.fetch!(opts, :host_id)
    Logger.info("GameServer iniciado para sala #{codigo}")
    {:ok, %Estado{codigo: codigo, host_id: host_id}, @timeout_sala}
  end

  @impl true
  def handle_call(:get_estado, _from, estado) do
    {:reply, {:ok, estado}, estado, @timeout_sala}
  end

  @impl true
  def handle_call({:unirse, jugador}, _from, estado) do
    cond do
      length(estado.jugadores) >= @max_jugadores ->
        {:reply, {:error, :sala_llena}, estado, @timeout_sala}

      color_tomado?(estado.jugadores, jugador.color) ->
        {:reply, {:error, :color_tomado}, estado, @timeout_sala}

      jugador_ya_existe?(estado.jugadores, jugador.id) ->
        {:reply, {:error, :ya_en_sala}, estado, @timeout_sala}

      true ->
        nuevo_estado = %{estado | jugadores: estado.jugadores ++ [jugador]}
        broadcast!(nuevo_estado.codigo, {:jugador_unido, nuevo_estado})
        {:reply, {:ok, nuevo_estado}, nuevo_estado, @timeout_sala}
    end
  end

  @impl true
  def handle_call({:iniciar, host_id}, _from, estado) do
    cond do
      estado.host_id != host_id ->
        {:reply, {:error, :no_es_host}, estado, @timeout_sala}

      length(estado.jugadores) < 2 ->
        {:reply, {:error, :pocos_jugadores}, estado, @timeout_sala}

      estado.fase != :esperando ->
        {:reply, {:error, :ya_iniciada}, estado, @timeout_sala}

      true ->
        tablero   = Ludo.Board.nuevo(estado.jugadores)
        nuevo     = %{estado | fase: :jugando, tablero: tablero, dado: nil, turno_idx: 0}
        broadcast!(nuevo.codigo, {:partida_iniciada, nuevo})
        {:reply, {:ok, nuevo}, nuevo, @timeout_sala}
    end
  end

  @impl true
  def handle_call({:tirar_dado, jugador_id}, _from, estado) do
    jugador_en_turno = Enum.at(estado.jugadores, estado.turno_idx)

    cond do
      estado.fase != :jugando ->
        {:reply, {:error, :partida_no_activa}, estado, @timeout_sala}

      jugador_en_turno.id != jugador_id ->
        {:reply, {:error, :no_es_tu_turno}, estado, @timeout_sala}

      estado.dado != nil ->
        {:reply, {:error, :ya_tiraste}, estado, @timeout_sala}

      true ->
        resultado = Enum.random(1..6)
        color     = jugador_en_turno.color
        movibles  = Ludo.Board.fichas_movibles(estado.tablero, jugador_id, color, resultado)

        nuevo = %{estado | dado: resultado, fichas_movibles: movibles}

        # Broadcast dice result first so the UI shows it
        broadcast!(nuevo.codigo, {:dado_tirado, resultado, jugador_id, nuevo})

        # If no valid moves, auto-pass after 2s so the player sees the dice
        if movibles == [] do
          Process.send_after(self(), {:auto_pasar_turno, resultado}, 2000)
        end

        {:reply, {:ok, resultado}, nuevo, @timeout_sala}
    end
  end

  @impl true
  def handle_call({:mover_ficha, jugador_id, ficha_id}, _from, estado) do
    jugador_en_turno = Enum.at(estado.jugadores, estado.turno_idx)

    cond do
      estado.fase != :jugando ->
        {:reply, {:error, :partida_no_activa}, estado, @timeout_sala}

      jugador_en_turno.id != jugador_id ->
        {:reply, {:error, :no_es_tu_turno}, estado, @timeout_sala}

      estado.dado == nil ->
        {:reply, {:error, :debes_tirar_dado}, estado, @timeout_sala}

      ficha_id not in estado.fichas_movibles ->
        {:reply, {:error, :ficha_no_puede_moverse}, estado, @timeout_sala}

      true ->
        dado_usado  = estado.dado
        fichas_prev = Map.get(estado.tablero, jugador_id, [])
        pos_anterior = fichas_prev |> Enum.find(&(&1.id == ficha_id)) |> case do
          nil -> nil
          f   -> f.pos
        end

        case Ludo.Board.aplicar_movimiento(
               estado.tablero, jugador_id, ficha_id,
               dado_usado, estado.jugadores
             ) do
          {:error, _} = err ->
            {:reply, err, estado, @timeout_sala}

          {:ok, nuevo_tablero, eventos} ->
            nuevo =
              %{estado | tablero: nuevo_tablero, dado: nil, fichas_movibles: []}
              |> maybe_finalizar(jugador_id, eventos)
              |> avanzar_turno_si_no_seis(dado_usado, eventos)

            broadcast!(nuevo.codigo,
              {:ficha_movida, jugador_id, ficha_id, dado_usado, pos_anterior, nuevo, eventos})
            {:reply, {:ok, nuevo}, nuevo, @timeout_sala}
        end
    end
  end

  @impl true
  def handle_cast({:salir, jugador_id}, estado) do
    jugadores   = Enum.reject(estado.jugadores, &(&1.id == jugador_id))
    nuevo_estado = %{estado | jugadores: jugadores}

    nuevo_estado =
      if estado.host_id == jugador_id && length(jugadores) > 0 do
        %{nuevo_estado | host_id: hd(jugadores).id}
      else
        nuevo_estado
      end

    broadcast!(nuevo_estado.codigo, {:jugador_salio, nuevo_estado})

    if length(jugadores) == 0 do
      {:stop, :normal, nuevo_estado}
    else
      {:noreply, nuevo_estado, @timeout_sala}
    end
  end

  @impl true
  def handle_info({:auto_pasar_turno, dado_resultado}, estado) do
    # Only advance if the dado is still set (player didn't move in time)
    if estado.dado != nil do
      nuevo = avanzar_turno(estado, dado_resultado)
      broadcast!(nuevo.codigo, {:turno_pasado, nuevo})
      {:noreply, nuevo, @timeout_sala}
    else
      {:noreply, estado, @timeout_sala}
    end
  end

  @impl true
  def handle_info(:timeout, estado) do
    Logger.info("Sala #{estado.codigo} expiró por inactividad")
    {:stop, :normal, estado}
  end

  # ── Private helpers ───────────────────────────────────────────────────────────

  defp avanzar_turno(estado, dado) do
    n = length(estado.jugadores)
    # Same player again on 6, unless game over
    if dado == 6 && estado.fase == :jugando do
      %{estado | dado: nil, fichas_movibles: []}
    else
      %{estado | dado: nil, fichas_movibles: [], turno_idx: rem(estado.turno_idx + 1, n)}
    end
  end

  defp avanzar_turno_si_no_seis(estado, dado, eventos) do
    if :jugador_gana in eventos do
      estado
    else
      avanzar_turno(estado, dado)
    end
  end

  defp maybe_finalizar(estado, _jugador_id, eventos) do
    if :jugador_gana in eventos do
      %{estado | fase: :finalizada}
    else
      estado
    end
  end

  defp via(codigo), do: {:via, Registry, {Ludo.SalaRegistry, codigo}}

  defp broadcast!(codigo, msg),
    do: Phoenix.PubSub.broadcast(Ludo.PubSub, "sala:#{codigo}", msg)

  defp color_tomado?(jugadores, color),
    do: Enum.any?(jugadores, &(&1.color == color))

  defp jugador_ya_existe?(jugadores, id),
    do: Enum.any?(jugadores, &(&1.id == id))
end
