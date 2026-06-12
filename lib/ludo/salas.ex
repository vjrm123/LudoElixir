# lib/ludo/salas.ex
defmodule Ludo.Salas do
  alias Ludo.GameServer

  # ─── Generación de código de sala ─────────────────────────────────────────

  @chars "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  @longitud_codigo 6

  defp generar_codigo do
    1..@longitud_codigo
    |> Enum.map(fn _ ->
      String.at(@chars, :rand.uniform(String.length(@chars)) - 1)
    end)
    |> Enum.join()
  end

  defp codigo_unico do
    # Genera hasta encontrar uno que no esté en uso
    codigo = generar_codigo()
    if sala_existe?(codigo), do: codigo_unico(), else: codigo
  end

  # ─── API pública ──────────────────────────────────────────────────────────

  @doc """
  Crea una nueva sala y arrancar su GameServer.
  Retorna {:ok, %{codigo, estado}} o {:error, razon}.
  """
  def crear_sala(nombre_jugador, color) do
    with :ok <- validar_color(color),
         :ok <- validar_nombre(nombre_jugador),
         codigo <- codigo_unico(),
         host_id <- generar_id(),
         jugador <- %{id: host_id, nombre: nombre_jugador, color: color},
         {:ok, _pid} <- arrancar_game_server(codigo, host_id),
         {:ok, estado} <- GameServer.unirse(codigo, jugador) do
      {:ok, %{codigo: codigo, host_id: host_id, estado: estado}}
    end
  end

  @doc """
  Une a un jugador a una sala existente.
  """
  def unirse_sala(codigo, nombre_jugador, color) do
    codigo = normalizar_codigo(codigo)

    with  :ok <- validar_color(color),
          :ok <- validar_nombre(nombre_jugador),
          :ok <- sala_existe_o_error(codigo),
          jugador_id <- generar_id(),
          jugador <- %{id: jugador_id, nombre: nombre_jugador, color: color},
          {:ok, estado} <- GameServer.unirse(codigo, jugador) do
      {:ok, %{jugador_id: jugador_id, estado: estado}}
    end
  end

  @doc """
  Obtiene el estado actual de una sala.
  """
  def obtener_sala(codigo) do
    codigo = normalizar_codigo(codigo)

    if sala_existe?(codigo) do
      GameServer.get_estado(codigo)
    else
      {:error, :sala_no_existe}
    end
  end

  @doc """
  Saca a un jugador de la sala (usado en terminate del LiveView).
  """
  def salir_sala(codigo, jugador_id) do
    codigo = normalizar_codigo(codigo)

    if sala_existe?(codigo) do
      GameServer.salir(codigo, jugador_id)
    end

    :ok
  end

  @doc """
  Inicia la partida. Solo el host puede llamar esto.
  """
  def iniciar_partida(codigo, host_id) do
    codigo = normalizar_codigo(codigo)

    with :ok <- sala_existe_o_error(codigo) do
      GameServer.iniciar(codigo, host_id)
    end
  end

  @doc """
  Suscribe el proceso actual al topic de la sala.
  Llamar desde LiveView.mount/3.
  """
  def suscribir(codigo) do
    codigo = normalizar_codigo(codigo)
    Phoenix.PubSub.subscribe(Ludo.PubSub, "sala:#{codigo}")
  end

  @colores_validos [:rojo, :azul, :verde, :amarillo]

  defp validar_color(color) when color in @colores_validos, do: :ok
  defp validar_color(_), do: {:error, :color_invalido}

  defp validar_nombre(nombre) when is_binary(nombre) and byte_size(nombre) >= 2, do: :ok
  defp validar_nombre(_), do: {:error, :nombre_invalido}

  defp normalizar_codigo(codigo) when is_binary(codigo),
    do: codigo |> String.trim() |> String.upcase()

  defp normalizar_codigo(codigo), do: codigo

  defp sala_existe?(codigo) do
    case Registry.lookup(Ludo.SalaRegistry, codigo) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  defp sala_existe_o_error(codigo) do
    if sala_existe?(codigo), do: :ok, else: {:error, :sala_no_existe}
  end

  defp arrancar_game_server(codigo, host_id) do
    DynamicSupervisor.start_child(
      Ludo.SalaSupervisor,
      {GameServer, codigo: codigo, host_id: host_id}
    )
  end

  defp generar_id, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
