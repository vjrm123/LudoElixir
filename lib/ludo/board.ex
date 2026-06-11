defmodule Ludo.Board do
  # 52-cell main path in clockwise order starting from Red's start cell
  @path [
    {6,1},{6,2},{6,3},{6,4},{6,5},
    {5,6},{4,6},{3,6},{2,6},{1,6},
    {0,6},{0,7},{0,8},
    {1,8},{2,8},{3,8},{4,8},{5,8},
    {6,9},{6,10},{6,11},{6,12},{6,13},{6,14},
    {7,14},{8,14},
    {8,13},{8,12},{8,11},{8,10},{8,9},
    {9,8},{10,8},{11,8},{12,8},{13,8},{14,8},
    {14,7},{14,6},
    {13,6},{12,6},{11,6},{10,6},{9,6},
    {8,5},{8,4},{8,3},{8,2},{8,1},{8,0},
    {7,0},{6,0}
  ]

  # Home lane cells in order (position 1 = nearest entry, 5 = nearest center)
  @home_lanes %{
    rojo:     [{7,1},{7,2},{7,3},{7,4},{7,5}],
    azul:     [{1,7},{2,7},{3,7},{4,7},{5,7}],
    verde:    [{13,7},{12,7},{11,7},{10,7},{9,7}],
    amarillo: [{7,13},{7,12},{7,11},{7,10},{7,9}]
  }

  # Last main-path cell before home lane (token at this cell moves into lane next step)
  @home_entry %{rojo: 51, azul: 12, verde: 38, amarillo: 25}

  # Safe cells: capture cannot happen here
  @safe_cells MapSet.new([1, 14, 27, 40])

  # Precomputed at compile time
  @cell_coords @path |> Enum.with_index(1) |> Map.new(fn {rc, n} -> {n, rc} end)

  def cell_coords(n), do: Map.get(@cell_coords, n)
  def home_lane_coords(color), do: Map.get(@home_lanes, color, [])

  def casilla_salida(:rojo),     do: 1
  def casilla_salida(:azul),     do: 14
  def casilla_salida(:verde),    do: 40
  def casilla_salida(:amarillo), do: 27

  def nuevo(jugadores) do
    Map.new(jugadores, fn jugador ->
      fichas = Enum.map(1..4, &%{id: &1, pos: :casa})
      {jugador.id, fichas}
    end)
  end

  @doc "Returns list of ficha ids that can legally move with this dice roll."
  def fichas_movibles(tablero, jugador_id, color, dado) do
    tablero
    |> Map.get(jugador_id, [])
    |> Enum.filter(&puede_mover?(&1.pos, color, dado))
    |> Enum.map(& &1.id)
  end

  @doc "Applies a token move; returns {:ok, new_tablero, events} or {:error, reason}."
  def aplicar_movimiento(tablero, jugador_id, ficha_id, dado, jugadores) do
    fichas = Map.get(tablero, jugador_id, [])

    case Enum.find(fichas, &(&1.id == ficha_id)) do
      nil ->
        {:error, :ficha_no_encontrada}

      ficha ->
        color = get_color(jugadores, jugador_id)
        nueva_pos = nueva_posicion(ficha.pos, color, dado)
        fichas_nuevas = Enum.map(fichas, fn f ->
          if f.id == ficha_id, do: %{f | pos: nueva_pos}, else: f
        end)
        tablero2 = Map.put(tablero, jugador_id, fichas_nuevas)
        {tablero3, capturas} = resolver_capturas(tablero2, jugador_id, nueva_pos, jugadores)

        eventos =
          []
          |> maybe_add(:ficha_capturada, capturas != [])
          |> maybe_add(:ficha_en_meta, nueva_pos == :meta)
          |> maybe_add(:jugador_gana, todas_en_meta?(tablero3, jugador_id))

        {:ok, tablero3, eventos}
    end
  end

  # ── Position logic ──────────────────────────────────────────────────────────

  defp puede_mover?(:casa, _color, 6), do: true
  defp puede_mover?(:casa, _color, _), do: false
  defp puede_mover?(:meta, _color, _), do: false

  defp puede_mover?({:camino, n}, color, dado) do
    entry = @home_entry[color]
    steps_to_entry = rem(entry - n + 52, 52)
    steps_beyond = dado - steps_to_entry
    # Must not overshoot past meta (6 steps beyond entry)
    dado <= steps_to_entry || steps_beyond <= 6
  end

  defp puede_mover?({:pasillo, pos}, _color, dado), do: pos + dado <= 6

  defp nueva_posicion(:casa, color, 6), do: {:camino, casilla_salida(color)}

  defp nueva_posicion({:camino, n}, color, dado) do
    entry = @home_entry[color]
    steps_to_entry = rem(entry - n + 52, 52)

    if dado <= steps_to_entry do
      {:camino, rem(n + dado - 1, 52) + 1}
    else
      steps_beyond = dado - steps_to_entry
      if steps_beyond == 6, do: :meta, else: {:pasillo, steps_beyond}
    end
  end

  defp nueva_posicion({:pasillo, pos}, _color, dado) do
    case pos + dado do
      6 -> :meta
      p when p < 6 -> {:pasillo, p}
      # bounce back (shouldn't happen if fichas_movibles filtered correctly)
      p -> {:pasillo, 12 - p}
    end
  end

  # ── Capture logic ────────────────────────────────────────────────────────────

  defp resolver_capturas(tablero, atacante_id, {:camino, n}, jugadores) do
    if MapSet.member?(@safe_cells, n) do
      {tablero, []}
    else
      Enum.reduce(jugadores, {tablero, []}, fn jugador, {t, caps} ->
        if jugador.id == atacante_id do
          {t, caps}
        else
          fichas = Map.get(t, jugador.id, [])
          capturadas = Enum.filter(fichas, &(&1.pos == {:camino, n}))

          if capturadas == [] do
            {t, caps}
          else
            nuevas = Enum.map(fichas, fn f ->
              if f.pos == {:camino, n}, do: %{f | pos: :casa}, else: f
            end)
            {Map.put(t, jugador.id, nuevas), caps ++ capturadas}
          end
        end
      end)
    end
  end

  defp resolver_capturas(tablero, _id, _pos, _jugadores), do: {tablero, []}

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp todas_en_meta?(tablero, jugador_id) do
    tablero |> Map.get(jugador_id, []) |> Enum.all?(&(&1.pos == :meta))
  end

  defp get_color(jugadores, jugador_id) do
    case Enum.find(jugadores, &(&1.id == jugador_id)) do
      nil -> nil
      j -> j.color
    end
  end

  defp maybe_add(list, event, true), do: [event | list]
  defp maybe_add(list, _event, false), do: list

  @doc """
  Returns the list of {row, col} cells a token visits when moved `dado` steps,
  NOT including the starting cell, including the final cell.
  Used for step-by-step animation.
  """
  def pasos_de_movimiento(:casa, color, _dado) do
    [cell_coords(casilla_salida(color))]
  end

  def pasos_de_movimiento(pos_inicial, color, dado) do
    Enum.scan(1..dado, pos_inicial, fn _i, pos -> sig_pos(pos, color) end)
    |> Enum.map(fn
      {:camino, n}  -> cell_coords(n)
      {:pasillo, p} -> Enum.at(home_lane_coords(color), p - 1)
      :meta         -> {7, 7}
      _             -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp sig_pos(:casa, color), do: {:camino, casilla_salida(color)}

  defp sig_pos({:camino, n}, color) do
    if n == @home_entry[color], do: {:pasillo, 1}, else: {:camino, rem(n, 52) + 1}
  end

  defp sig_pos({:pasillo, p}, _color) when p >= 5, do: :meta
  defp sig_pos({:pasillo, p}, _color), do: {:pasillo, p + 1}
  defp sig_pos(:meta, _color), do: :meta

  @doc "Returns {row, col} for rendering a token given its position and color."
  def coords_para_pos(:casa, _color, slot_idx) do
    # slot_idx 0..3 — caller picks the home slot
    {:casa, slot_idx}
  end

  def coords_para_pos({:camino, n}, _color, _slot_idx), do: cell_coords(n)

  def coords_para_pos({:pasillo, p}, color, _slot_idx) do
    Enum.at(home_lane_coords(color), p - 1)
  end

  def coords_para_pos(:meta, _color, _slot_idx), do: {7, 7}
end
