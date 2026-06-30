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
    fichas_movibles: [],
    # cuantos 6 seguidos lleva el jugador en turno (a los 3 pierde el turno)
    seis_seguidos: 0
  ]

  # Avanza al siguiente jugador o repite turno si saco 6
  def avanzar_turno(%__MODULE__{} = estado, dado) do
    if dado == 6 && estado.fase == :jugando do
      # Repite turno; conserva el contador de seises para detectar el tercero
      %{estado | dado: nil, fichas_movibles: []}
    else
      pasar_turno(estado)
    end
  end

  # Pasa el turno al siguiente jugador incondicionalmente y reinicia el
  # contador de seises. Se usa al avanzar normalmente y cuando un jugador
  # pierde el turno por sacar tres 6 seguidos.
  def pasar_turno(%__MODULE__{} = estado) do
    n = length(estado.jugadores)

    %{
      estado
      | dado: nil,
        fichas_movibles: [],
        seis_seguidos: 0,
        turno_idx: rem(estado.turno_idx + 1, n)
    }
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
