defmodule Ludo.GameServer do
  use GenServer
  require Logger

  alias Ludo.Estado
  alias Ludo.Reglas
  alias Ludo.Board

  @max_jugadores 4
  @timeout_sala :timer.minutes(60)
  @tiempo_turno :timer.seconds(30)

  # API publica

  def start_link(opts) do
    codigo = Keyword.fetch!(opts, :codigo)
    GenServer.start_link(__MODULE__, opts, name: via(codigo), timeout: @timeout_sala)
  end

  def get_estado(codigo), do: GenServer.call(via(codigo), :get_estado)
  def unirse(codigo, jugador), do: GenServer.call(via(codigo), {:unirse, jugador})
  def salir(codigo, jugador_id), do: GenServer.cast(via(codigo), {:salir, jugador_id})
  def iniciar(codigo, host_id), do: GenServer.call(via(codigo), {:iniciar, host_id})
  def tirar_dado(codigo, jugador_id), do: GenServer.call(via(codigo), {:tirar_dado, jugador_id})

  def tirar_dado_fijo(codigo, jugador_id, valor),
    do: GenServer.call(via(codigo), {:tirar_dado_fijo, jugador_id, valor})

  def mover_ficha(codigo, jugador_id, ficha_id),
    do: GenServer.call(via(codigo), {:mover_ficha, jugador_id, ficha_id})

  def rendirse(codigo, jugador_id), do: GenServer.call(via(codigo), {:rendirse, jugador_id})

  @impl true
  def init(opts) do
    codigo = Keyword.fetch!(opts, :codigo)
    host_id = Keyword.fetch!(opts, :host_id)
    modo = Keyword.get(opts, :modo, :clasico)
    Logger.info("GameServer iniciado para sala #{codigo} (modo: #{modo})")
    {:ok, %Estado{codigo: codigo, host_id: host_id, modo: modo}, @timeout_sala}
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
        nuevo = %{estado | fase: :jugando, tablero: tablero, dado: nil, turno_idx: 0}
        programar_timeout_turno(nuevo)
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
        procesar_tirada(estado, jugador_id, jugador_en_turno, Enum.random(1..6))
    end
  end

  @impl true
  def handle_call({:tirar_dado_fijo, jugador_id, valor}, _from, estado) do
    jugador_en_turno = Enum.at(estado.jugadores, estado.turno_idx)

    cond do
      estado.fase != :jugando ->
        {:reply, {:error, :partida_no_activa}, estado, @timeout_sala}

      jugador_en_turno.id != jugador_id ->
        {:reply, {:error, :no_es_tu_turno}, estado, @timeout_sala}

      estado.dado != nil ->
        {:reply, {:error, :ya_tiraste}, estado, @timeout_sala}

      valor not in 1..6 ->
        {:reply, {:error, :valor_invalido}, estado, @timeout_sala}

      true ->
        procesar_tirada(estado, jugador_id, jugador_en_turno, valor)
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
        dado_usado = estado.dado
        fichas_prev = Map.get(estado.tablero, jugador_id, [])

        pos_anterior =
          fichas_prev
          |> Enum.find(&(&1.id == ficha_id))
          |> case do
            nil -> nil
            f -> f.pos
          end

        case Reglas.aplicar_movimiento(
               estado.tablero,
               jugador_id,
               ficha_id,
               dado_usado,
               estado.jugadores
             ) do
          {:error, _} = err ->
            {:reply, err, estado, @timeout_sala}

          {:ok, nuevo_tablero, eventos} ->
            nuevo =
              %{estado | tablero: nuevo_tablero, dado: nil, fichas_movibles: []}
              |> Estado.finalizar(eventos)
              |> Estado.avanzar_turno_si_no_seis(dado_usado, eventos)

            programar_timeout_turno(nuevo)

            broadcast!(
              nuevo.codigo,
              {:ficha_movida, jugador_id, ficha_id, dado_usado, pos_anterior, nuevo, eventos}
            )

            {:reply, {:ok, nuevo}, nuevo, @timeout_sala}
        end
    end
  end

  @impl true
  def handle_call({:rendirse, jugador_id}, _from, estado) do
    cond do
      estado.fase != :jugando ->
        {:reply, {:error, :partida_no_activa}, estado, @timeout_sala}

      true ->
        # Cancelar timer de turno
        cancelar_timeout_turno()

        nuevo = %{
          estado
          | fase: :esperando,
            tablero: %{},
            dado: nil,
            fichas_movibles: [],
            turno_idx: 0
        }

        Logger.info("Sala #{estado.codigo}: jugador #{jugador_id} abandonó la partida")
        broadcast!(nuevo.codigo, {:partida_rendida, nuevo})
        {:reply, {:ok, nuevo}, nuevo, @timeout_sala}
    end
  end

  @impl true
  def handle_cast({:salir, jugador_id}, estado) do
    nuevo_estado = ejecutar_salir(estado, jugador_id)

    if length(nuevo_estado.jugadores) == 0,
      do: {:stop, :normal, nuevo_estado},
      else: {:noreply, nuevo_estado, @timeout_sala}
  end

  @impl true
  def handle_info({:auto_pasar_turno, dado_resultado}, estado) do
    if estado.dado != nil do
      nuevo = Estado.avanzar_turno(estado, dado_resultado)
      programar_timeout_turno(nuevo)
      broadcast!(nuevo.codigo, {:turno_pasado, nuevo})
      {:noreply, nuevo, @timeout_sala}
    else
      {:noreply, estado, @timeout_sala}
    end
  end

  @impl true
  def handle_info({:forzar_pasar_turno, turno_idx}, estado) do
    # Cambio de turno forzado tras tres 6 seguidos. Solo aplica si el estado
    # no cambio mientras corria el temporizador (mismo turno y dado sin usar).
    if estado.fase == :jugando && estado.turno_idx == turno_idx && estado.dado != nil do
      nuevo = Estado.pasar_turno(estado)
      programar_timeout_turno(nuevo)
      broadcast!(nuevo.codigo, {:turno_pasado, nuevo})
      {:noreply, nuevo, @timeout_sala}
    else
      {:noreply, estado, @timeout_sala}
    end
  end

  @impl true
  def handle_info({:timeout_turno, jugador_id, turno_idx}, estado) do
    Process.delete(:timeout_ref)

    if estado.fase == :jugando && estado.dado == nil && estado.turno_idx == turno_idx do
      jugador_en_turno = Enum.at(estado.jugadores, estado.turno_idx)

      if jugador_en_turno && jugador_en_turno.id == jugador_id do
        Logger.info("Timeout de turno para jugador #{jugador_id}")
        {:noreply, ejecutar_salir(estado, jugador_id), @timeout_sala}
      else
        {:noreply, estado, @timeout_sala}
      end
    else
      {:noreply, estado, @timeout_sala}
    end
  end

  @impl true
  def handle_info(:timeout, estado) do
    Logger.info("Sala #{estado.codigo} expirada por inactividad")
    {:stop, :normal, estado}
  end

  #  Helpers privados

  # Procesa una tirada (aleatoria o forzada) ya validada: actualiza el contador
  # de seises consecutivos y, si es el tercero, hace perder el turno al jugador.
  defp procesar_tirada(estado, jugador_id, jugador_en_turno, valor) do
    cancelar_timeout_turno()

    seis_seguidos = if valor == 6, do: estado.seis_seguidos + 1, else: 0

    if seis_seguidos >= 3 do
      # Tercer 6 seguido: el jugador pierde el turno y no puede mover.
      # Se muestra el dado (animacion) y se fuerza el cambio de turno tras 2s.
      nuevo = %{estado | dado: valor, fichas_movibles: [], seis_seguidos: seis_seguidos}
      broadcast!(nuevo.codigo, {:tres_seises, jugador_id, valor, nuevo})
      Process.send_after(self(), {:forzar_pasar_turno, nuevo.turno_idx}, 2000)
      {:reply, {:ok, valor}, nuevo, @timeout_sala}
    else
      movibles =
        Reglas.fichas_movibles(estado.tablero, jugador_id, jugador_en_turno.color, valor)

      nuevo = %{estado | dado: valor, fichas_movibles: movibles, seis_seguidos: seis_seguidos}
      broadcast!(nuevo.codigo, {:dado_tirado, valor, jugador_id, nuevo})

      # Si no hay movimientos posibles, pasar turno automaticamente tras 2 segundos
      if movibles == [], do: Process.send_after(self(), {:auto_pasar_turno, valor}, 2000)

      {:reply, {:ok, valor}, nuevo, @timeout_sala}
    end
  end

  defp cancelar_timeout_turno do
    case Process.get(:timeout_ref) do
      nil -> :ok
      ref -> Process.cancel_timer(ref)
    end

    Process.delete(:timeout_ref)
  end

  defp via(codigo), do: {:via, Registry, {Ludo.SalaRegistry, codigo}}

  defp broadcast!(codigo, msg),
    do: Phoenix.PubSub.broadcast(Ludo.PubSub, "sala:#{codigo}", msg)

  defp ejecutar_salir(estado, jugador_id) do
    jugadores = Enum.reject(estado.jugadores, &(&1.id == jugador_id))
    idx_saliente = Enum.find_index(estado.jugadores, &(&1.id == jugador_id))

    tablero =
      if estado.fase == :jugando do
        Map.delete(estado.tablero, jugador_id)
      else
        estado.tablero
      end

    nuevo_estado = %{estado | jugadores: jugadores, tablero: tablero}

    nuevo_estado =
      if estado.host_id == jugador_id && length(jugadores) > 0 do
        %{nuevo_estado | host_id: hd(jugadores).id}
      else
        nuevo_estado
      end

    nuevo_estado =
      if estado.fase == :jugando && idx_saliente do
        if idx_saliente < estado.turno_idx do
          %{nuevo_estado | turno_idx: estado.turno_idx - 1}
        else
          nuevo_estado
        end
      else
        nuevo_estado
      end

    nuevo_estado =
      if estado.fase == :jugando && length(jugadores) <= 1 do
        %{nuevo_estado | fase: :finalizada, turno_idx: 0}
      else
        nuevo_estado
      end

    programar_timeout_turno(nuevo_estado)

    broadcast!(nuevo_estado.codigo, {:jugador_salio, jugador_id, nuevo_estado})

    nuevo_estado
  end

  defp programar_timeout_turno(estado) do
    if estado.fase == :jugando && length(estado.jugadores) > 1 do
      jugador = Enum.at(estado.jugadores, estado.turno_idx)

      if jugador do
        cancelar_timeout_turno()

        ref =
          Process.send_after(
            self(),
            {:timeout_turno, jugador.id, estado.turno_idx},
            @tiempo_turno
          )

        Process.put(:timeout_ref, ref)
      end
    end
  end

  defp color_tomado?(jugadores, color),
    do: Enum.any?(jugadores, &(&1.color == color))

  defp jugador_ya_existe?(jugadores, id),
    do: Enum.any?(jugadores, &(&1.id == id))
end
