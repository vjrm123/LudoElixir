defmodule Ludo.GameServerTest do
  use ExUnit.Case, async: false

  alias Ludo.GameServer
  alias Ludo.Salas

  test "tres 6 seguidos hacen perder el turno" do
    {:ok, %{codigo: codigo, host_id: j1}} = Salas.crear_sala("Uno", :rojo)
    {:ok, %{jugador_id: _j2}} = Salas.unirse_sala(codigo, "Dos", :azul)
    {:ok, _} = GameServer.iniciar(codigo, j1)

    # j1 saca tres 6 seguidos, moviendo una ficha distinta entre cada tirada
    {:ok, 6} = GameServer.tirar_dado_fijo(codigo, j1, 6)
    {:ok, _} = GameServer.mover_ficha(codigo, j1, 1)
    {:ok, 6} = GameServer.tirar_dado_fijo(codigo, j1, 6)
    {:ok, _} = GameServer.mover_ficha(codigo, j1, 2)
    {:ok, 6} = GameServer.tirar_dado_fijo(codigo, j1, 6)

    # En el tercer 6 el jugador no puede mover y queda a la espera del cambio forzado
    {:ok, antes} = GameServer.get_estado(codigo)
    assert antes.turno_idx == 0
    assert antes.dado == 6
    assert antes.fichas_movibles == []
    assert antes.seis_seguidos == 3

    # Tras el temporizador (2s) el turno pasa solo al siguiente jugador
    Process.sleep(2200)
    {:ok, despues} = GameServer.get_estado(codigo)
    assert despues.turno_idx == 1
    assert despues.dado == nil
    assert despues.seis_seguidos == 0
  end

  test "dos 6 seguidos NO pierden el turno (se sigue jugando)" do
    {:ok, %{codigo: codigo, host_id: j1}} = Salas.crear_sala("Uno", :rojo)
    {:ok, %{jugador_id: _j2}} = Salas.unirse_sala(codigo, "Dos", :azul)
    {:ok, _} = GameServer.iniciar(codigo, j1)

    {:ok, 6} = GameServer.tirar_dado_fijo(codigo, j1, 6)
    {:ok, _} = GameServer.mover_ficha(codigo, j1, 1)
    {:ok, 6} = GameServer.tirar_dado_fijo(codigo, j1, 6)

    {:ok, estado} = GameServer.get_estado(codigo)
    assert estado.turno_idx == 0
    assert estado.seis_seguidos == 2
    refute estado.fichas_movibles == []
  end
end
