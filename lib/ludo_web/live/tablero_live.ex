defmodule LudoWeb.TableroLive do
  use LudoWeb, :live_view

  @path_cells MapSet.new([
    {6,0},{6,1},{6,2},{6,3},{6,4},{6,5},
    {5,6},{4,6},{3,6},{2,6},{1,6},{0,6},
    {0,7},{0,8},
    {1,8},{2,8},{3,8},{4,8},{5,8},
    {6,9},{6,10},{6,11},{6,12},{6,13},{6,14},
    {7,14},{8,14},
    {8,13},{8,12},{8,11},{8,10},{8,9},
    {9,8},{10,8},{11,8},{12,8},{13,8},{14,8},
    {14,7},{14,6},
    {13,6},{12,6},{11,6},{10,6},{9,6},
    {8,5},{8,4},{8,3},{8,2},{8,1},{8,0},
    {7,0}
  ])
  @home_slots %{
    red:     [{1,1},{1,4},{4,1},{4,4}],
    blue:    [{1,10},{1,13},{4,10},{4,13}],
    emerald: [{10,1},{10,4},{13,1},{13,4}],
    amber:   [{10,10},{10,13},{13,10},{13,13}]
  }
  @start_cells %{red: {6,1}, blue: {1,8}, emerald: {13,6}, amber: {8,13}}

  # ── Mount ────────────────────────────────────────────────────────────────────

  def mount(%{"codigo" => codigo}, _session, socket) do
    case Ludo.Salas.obtener_sala(codigo) do
      {:ok, estado} ->
        if connected?(socket), do: Ludo.Salas.suscribir(codigo)

        {:ok,
         socket
         |> assign(codigo: codigo, jugador_id: nil)
         |> sync_estado(estado)}

      {:error, :sala_no_existe} ->
        {:ok,
         socket
         |> put_flash(:error, "La sala no existe.")
         |> push_navigate(to: ~p"/")}
    end
  end

  # ── Events ───────────────────────────────────────────────────────────────────

  def handle_event("restore_jugador", %{"jugador_id" => jid}, socket) do
    en_sala? = socket.assigns.jugadores_lista
               |> Enum.any?(&(&1.id == jid))
    {:noreply, if(en_sala?, do: assign(socket, jugador_id: jid), else: socket)}
  end

  def handle_event("tirar_dado", _params, socket) do
    %{codigo: codigo, jugador_id: jid} = socket.assigns

    case Ludo.GameServer.tirar_dado(codigo, jid) do
      {:ok, _resultado} -> {:noreply, socket}
      {:error, _razon}  -> {:noreply, socket}
    end
  end

  def handle_event("minimizar_popup", _params, socket) do
    {:noreply, assign(socket, popup_minimizado: true)}
  end

  def handle_event("mover_ficha", %{"ficha" => ficha_id_str}, socket) do
    %{codigo: codigo, jugador_id: jid} = socket.assigns
    ficha_id = String.to_integer(ficha_id_str)

    case Ludo.GameServer.mover_ficha(codigo, jid, ficha_id) do
      {:ok, _nuevo_estado} -> {:noreply, socket}
      {:error, _razon}     -> {:noreply, socket}
    end
  end

  # ── PubSub ───────────────────────────────────────────────────────────────────

  def handle_info({:dado_tirado, resultado, jugador_id, nuevo_estado}, socket) do
    socket =
      socket
      |> push_event("dado_tirado", %{jugador_id: jugador_id, valor: resultado})
      |> assign(popup_minimizado: false)
    {:noreply, sync_estado(socket, nuevo_estado)}
  end

  def handle_info({:ficha_movida, jugador_id, ficha_id, dado_usado, pos_anterior, nuevo_estado, _eventos}, socket) do
    jugador = Enum.find(nuevo_estado.jugadores, &(&1.id == jugador_id))

    socket =
      if jugador && pos_anterior && dado_usado do
        color_es = jugador.color
        color_en = color_sala_to_tablero(color_es)
        inicio   = anim_inicio(pos_anterior, color_en, color_es, ficha_id - 1)
        pasos    = Ludo.Board.pasos_de_movimiento(pos_anterior, color_es, dado_usado)

        push_event(socket, "animar_token", %{
          token_id:    "#{jugador_id}-#{ficha_id}",
          color_class: player_color_class(color_en),
          inicio:      Tuple.to_list(inicio),
          pasos:       Enum.map(pasos, &Tuple.to_list/1),
          intervalo:   300
        })
      else
        socket
      end

    {:noreply, sync_estado(socket, nuevo_estado)}
  end

  def handle_info({:turno_pasado, nuevo_estado}, socket) do
    {:noreply, sync_estado(socket, nuevo_estado)}
  end

  def handle_info({:partida_iniciada, nuevo_estado}, socket) do
    {:noreply, sync_estado(socket, nuevo_estado)}
  end

  def handle_info({:jugador_salio, _estado}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # ── State sync ────────────────────────────────────────────────────────────────

  # Sincroniza el estado del servidor con los assigns de LiveView.
  # Cuando el dado vuelve a nil (tras mover ficha o pasar turno),
  # se resetea popup_minimizado para que el popup vuelva a aparecer en el siguiente turno.
  defp sync_estado(socket, estado) do
    jugadores_lista  = estado.jugadores
    color_map        = Map.new(jugadores_lista, &{&1.id, &1.color})
    token_coords     = build_token_coords(estado.tablero, color_map)
    jugador_en_turno = Enum.at(jugadores_lista, estado.turno_idx)

    assign(socket,
      fase:             estado.fase,
      jugadores_lista:  jugadores_lista,
      turno_jugador:    jugador_en_turno,
      dado:             estado.dado,
      fichas_movibles:  estado.fichas_movibles,
      tablero:          estado.tablero,
      token_coords:     token_coords,
      ganador:          if(estado.fase == :finalizada, do: jugador_en_turno, else: nil),
      popup_minimizado: if(estado.dado == nil, do: false, else: Map.get(socket.assigns, :popup_minimizado, false))
    )
  end

  defp build_token_coords(tablero, color_map) do
    Enum.flat_map(tablero, fn {jugador_id, fichas} ->
      color_es = Map.get(color_map, jugador_id)
      color_en = color_sala_to_tablero(color_es)

      Enum.map(fichas, fn ficha ->
        coords = pos_to_coords(ficha.pos, color_es, ficha.id - 1)
        %{
          jugador_id: jugador_id,
          ficha_id:   ficha.id,
          color:      color_en,
          coords:     coords,
          en_casa:    ficha.pos == :casa,
          en_meta:    ficha.pos == :meta
        }
      end)
    end)
  end

  defp pos_to_coords(:casa, color_es, slot_idx) do
    color_en = color_sala_to_tablero(color_es)
    slots = @home_slots[color_en] || []
    Enum.at(slots, slot_idx, {0, 0})
  end

  defp pos_to_coords({:camino, n}, _color, _slot) do
    Ludo.Board.cell_coords(n)
  end

  defp pos_to_coords({:pasillo, p}, color_es, _slot) do
    Ludo.Board.home_lane_coords(color_es) |> Enum.at(p - 1)
  end

  defp pos_to_coords(:meta, _color, _slot), do: {7, 7}

  # ── Board rendering helpers ──────────────────────────────────────────────────

  def board_cell(row, col) do
    cond do
      slot_color = home_slot_color(row, col) ->
        %{kind: :home_slot, color: slot_color, slot: home_slot_number(slot_color, row, col)}

      base_color = base_color(row, col) ->
        %{kind: :base, color: base_color}

      center_cell?(row, col) ->
        center_cell_info(row, col)

      lane_color = home_lane_color(row, col) ->
        %{kind: :lane, color: lane_color}

      MapSet.member?(@path_cells, {row, col}) ->
        %{kind: :path, color: start_color(row, col), safe: safe_cell?(row, col), row: row, col: col}

      true ->
        %{kind: :blank}
    end
  end

  def board_cell_class(%{kind: :blank}),
    do: "aspect-square"

  def board_cell_class(%{kind: :base, color: _color}),
    do: "aspect-square"

  def board_cell_class(%{kind: :home_slot, color: _color}),
    do: "aspect-square"

  def board_cell_class(%{kind: :center_core}),
    do: "aspect-square bg-white/20"

  def board_cell_class(%{kind: :center_corner}),
    do: "aspect-square bg-white/15"

  def board_cell_class(%{kind: :center_tri, color: color}),
    do: "aspect-square #{center_tri_bg(color)}"

  def board_cell_class(%{kind: :lane, color: color}),
    do: "aspect-square rounded-sm #{lane_gradient(color)}"

  def board_cell_class(%{kind: :path, color: nil} = cell),
    do: "aspect-square bg-white/52 border border-white/52 #{path_corner_class(cell.row, cell.col)}"

  def board_cell_class(%{kind: :path, color: color} = cell),
    do: "aspect-square border border-white/30 #{start_cell_gradient(color)} #{path_corner_class(cell.row, cell.col)}"

  # Esquinas del camino — cada celda de esquina tiene el radio en la esquina correcta
  defp path_corner_class(0,  6),  do: "rounded-tl-lg"
  defp path_corner_class(0,  8),  do: "rounded-tr-lg"
  defp path_corner_class(6,  0),  do: "rounded-tl-lg"
  defp path_corner_class(8,  0),  do: "rounded-bl-lg"
  defp path_corner_class(6,  14), do: "rounded-tr-lg"
  defp path_corner_class(8,  14), do: "rounded-br-lg"
  defp path_corner_class(14, 6),  do: "rounded-bl-lg"
  defp path_corner_class(14, 8),  do: "rounded-br-lg"
  defp path_corner_class(_,  _),  do: ""

  # Returns list of tokens on a given {row, col}
  def tokens_en_celda(token_coords, row, col) do
    Enum.filter(token_coords, &(&1.coords == {row, col}))
  end

  # Returns tokens that are in their home (casa) for a given board color
  def tokens_en_casa(token_coords, color) do
    Enum.filter(token_coords, &(&1.en_casa && &1.color == color))
  end

  # CSS grid-area style for each home zone overlay
  def home_zone_grid_style(:red),     do: "grid-column: 1 / 7; grid-row: 1 / 7;"
  def home_zone_grid_style(:blue),    do: "grid-column: 10 / 16; grid-row: 1 / 7;"
  def home_zone_grid_style(:emerald), do: "grid-column: 1 / 7; grid-row: 10 / 16;"
  def home_zone_grid_style(:amber),   do: "grid-column: 10 / 16; grid-row: 10 / 16;"

  # Home zone bg CSS classes (app.css)
  def home_zone_bg(:red),     do: "home-zone-red"
  def home_zone_bg(:blue),    do: "home-zone-blue"
  def home_zone_bg(:emerald), do: "home-zone-emerald"
  def home_zone_bg(:amber),   do: "home-zone-amber"

  # Cuadrado interior — muy oscuro del mismo color, contraste para piezas brillantes
  @inner_base "border-radius: 18%; padding: 5%; gap: 4%; box-shadow: inset 0 3px 16px rgba(0,0,0,0.55);"
  def home_inner_style(:red),
    do: @inner_base <> " background: rgba(80,0,0,0.75); border: 2px solid rgba(239,68,68,0.60);"
  def home_inner_style(:blue),
    do: @inner_base <> " background: rgba(0,10,75,0.75); border: 2px solid rgba(59,130,246,0.60);"
  def home_inner_style(:emerald),
    do: @inner_base <> " background: rgba(0,40,18,0.75); border: 2px solid rgba(16,185,129,0.60);"
  def home_inner_style(:amber),
    do: @inner_base <> " background: rgba(70,35,0,0.75); border: 2px solid rgba(245,158,11,0.60);"

  def es_mi_turno?(jugador_id, turno_jugador) do
    turno_jugador != nil && turno_jugador.id == jugador_id
  end

  def puedo_tirar?(jugador_id, turno_jugador, dado) do
    es_mi_turno?(jugador_id, turno_jugador) && dado == nil
  end

  def puede_mover_ficha?(ficha_id, fichas_movibles, jugador_id, turno_jugador, dado) do
    es_mi_turno?(jugador_id, turno_jugador) && dado != nil &&
      ficha_id in fichas_movibles
  end

  def player_color_class(nil),      do: "bg-[#c8f07a]"
  def player_color_class(:red),     do: "bg-red-500"
  def player_color_class(:blue),    do: "bg-blue-500"
  def player_color_class(:emerald), do: "bg-emerald-500"
  def player_color_class(:amber),   do: "bg-amber-500"

  def color_name(:red),     do: "Rojo"
  def color_name(:blue),    do: "Azul"
  def color_name(:emerald), do: "Verde"
  def color_name(:amber),   do: "Amarillo"
  def color_name(nil),      do: "-"

  def color_hex(:red),     do: "#dc2626"
  def color_hex(:blue),    do: "#2563eb"
  def color_hex(:emerald), do: "#059669"
  def color_hex(:amber),   do: "#d97706"

  def color_sala_nombre(c), do: color_name(color_sala_to_tablero(c))

  def color_sala_hex(:rojo),     do: "#dc2626"
  def color_sala_hex(:azul),     do: "#2563eb"
  def color_sala_hex(:verde),    do: "#059669"
  def color_sala_hex(:amarillo), do: "#d97706"
  def color_sala_hex(_),         do: "#6366f1"

  defp anim_inicio(:casa, color_en, _color_es, slot_idx) do
    slots = @home_slots[color_en] || []
    Enum.at(slots, slot_idx, {0, 0})
  end

  defp anim_inicio({:camino, n}, _color_en, _color_es, _slot) do
    Ludo.Board.cell_coords(n)
  end

  defp anim_inicio({:pasillo, p}, _color_en, color_es, _slot) do
    Ludo.Board.home_lane_coords(color_es) |> Enum.at(p - 1, {7, 7})
  end

  defp anim_inicio(:meta, _color_en, _color_es, _slot), do: {7, 7}
  defp anim_inicio(_, _color_en, _color_es, _slot), do: {7, 7}

  def color_sala_to_tablero(:rojo),     do: :red
  def color_sala_to_tablero(:azul),     do: :blue
  def color_sala_to_tablero(:verde),    do: :emerald
  def color_sala_to_tablero(:amarillo), do: :amber
  def color_sala_to_tablero(c),         do: c

  # ── Board geometry helpers ────────────────────────────────────────────────────

  defp home_slot_color(row, col) do
    Enum.find_value(@home_slots, fn {color, slots} ->
      if {row, col} in slots, do: color
    end)
  end

  defp home_slot_number(color, row, col) do
    @home_slots
    |> Map.fetch!(color)
    |> Enum.find_index(&(&1 == {row, col}))
    |> Kernel.+(1)
  end

  defp center_cell?(row, col), do: row in 6..8 and col in 6..8

  defp home_lane_color(7, col) when col in 1..5,  do: :red
  defp home_lane_color(row, 7) when row in 1..5,  do: :blue
  defp home_lane_color(row, 7) when row in 9..13, do: :emerald
  defp home_lane_color(7, col) when col in 9..13, do: :amber
  defp home_lane_color(_row, _col), do: nil

  defp base_color(row, col) when row in 0..5 and col in 0..5,   do: :red
  defp base_color(row, col) when row in 0..5 and col in 9..14,  do: :blue
  defp base_color(row, col) when row in 9..14 and col in 0..5,  do: :emerald
  defp base_color(row, col) when row in 9..14 and col in 9..14, do: :amber
  defp base_color(_row, _col), do: nil

  defp center_cell_info(7, 7), do: %{kind: :center_core}
  defp center_cell_info(6, 7), do: %{kind: :center_tri, color: :blue}
  defp center_cell_info(7, 6), do: %{kind: :center_tri, color: :red}
  defp center_cell_info(7, 8), do: %{kind: :center_tri, color: :amber}
  defp center_cell_info(8, 7), do: %{kind: :center_tri, color: :emerald}
  defp center_cell_info(_, _), do: %{kind: :center_corner}

  defp safe_cell?(6, 1),  do: true
  defp safe_cell?(1, 8),  do: true
  defp safe_cell?(13, 6), do: true
  defp safe_cell?(8, 13), do: true
  defp safe_cell?(_, _),  do: false

  defp start_color(row, col) do
    Enum.find_value(@start_cells, fn {color, coord} ->
      if coord == {row, col}, do: color
    end)
  end


  defp center_tri_bg(:red),     do: "bg-red-500/70"
  defp center_tri_bg(:blue),    do: "bg-blue-500/70"
  defp center_tri_bg(:emerald), do: "bg-emerald-500/70"
  defp center_tri_bg(:amber),   do: "bg-amber-500/70"

  defp lane_gradient(:red),     do: "bg-red-500/80"
  defp lane_gradient(:blue),    do: "bg-blue-500/80"
  defp lane_gradient(:emerald), do: "bg-emerald-500/80"
  defp lane_gradient(:amber),   do: "bg-amber-500/80"

  defp start_cell_gradient(:red),     do: "bg-red-400/70"
  defp start_cell_gradient(:blue),    do: "bg-blue-400/70"
  defp start_cell_gradient(:emerald), do: "bg-emerald-400/70"
  defp start_cell_gradient(:amber),   do: "bg-amber-300/70"
end
