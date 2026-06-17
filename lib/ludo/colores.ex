# lib/ludo/colores.ex
defmodule Ludo.Colores do
  # Fuente unica de verdad para los colores de jugador (sala/lobby).
  # El tablero usa su propia paleta mas saturada en tablero_live.ex,
  # asi que no se mezcla con esta.

  @lista [:rojo, :azul, :verde, :amarillo]
  @hex %{rojo: "#ef4444", azul: "#3b82f6", verde: "#10b981", amarillo: "#f59e0b"}

  def lista, do: @lista
  def hex(color), do: Map.get(@hex, color)
  def mapa_hex, do: @hex
end
