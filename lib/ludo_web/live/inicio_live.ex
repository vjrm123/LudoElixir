# lib/ludo_web/live/inicio_live.ex
defmodule LudoWeb.InicioLive do
  use LudoWeb, :live_view

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        modo: nil,
        nombre: "",
        color: nil,
        codigo_entrada: "",
        error: nil,
        colores: Ludo.Colores.lista(),
        color_hex: Ludo.Colores.mapa_hex()
      )
      |> assign_inicio_form()

    {:ok, socket}
  end

  def handle_event("modo_crear", _params, socket),
    do: {:noreply, assign(socket, modo: :crear, error: nil)}

  def handle_event("modo_unirse", _params, socket),
    do: {:noreply, assign(socket, modo: :unirse, error: nil)}

  def handle_event("volver", _params, socket),
    do: {:noreply, assign(socket, modo: nil, error: nil)}

  def handle_event("change_nombre", %{"value" => val}, socket) do
    {:noreply,
      socket
      |> assign(nombre: val, error: nil)
      |> assign_inicio_form()}
  end

  def handle_event("change_codigo", %{"value" => val}, socket) do
    {:noreply,
      socket
      |> assign(codigo_entrada: String.upcase(val), error: nil)
      |> assign_inicio_form()}
  end

  def handle_event("change_color", %{"color" => color}, socket) do
    color_atom = Enum.find(Ludo.Colores.lista(), &(Atom.to_string(&1) == color))

    if color_atom do
      {:noreply, assign(socket, color: color_atom, error: nil)}
    else
      {:noreply, assign(socket, error: traducir_error(:color_invalido))}
    end
  end

  def handle_event("actualizar_form", params, socket) do
    {:noreply,
      socket
      |> assign_form_params(params)
      |> assign(error: nil)
      |> assign_inicio_form()}
  end

  def handle_event("crear_sala", params, socket) do
    socket =
      socket
      |> assign_form_params(params)
      |> assign_inicio_form()

    case Ludo.Salas.crear_sala(socket.assigns.nombre, socket.assigns.color) do
      {:ok, %{codigo: codigo, host_id: host_id}} ->
        {:noreply,
          socket
          |> push_event("set_jugador_id", %{jugador_id: host_id, codigo: codigo})
          |> push_navigate(to: ~p"/lobby/#{codigo}")}

      {:error, razon} ->
        {:noreply, assign(socket, error: traducir_error(razon))}
    end
  end

  def handle_event("unirse_sala", params, socket) do
    socket =
      socket
      |> assign_form_params(params)
      |> assign_inicio_form()

    %{codigo_entrada: codigo, nombre: nombre, color: color} = socket.assigns

    case Ludo.Salas.unirse_sala(codigo, nombre, color) do
      {:ok, %{jugador_id: jugador_id}} ->
        {:noreply,
          socket
          |> push_event("set_jugador_id", %{jugador_id: jugador_id, codigo: codigo})
          |> push_navigate(to: ~p"/lobby/#{codigo}")}

      {:error, razon} ->
        {:noreply, assign(socket, error: traducir_error(razon))}
    end
  end

  defp assign_form_params(socket, %{"inicio" => params}) do
    assign(socket,
      nombre: Map.get(params, "nombre", socket.assigns.nombre),
      codigo_entrada:
        params
        |> Map.get("codigo", socket.assigns.codigo_entrada)
        |> String.upcase()
    )
  end

  defp assign_form_params(socket, _params), do: socket

  defp assign_inicio_form(socket) do
    assign(
      socket,
      :form,
      to_form(
        %{"nombre" => socket.assigns.nombre, "codigo" => socket.assigns.codigo_entrada},
        as: :inicio
      )
    )
  end

  defp traducir_error(:sala_no_existe), do: "La sala no existe"
  defp traducir_error(:sala_llena), do: "La sala estllena (maximo 4 jugadores)"
  defp traducir_error(:color_tomado), do: "Ese color ya fue elegido por otro jugador"
  defp traducir_error(:nombre_invalido), do: "El nombre debe tener al menos 2 caracteres"
  defp traducir_error(:color_invalido), do: "Selecciona un color valido"
  defp traducir_error(_), do: "Error inesperado. Intenta de nuevo"
end
