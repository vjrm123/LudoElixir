defmodule Ludo.Board do
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

  # Celdas del pasillo de llegada de cada color (posicion 1 = entrada, 5 = junto a la meta)
  @home_lanes %{
    rojo:     [{7,1},{7,2},{7,3},{7,4},{7,5}],
    azul:     [{1,7},{2,7},{3,7},{4,7},{5,7}],
    verde:    [{13,7},{12,7},{11,7},{10,7},{9,7}],
    amarillo: [{7,13},{7,12},{7,11},{7,10},{7,9}]
  }

  # Ultima celda del camino principal antes de entrar al pasillo de cada color
  @home_entry %{rojo: 51, azul: 12, verde: 38, amarillo: 25}

  # Celdas seguras donde no se puede capturar fichas rivales
  @safe_cells MapSet.new([1, 14, 27, 40])

  # Mapa n => {row, col} calculado en tiempo de compilacion
  @cell_coords @path |> Enum.with_index(1) |> Map.new(fn {rc, n} -> {n, rc} end)

  #  Coordenadas

  def cell_coords(n),          do: Map.get(@cell_coords, n)
  def home_lane_coords(color), do: Map.get(@home_lanes, color, [])
  def home_entry(color),       do: @home_entry[color]
  def celda_segura?(n),        do: MapSet.member?(@safe_cells, n)

  # Todas las coordenadas del camino principal, sin orden particular.
  # Usado por la UI para saber que celdas son parte del camino sin
  # tener que repetir la lista a mano.
  def todas_las_coords, do: Map.values(@cell_coords)

  #Casillas de salida por color

  def casilla_salida(:rojo),     do: 1
  def casilla_salida(:azul),     do: 14
  def casilla_salida(:verde),    do: 40
  def casilla_salida(:amarillo), do: 27

  # Tablero inicial

  def nuevo(jugadores) do
    Map.new(jugadores, fn jugador ->
      fichas = Enum.map(1..4, &%{id: &1, pos: :casa})
      {jugador.id, fichas}
    end)
  end
end
