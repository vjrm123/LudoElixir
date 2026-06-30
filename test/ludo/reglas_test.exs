defmodule Ludo.ReglasTest do
  use ExUnit.Case, async: true

  alias Ludo.Reglas

  describe "equipo_de_color/1" do
    test "rojo y amarillo son equipo A" do
      assert Reglas.equipo_de_color(:rojo) == :equipo_a
      assert Reglas.equipo_de_color(:amarillo) == :equipo_a
    end

    test "azul y verde son equipo B" do
      assert Reglas.equipo_de_color(:azul) == :equipo_b
      assert Reglas.equipo_de_color(:verde) == :equipo_b
    end
  end

  describe "mismo_equipo?/2" do
    test "rojo y amarillo son mismo equipo" do
      assert Reglas.mismo_equipo?(:rojo, :amarillo)
    end

    test "azul y verde son mismo equipo" do
      assert Reglas.mismo_equipo?(:azul, :verde)
    end

    test "rojo y azul son diferente equipo" do
      refute Reglas.mismo_equipo?(:rojo, :azul)
    end
  end

  describe "fichas_movibles/4" do
    test "ficha en casa solo se mueve con 6" do
      tablero = %{"j1" => [%{id: 1, pos: :casa}]}
      assert Reglas.fichas_movibles(tablero, "j1", :rojo, 6) == [1]
      assert Reglas.fichas_movibles(tablero, "j1", :rojo, 5) == []
    end

    test "ficha en meta nunca se mueve" do
      tablero = %{"j1" => [%{id: 1, pos: :meta}]}
      assert Reglas.fichas_movibles(tablero, "j1", :rojo, 6) == []
    end

    test "ficha en camino se mueve si no se pasa de meta" do
      # rojo: entry en 51, salida en 1. Ficha en 50: steps_to_entry = 1
      # con dado 1 llega a entry, con dado 8 se pasa (steps_beyond = 7 > 6)
      tablero = %{"j1" => [%{id: 1, pos: {:camino, 50}}]}
      assert Reglas.fichas_movibles(tablero, "j1", :rojo, 1) == [1]
      assert Reglas.fichas_movibles(tablero, "j1", :rojo, 8) == []
    end

    test "ficha en pasillo no se pasa de 6" do
      tablero = %{"j1" => [%{id: 1, pos: {:pasillo, 4}}]}
      assert Reglas.fichas_movibles(tablero, "j1", :rojo, 2) == [1]
      assert Reglas.fichas_movibles(tablero, "j1", :rojo, 3) == []
    end
  end

  describe "aplicar_movimiento/5 — capturas" do
    setup do
      jugadores = [
        %{id: "rojo", nombre: "Rojo", color: :rojo},
        %{id: "azul", nombre: "Azul", color: :azul}
      ]

      %{jugadores: jugadores}
    end

    test "captura ficha enemiga en celda no segura", ctx do
      # rojo desde 8 con dado 2 → 10 donde esta azul
      tablero2 = %{
        "rojo" => [%{id: 1, pos: {:camino, 8}}],
        "azul" => [%{id: 1, pos: {:camino, 10}}]
      }

      assert {:ok, tablero_nuevo, eventos} =
               Reglas.aplicar_movimiento(tablero2, "rojo", 1, 2, ctx.jugadores)

      assert :ficha_capturada in eventos
      # azul vuelve a casa
      assert [%{pos: :casa}] = Map.get(tablero_nuevo, "azul")
    end

    test "no captura en celda segura", ctx do
      # celda 1 es segura (salida de rojo)
      tablero = %{
        "rojo" => [%{id: 1, pos: {:camino, 52}}],
        "azul" => [%{id: 1, pos: {:camino, 1}}]
      }

      assert {:ok, _tablero, eventos} =
               Reglas.aplicar_movimiento(tablero, "rojo", 1, 1, ctx.jugadores)

      refute :ficha_capturada in eventos
    end

    test "no captura entre compañeros de equipo", _ctx do
      jugadores = [
        %{id: "rojo", nombre: "Rojo", color: :rojo},
        %{id: "amarillo", nombre: "Amarillo", color: :amarillo}
      ]

      tablero = %{
        "rojo" => [%{id: 1, pos: {:camino, 8}}],
        "amarillo" => [%{id: 1, pos: {:camino, 10}}]
      }

      assert {:ok, _tablero, eventos} =
               Reglas.aplicar_movimiento(tablero, "rojo", 1, 2, jugadores)

      refute :ficha_capturada in eventos
    end

    test "no captura bloqueo (2+ fichas del mismo color)", ctx do
      tablero = %{
        "rojo" => [%{id: 1, pos: {:camino, 8}}],
        "azul" => [%{id: 1, pos: {:camino, 10}}, %{id: 2, pos: {:camino, 10}}]
      }

      assert {:ok, _tablero, eventos} =
               Reglas.aplicar_movimiento(tablero, "rojo", 1, 2, ctx.jugadores)

      refute :ficha_capturada in eventos
    end
  end

  describe "aplicar_movimiento/5 — meta y victoria" do
    test "llega a meta genera evento :ficha_en_meta" do
      jugadores = [%{id: "r1", nombre: "R", color: :rojo}]
      # rojo entry en 51. Ficha en pasillo 5 con dado 1 → meta
      tablero = %{"r1" => [%{id: 1, pos: {:pasillo, 5}}]}

      assert {:ok, _tab, eventos} =
               Reglas.aplicar_movimiento(tablero, "r1", 1, 1, jugadores)

      assert :ficha_en_meta in eventos
    end

    test "meter las 4 fichas genera :jugador_gana" do
      jugadores = [%{id: "r1", nombre: "R", color: :rojo}]
      # 3 ya en meta, 1 en pasillo 5 con dado 1
      tablero = %{
        "r1" => [
          %{id: 1, pos: :meta},
          %{id: 2, pos: :meta},
          %{id: 3, pos: :meta},
          %{id: 4, pos: {:pasillo, 5}}
        ]
      }

      assert {:ok, _tab, eventos} =
               Reglas.aplicar_movimiento(tablero, "r1", 4, 1, jugadores)

      assert :jugador_gana in eventos
    end
  end

  describe "equipo_gana?/3" do
    test "true cuando el jugador tiene todas en meta" do
      jugadores = [%{id: "r1", nombre: "R", color: :rojo}]

      tablero = %{
        "r1" => [
          %{id: 1, pos: :meta},
          %{id: 2, pos: :meta},
          %{id: 3, pos: :meta},
          %{id: 4, pos: :meta}
        ]
      }

      assert Reglas.equipo_gana?(tablero, jugadores, "r1")
    end

    test "true cuando el compañero de equipo tiene todas en meta" do
      jugadores = [
        %{id: "r1", nombre: "R", color: :rojo},
        %{id: "a1", nombre: "A", color: :amarillo}
      ]

      tablero = %{
        "r1" => [%{id: 1, pos: {:camino, 5}}],
        "a1" => [
          %{id: 1, pos: :meta},
          %{id: 2, pos: :meta},
          %{id: 3, pos: :meta},
          %{id: 4, pos: :meta}
        ]
      }

      assert Reglas.equipo_gana?(tablero, jugadores, "r1")
    end

    test "false cuando nadie del equipo ha ganado" do
      jugadores = [
        %{id: "r1", nombre: "R", color: :rojo},
        %{id: "a1", nombre: "A", color: :amarillo}
      ]

      tablero = %{
        "r1" => [%{id: 1, pos: {:camino, 5}}],
        "a1" => [%{id: 1, pos: {:camino, 10}}]
      }

      refute Reglas.equipo_gana?(tablero, jugadores, "r1")
    end

    test "false cuando el otro equipo ha ganado (no el tuyo)" do
      jugadores = [
        %{id: "r1", nombre: "R", color: :rojo},
        %{id: "z1", nombre: "Z", color: :azul}
      ]

      tablero = %{
        "r1" => [%{id: 1, pos: {:camino, 5}}],
        "z1" => [
          %{id: 1, pos: :meta},
          %{id: 2, pos: :meta},
          %{id: 3, pos: :meta},
          %{id: 4, pos: :meta}
        ]
      }

      refute Reglas.equipo_gana?(tablero, jugadores, "r1")
    end
  end

  describe "aplicar_movimiento/5 — equipo gana" do
    test "emite :equipo_gana cuando compañero ya tiene todas en meta" do
      jugadores = [
        %{id: "r1", nombre: "R", color: :rojo},
        %{id: "a1", nombre: "A", color: :amarillo}
      ]

      # a1 ya tiene las 4 en meta, r1 mete la 4ta
      tablero = %{
        "r1" => [
          %{id: 1, pos: :meta},
          %{id: 2, pos: :meta},
          %{id: 3, pos: :meta},
          %{id: 4, pos: {:pasillo, 5}}
        ],
        "a1" => [
          %{id: 1, pos: :meta},
          %{id: 2, pos: :meta},
          %{id: 3, pos: :meta},
          %{id: 4, pos: :meta}
        ]
      }

      assert {:ok, _tab, eventos} =
               Reglas.aplicar_movimiento(tablero, "r1", 4, 1, jugadores)

      assert :jugador_gana in eventos
      assert :equipo_gana in eventos
    end
  end

  describe "pasos_de_movimiento/3" do
    test "desde casa da solo la salida" do
      pasos = Reglas.pasos_de_movimiento(:casa, :rojo, 6)
      assert pasos == [Ludo.Board.cell_coords(1)]
    end

    test "desde camino da N pasos" do
      pasos = Reglas.pasos_de_movimiento({:camino, 1}, :rojo, 3)
      assert length(pasos) == 3
    end

    test "rebote en pasillo: pasillo 4 con dado 4 rebota a pasillo 4" do
      # Pasillo rojo: [{7,1},{7,2},{7,3},{7,4},{7,5}]
      # Desde pos 4, dado 4: 5 → meta → 5 → 4
      pasos = Reglas.pasos_de_movimiento({:pasillo, 4}, :rojo, 4)
      assert pasos == [{7, 5}, {7, 7}, {7, 5}, {7, 4}]
    end

    test "rebote en pasillo: pasillo 3 con dado 5 rebota a pasillo 4" do
      # Desde pos 3, dado 5: 4 → 5 → meta → 5 → 4
      pasos = Reglas.pasos_de_movimiento({:pasillo, 3}, :rojo, 5)
      assert pasos == [{7, 4}, {7, 5}, {7, 7}, {7, 5}, {7, 4}]
    end

    test "sin rebote: pasillo 3 con dado 3 llega a meta" do
      # 3 → 4 → 5 → meta(6)
      pasos = Reglas.pasos_de_movimiento({:pasillo, 3}, :rojo, 3)
      assert List.last(pasos) == {7, 7}
    end
  end
end
