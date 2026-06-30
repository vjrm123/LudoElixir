defmodule Ludo.EstadoTest do
  use ExUnit.Case, async: true

  alias Ludo.Estado

  defp estado_jugando(attrs) do
    base = %Estado{
      codigo: "TEST01",
      host_id: "j1",
      jugadores: [
        %{id: "j1", nombre: "Uno", color: :rojo},
        %{id: "j2", nombre: "Dos", color: :azul}
      ],
      fase: :jugando,
      turno_idx: 0
    }

    Map.merge(base, attrs)
  end

  describe "avanzar_turno/2" do
    test "con 6 repite turno y conserva el contador de seises" do
      estado = estado_jugando(%{dado: 6, seis_seguidos: 2})
      nuevo = Estado.avanzar_turno(estado, 6)

      assert nuevo.turno_idx == 0
      assert nuevo.dado == nil
      assert nuevo.seis_seguidos == 2
    end

    test "con valor distinto de 6 pasa al siguiente y reinicia el contador" do
      estado = estado_jugando(%{dado: 3, seis_seguidos: 1})
      nuevo = Estado.avanzar_turno(estado, 3)

      assert nuevo.turno_idx == 1
      assert nuevo.dado == nil
      assert nuevo.seis_seguidos == 0
    end
  end

  describe "pasar_turno/1" do
    test "siempre avanza al siguiente jugador y reinicia el contador, aunque venga de un 6" do
      estado = estado_jugando(%{dado: 6, seis_seguidos: 3, turno_idx: 0})
      nuevo = Estado.pasar_turno(estado)

      assert nuevo.turno_idx == 1
      assert nuevo.dado == nil
      assert nuevo.seis_seguidos == 0
    end

    test "da la vuelta desde el ultimo jugador al primero" do
      estado = estado_jugando(%{turno_idx: 1})
      assert Estado.pasar_turno(estado).turno_idx == 0
    end
  end
end
