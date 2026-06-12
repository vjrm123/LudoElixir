defmodule Ludo.GameServer do
  @moduledoc "Proceso GenServer que gestiona el ciclo de vida de una partida"

  use GenServer
  require Logger

  alias Ludo.Estado
  alias Ludo.Reglas
  alias Ludo.Board

  @max_jugadores 4
  @timeout_sala  :timer.minutes(60)

  # ── API publica ───────────────────────────────────────────────────────────────

  def start_link(opts) do
    codigo = Keyword.fetch!(opts, :codigo)
    GenServer.start_link(__MODULE__, opts, name: via(codigo), timeout: @timeout_sala)
  end

  def get_estado(codigo),             do: GenServer.call(via(codigo), :get_estado)
  def unirse(codigo, jugador),        do: GenServer.call(via(codigo), {:unirse, jugador})
  def salir(codigo, jugador_id),      do: GenServer.cast(via(codigo), {:salir, jugador_id})
  def iniciar(codigo, host_id),       do: GenServer.call(via(codigo), {:iniciar, host_id})
  def tirar_dado(codigo, jugador_id), do: GenServer.call(via(codigo), {:tirar_dado, jugador_id})

  def mover_ficha(codigo, jugador_id, ficha_id),
    do: GenServer.call(via(codigo), {:mover_ficha, jugador_id, ficha_id})

  # ── Callbacks GenServer ───────────────────────────────────────────────────────

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
        tablero = Board.nuevo(estado.jugadores)
        nuevo   = %{estado | fase: :jugando, tablero: tablero, dado: nil, turno_idx: 0}
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
        movibles  = Reglas.fichas_movibles(estado.tablero, jugador_id, color, resultado)
        nuevo     = %{estado | dado: resultado, fichas_movibles: movibles}

        broadcast!(nuevo.codigo, {:dado_tirado, resultado, jugador_id, nuevo})

        # Si no hay movimientos posibles, pasar turno automaticamente tras 2 segundos
        if movibles == [], do: Process.send_after(self(), {:auto_pasar_turno, resultado}, 2000)

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
        dado_usado   = estado.dado
        fichas_prev  = Map.get(estado.tablero, jugador_id, [])
        pos_anterior = fichas_prev |> Enum.find(&(&1.id == ficha_id)) |> case do
          nil -> nil
          f   -> f.pos
        end

        case Reglas.aplicar_movimiento(estado.tablero, jugador_id, ficha_id, dado_usado, estado.jugadores) do
          {:error, _} = err ->
            {:reply, err, estado, @timeout_sala}

          {:ok, nuevo_tablero, eventos} ->
            nuevo =
              %{estado | tablero: nuevo_tablero, dado: nil, fichas_movibles: []}
              |> Estado.finalizar(eventos)
              |> Estado.avanzar_turno_si_no_seis(dado_usado, eventos)

            broadcast!(nuevo.codigo,
              {:ficha_movida, jugador_id, ficha_id, dado_usado, pos_anterior, nuevo, eventos})
            {:reply, {:ok, nuevo}, nuevo, @timeout_sala}
        end
    end
  end

  @impl true
  def handle_cast({:salir, jugador_id}, estado) do
    jugadores    = Enum.reject(estado.jugadores, &(&1.id == jugador_id))
    nuevo_estado = %{estado | jugadores: jugadores}

    nuevo_estado =
      if estado.host_id == jugador_id && length(jugadores) > 0 do
        %{nuevo_estado | host_id: hd(jugadores).id}
      else
        nuevo_estado
      end

    broadcast!(nuevo_estado.codigo, {:jugador_salio, nuevo_estado})

    if length(jugadores) == 0,
      do:   {:stop, :normal, nuevo_estado},
      else: {:noreply, nuevo_estado, @timeout_sala}
  end

  @impl true
  def handle_info({:auto_pasar_turno, dado_resultado}, estado) do
    # Solo avanzar si el dado sigue activo (el jugador no movio a tiempo)
    if estado.dado != nil do
      nuevo = Estado.avanzar_turno(estado, dado_resultado)
      broadcast!(nuevo.codigo, {:turno_pasado, nuevo})
      {:noreply, nuevo, @timeout_sala}
    else
      {:noreply, estado, @timeout_sala}
    end
  end

  @impl true
  def handle_info(:timeout, estado) do
    Logger.info("Sala #{estado.codigo} expirada por inactividad")
    {:stop, :normal, estado}
  end

  # ── Helpers privados ──────────────────────────────────────────────────────────

  defp via(codigo), do: {:via, Registry, {Ludo.SalaRegistry, codigo}}

  defp broadcast!(codigo, msg),
    do: Phoenix.PubSub.broadcast(Ludo.PubSub, "sala:#{codigo}", msg)

  defp color_tomado?(jugadores, color),
    do: Enum.any?(jugadores, &(&1.color == color))

  defp jugador_ya_existe?(jugadores, id),
    do: Enum.any?(jugadores, &(&1.id == id))
end
