defmodule Ludo.Estado do
  @enforce_keys [:codigo, :host_id]
  defstruct [
    :codigo,
    :host_id,
    jugadores: [],
    # :clasico | :equipos
    modo: :clasico,
    # :esperando | :jugando | :finalizada
    fase: :esperando,
    turno_idx: 0,
    dado: nil,
    # jugador_id => [%{id, pos}]
    tablero: %{},
    # ids de fichas que pueden moverse este turno
    fichas_movibles: []
  ]

  # Avanza al siguiente jugador o repite turno si saco 6
  def avanzar_turno(%__MODULE__{} = estado, dado) do
    n = length(estado.jugadores)

    if dado == 6 && estado.fase == :jugando do
      %{estado | dado: nil, fichas_movibles: []}
    else
      %{estado | dado: nil, fichas_movibles: [], turno_idx: rem(estado.turno_idx + 1, n)}
    end
  end

  # Avanza el turno solo si el dado no fue 6 o si alguien ya gano
  def avanzar_turno_si_no_seis(%__MODULE__{} = estado, dado, eventos) do
    if :jugador_gana in eventos or :equipo_gana in eventos do
      estado
    else
      avanzar_turno(estado, dado)
    end
  end

  # Marca la partida como finalizada si alguien metio todas sus fichas
  def finalizar(%__MODULE__{} = estado, eventos) do
    if :jugador_gana in eventos or :equipo_gana in eventos do
      %{estado | fase: :finalizada}
    else
      estado
    end
  end
end
