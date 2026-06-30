defmodule Ludo.Reglas do
  alias Ludo.Board

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
        color = get_color(jugadores, jugador_id)
        nueva_pos = nueva_posicion(ficha.pos, color, dado)

        fichas_nuevas =
          Enum.map(fichas, fn f ->
            if f.id == ficha_id, do: %{f | pos: nueva_pos}, else: f
          end)

        tablero2 = Map.put(tablero, jugador_id, fichas_nuevas)
        {tablero3, capturas} = resolver_capturas(tablero2, jugador_id, nueva_pos, jugadores)

        jugador_gana = todas_en_meta?(tablero3, jugador_id)

        eventos =
          []
          |> maybe_add(:ficha_capturada, capturas != [])
          |> maybe_add(:ficha_en_meta, nueva_pos == :meta)
          |> maybe_add(:jugador_gana, jugador_gana)
          |> maybe_add(
            :equipo_gana,
            jugador_gana && equipo_gana?(tablero3, jugadores, jugador_id)
          )

        {:ok, tablero3, eventos}
    end
  end

  @doc "Devuelve la lista de {row, col} que recorre la ficha paso a paso (para animacion)."
  def pasos_de_movimiento(:casa, color, _dado) do
    [Board.cell_coords(Board.casilla_salida(color))]
  end

  def pasos_de_movimiento(pos_inicial, color, dado) do
    case pos_inicial do
      {:pasillo, _} ->
        pos_inicial
        |> pasos_pasillo(dado)
        |> Enum.map(fn
          {:pasillo, p} -> Enum.at(Board.home_lane_coords(color), p - 1)
          :meta -> {7, 7}
        end)

      _ ->
        Enum.scan(1..dado, pos_inicial, fn _i, pos -> sig_pos(pos, color) end)
        |> Enum.map(fn
          {:camino, n} -> Board.cell_coords(n)
          {:pasillo, p} -> Enum.at(Board.home_lane_coords(color), p - 1)
          :meta -> {7, 7}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)
    end
  end

  #  Validacion de movimiento

  defp puede_mover?(:casa, _color, 6), do: true
  defp puede_mover?(:casa, _color, _), do: false
  defp puede_mover?(:meta, _color, _), do: false

  defp puede_mover?({:camino, n}, color, dado) do
    entry = Board.home_entry(color)
    steps_to_entry = rem(entry - n + 52, 52)
    steps_beyond = dado - steps_to_entry
    # No puede pasarse de la meta
    dado <= steps_to_entry || steps_beyond <= 6
  end

  defp puede_mover?({:pasillo, pos}, _color, dado), do: pos + dado <= 6

  #  Calculo de posicion nueva

  defp nueva_posicion(:casa, color, 6), do: {:camino, Board.casilla_salida(color)}

  defp nueva_posicion({:camino, n}, color, dado) do
    entry = Board.home_entry(color)
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
      p -> {:pasillo, 12 - p}
    end
  end

  # Capturas

  defp resolver_capturas(tablero, atacante_id, {:camino, n}, jugadores) do
    if Board.celda_segura?(n) do
      {tablero, []}
    else
      color_atacante = get_color(jugadores, atacante_id)

      Enum.reduce(jugadores, {tablero, []}, fn jugador, {t, caps} ->
        if jugador.id == atacante_id or mismo_equipo?(jugador.color, color_atacante) do
          {t, caps}
        else
          fichas = Map.get(t, jugador.id, [])
          on_cell = Enum.filter(fichas, &(&1.pos == {:camino, n}))

          cond do
            on_cell == [] ->
              {t, caps}

            length(on_cell) >= 2 ->
              {t, caps}

            true ->
              nuevas =
                Enum.map(fichas, fn f ->
                  if f.pos == {:camino, n}, do: %{f | pos: :casa}, else: f
                end)

              {Map.put(t, jugador.id, nuevas), caps ++ on_cell}
          end
        end
      end)
    end
  end

  defp resolver_capturas(tablero, _id, _pos, _jugadores), do: {tablero, []}

  # Equipos

  def equipo_de_color(:rojo), do: :equipo_a
  def equipo_de_color(:amarillo), do: :equipo_a
  def equipo_de_color(:azul), do: :equipo_b
  def equipo_de_color(:verde), do: :equipo_b

  def mismo_equipo?(nil, _), do: false
  def mismo_equipo?(_, nil), do: false
  def mismo_equipo?(color1, color2), do: equipo_de_color(color1) == equipo_de_color(color2)

  def equipo_gana?(tablero, jugadores, jugador_id) do
    case get_color(jugadores, jugador_id) do
      nil ->
        false

      color ->
        Enum.any?(jugadores, fn j ->
          mismo_equipo?(j.color, color) && todas_en_meta?(tablero, j.id)
        end)
    end
  end

  # Utilidades internas

  defp sig_pos(:casa, color), do: {:camino, Board.casilla_salida(color)}

  defp sig_pos({:camino, n}, color) do
    if n == Board.home_entry(color),
      do: {:pasillo, 1},
      else: {:camino, rem(n, 52) + 1}
  end

  defp sig_pos({:pasillo, p}, _color) when p >= 5, do: :meta
  defp sig_pos({:pasillo, p}, _color), do: {:pasillo, p + 1}
  defp sig_pos(:meta, _color), do: :meta

  defp todas_en_meta?(tablero, jugador_id) do
    tablero |> Map.get(jugador_id, []) |> Enum.all?(&(&1.pos == :meta))
  end

  # Pasos para animacion en el pasillo (con rebote)

  defp pasos_pasillo({:pasillo, p}, dado) do
    pasos_pasillo(p, dado, :up, [])
  end

  defp pasos_pasillo(_p, 0, _dir, acc), do: Enum.reverse(acc)

  defp pasos_pasillo(p, n, dir, acc) do
    {step, next_p, next_dir} = step_pasillo(p, dir)
    pasos_pasillo(next_p, n - 1, next_dir, [step | acc])
  end

  defp step_pasillo(:meta, :down), do: {{:pasillo, 5}, 5, :down}
  defp step_pasillo(p, :up) when p >= 5, do: {:meta, :meta, :down}
  defp step_pasillo(p, :up), do: {{:pasillo, p + 1}, p + 1, :up}
  defp step_pasillo(p, :down) when p <= 1, do: {{:pasillo, 1}, 1, :up}
  defp step_pasillo(p, :down), do: {{:pasillo, p - 1}, p - 1, :down}

  defp get_color(jugadores, jugador_id) do
    case Enum.find(jugadores, &(&1.id == jugador_id)) do
      nil -> nil
      j -> j.color
    end
  end

  defp maybe_add(list, event, true), do: [event | list]
  defp maybe_add(list, _event, false), do: list
end
