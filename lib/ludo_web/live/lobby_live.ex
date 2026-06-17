# lib/ludo_web/live/lobby_live.ex
defmodule LudoWeb.LobbyLive do
  use LudoWeb, :live_view

  def mount(%{"codigo" => codigo}, session, socket) do
    jugador_id = session["jugador_id"]

    case Ludo.Salas.obtener_sala(codigo) do
      {:ok, estado} ->
        if connected?(socket) do
          Ludo.Salas.suscribir(codigo)
        end

        {:ok,
          assign(socket,
            codigo: codigo,
            jugador_id: jugador_id,
            estado: estado,
            color_hex: Ludo.Colores.mapa_hex()
          )}

      {:error, :sala_no_existe} ->
        {:ok,
          socket
          |> put_flash(:error, "La sala #{codigo} no existe.")
          |> push_navigate(to: ~p"/")}
    end
  end

  def handle_event("iniciar_partida", _params, socket) do
    %{codigo: codigo, jugador_id: jugador_id} = socket.assigns

    case Ludo.Salas.iniciar_partida(codigo, jugador_id) do
      {:ok, _estado} ->
        {:noreply, socket}

      {:error, razon} ->
        {:noreply, put_flash(socket, :error, "No se puede iniciar: #{razon}")}
    end
  end

  def handle_event("restore_jugador", %{"jugador_id" => jugador_id}, socket) do
    jugador_en_sala? = Enum.any?(socket.assigns.estado.jugadores, &(&1.id == jugador_id))

    if jugador_en_sala? do
      {:noreply, assign(socket, jugador_id: jugador_id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("salir_sala", _params, socket) do
    %{codigo: codigo, jugador_id: jugador_id} = socket.assigns
    Ludo.Salas.salir_sala(codigo, jugador_id)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_info({:jugador_unido, nuevo_estado}, socket) do
    {:noreply, assign(socket, estado: nuevo_estado)}
  end

  def handle_info({:jugador_salio, nuevo_estado}, socket) do
    {:noreply, assign(socket, estado: nuevo_estado)}
  end

  def handle_info({:partida_iniciada, _estado}, socket) do
    # Todos navegan al tablero cuando el host inicia
    {:noreply, push_navigate(socket, to: ~p"/tablero/#{socket.assigns.codigo}")}
  end

  def es_host?(estado, jugador_id),
    do: estado.host_id == jugador_id

  def puede_iniciar?(estado),
    do: length(estado.jugadores) >= 2 && estado.fase == :esperando
end
