defmodule Ludo.Reglas do
  @moduledoc "Reglas del juego — movimiento de fichas, capturas y condicion de victoria"

  alias Ludo.Board

  # ── API publica ───────────────────────────────────────────────────────────────

  @doc "Lista de ids de fichas que pueden moverse legalmente con el resultado del dado."
  def fichas_movibles(tablero, jugador_id, color, dado) do
    tablero
    |> Map.get(jugador_id, [])
    |> Enum.filter(&puede_mover?(&1.pos, color, dado))
    |> Enum.map(& &1.id)
  end

  @doc "Aplica un movimiento; devuelve {:ok, tablero, eventos} o {:error, razon}."
  def aplicar_movimiento(tablero, jugador_id, ficha_id, dado, jugadores) do
    fichas = Map.get(tablero, jugador_id, [])

    case Enum.find(fichas, &(&1.id == ficha_id)) do
      nil ->
        {:error, :ficha_no_encontrada}

      ficha ->
        color     = get_color(jugadores, jugador_id)
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

  @doc "Devuelve la lista de {row, col} que recorre la ficha paso a paso (para animacion)."
  def pasos_de_movimiento(:casa, color, _dado) do
    [Board.cell_coords(Board.casilla_salida(color))]
  end

  def pasos_de_movimiento(pos_inicial, color, dado) do
    Enum.scan(1..dado, pos_inicial, fn _i, pos -> sig_pos(pos, color) end)
    |> Enum.map(fn
      {:camino, n}  -> Board.cell_coords(n)
      {:pasillo, p} -> Enum.at(Board.home_lane_coords(color), p - 1)
      :meta         -> {7, 7}
      _             -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ── Validacion de movimiento ───────────────────────────────────────────────────

  defp puede_mover?(:casa, _color, 6), do: true
  defp puede_mover?(:casa, _color, _), do: false
  defp puede_mover?(:meta, _color, _), do: false

  defp puede_mover?({:camino, n}, color, dado) do
    entry           = Board.home_entry(color)
    steps_to_entry  = rem(entry - n + 52, 52)
    steps_beyond    = dado - steps_to_entry
    # No puede pasarse de la meta
    dado <= steps_to_entry || steps_beyond <= 6
  end

  defp puede_mover?({:pasillo, pos}, _color, dado), do: pos + dado <= 6

  # ── Calculo de posicion nueva ─────────────────────────────────────────────────

  defp nueva_posicion(:casa, color, 6), do: {:camino, Board.casilla_salida(color)}

  defp nueva_posicion({:camino, n}, color, dado) do
    entry          = Board.home_entry(color)
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
      6             -> :meta
      p when p < 6 -> {:pasillo, p}
      p             -> {:pasillo, 12 - p}
    end
  end

  # ── Capturas ──────────────────────────────────────────────────────────────────

  defp resolver_capturas(tablero, atacante_id, {:camino, n}, jugadores) do
    if Board.celda_segura?(n) do
      {tablero, []}
    else
      Enum.reduce(jugadores, {tablero, []}, fn jugador, {t, caps} ->
        if jugador.id == atacante_id do
          {t, caps}
        else
          fichas     = Map.get(t, jugador.id, [])
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

  # ── Utilidades internas ───────────────────────────────────────────────────────

  defp sig_pos(:casa, color), do: {:camino, Board.casilla_salida(color)}

  defp sig_pos({:camino, n}, color) do
    if n == Board.home_entry(color),
      do:   {:pasillo, 1},
      else: {:camino, rem(n, 52) + 1}
  end

  defp sig_pos({:pasillo, p}, _color) when p >= 5, do: :meta
  defp sig_pos({:pasillo, p}, _color), do: {:pasillo, p + 1}
  defp sig_pos(:meta, _color), do: :meta

  defp todas_en_meta?(tablero, jugador_id) do
    tablero |> Map.get(jugador_id, []) |> Enum.all?(&(&1.pos == :meta))
  end

  defp get_color(jugadores, jugador_id) do
    case Enum.find(jugadores, &(&1.id == jugador_id)) do
      nil -> nil
      j   -> j.color
    end
  end

  defp maybe_add(list, event, true),  do: [event | list]
  defp maybe_add(list, _event, false), do: list
end
