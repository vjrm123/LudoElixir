defmodule LudoWeb.PageControllerTest do
  use LudoWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")

    document =
      conn
      |> html_response(200)
      |> LazyHTML.from_fragment()

    assert LazyHTML.filter(document, "#inicio-session") != []
    assert LazyHTML.filter(document, "#inicio-modo-crear") != []
    assert LazyHTML.filter(document, "#inicio-modo-unirse") != []
  end
end
