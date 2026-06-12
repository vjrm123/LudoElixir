import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")


// Colores hex de cada equipo para los tokens fantasma de la animación de movimiento
const TOKEN_COLORS = {
  "bg-red-500":     "#ef4444",
  "bg-blue-500":    "#3b82f6",
  "bg-emerald-500": "#10b981",
  "bg-amber-500":   "#f59e0b"
}

let Hooks = {}

// Guarda y restaura el ID del jugador en sessionStorage para que al recargar la página
// el jugador vuelva a la misma sala sin tener que volver a unirse
Hooks.JugadorSession = {
  mounted() {
    this.handleEvent("set_jugador_id", ({ jugador_id, codigo }) => {
      sessionStorage.setItem(`ludo_jugador_${codigo}`, jugador_id)
    })

    const codigo    = this.el.dataset.codigo
    const jugadorId = codigo && sessionStorage.getItem(`ludo_jugador_${codigo}`)
    if (jugadorId) this.pushEvent("restore_jugador", { jugador_id: jugadorId })
  }
}

// Anima el movimiento de una ficha paso a paso creando un token fantasma que viaja
// por el camino mientras la ficha real ya está en la posición final en el servidor
Hooks.BoardHook = {
  mounted() {
    this.handleEvent("animar_token", ({ token_id, color_class, inicio, pasos, intervalo }) => {
      const board = this.el

      // Ocultar la ficha real hasta que termine la animación
      const realToken = document.getElementById(`token-${token_id}`)
      if (realToken) realToken.style.visibility = "hidden"

      // Calcula el centro de una celda relativo al tablero
      const centerOf = (row, col) => {
        const cell = document.getElementById(`cell-${row}-${col}`)
        if (!cell) return null
        const cr = cell.getBoundingClientRect()
        const br = board.getBoundingClientRect()
        return { x: cr.left - br.left + cr.width / 2, y: cr.top - br.top + cr.height / 2 }
      }

      const startPos = centerOf(inicio[0], inicio[1])
      if (!startPos) {
        if (realToken) realToken.style.visibility = ""
        return
      }

      // Crear el token fantasma que se moverá visualmente por el tablero
      const ghost = document.createElement("div")
      Object.assign(ghost.style, {
        position:        "absolute",
        width:           "20px",
        height:          "20px",
        borderRadius:    "50%",
        border:          "2px solid white",
        backgroundColor: TOKEN_COLORS[color_class] || "#c8f07a",
        display:         "flex",
        alignItems:      "center",
        justifyContent:  "center",
        fontSize:        "0.5rem",
        fontWeight:      "800",
        color:           "white",
        boxShadow:       "0 2px 8px rgba(0,0,0,.35)",
        zIndex:          "50",
        pointerEvents:   "none",
        transform:       "translate(-50%, -50%)",
        transition:      `left ${intervalo * 0.75}ms ease, top ${intervalo * 0.75}ms ease`,
        left:            `${startPos.x}px`,
        top:             `${startPos.y}px`
      })
      ghost.textContent = token_id.split("-").pop()
      board.appendChild(ghost)

      // Mover el fantasma celda por celda hasta el destino final
      let step = 0
      const next = () => {
        if (step >= pasos.length) {
          ghost.remove()
          if (realToken) realToken.style.visibility = ""
          return
        }
        const pos = centerOf(pasos[step][0], pasos[step][1])
        if (pos) {
          ghost.style.left = `${pos.x}px`
          ghost.style.top  = `${pos.y}px`
        }
        step++
        setTimeout(next, intervalo)
      }

      // Doble rAF para que el estado inicial del ghost quede pintado antes de moverse
      requestAnimationFrame(() => requestAnimationFrame(() => next()))
    })
  }
}

// Animación del dado: gira rápido mostrando números aleatorios y frena hasta mostrar el resultado real.
// Espera dos frames para que el elemento ya est pintado antes de iniciar la tran.
Hooks.DiceHook = {
  mounted() {
    const v = parseInt(this.el.dataset.valor)
    if (!isNaN(v)) {
      requestAnimationFrame(() => requestAnimationFrame(() => this.roll(v)))
    }
  },
  roll(final) {
    const el  = this.el
    let   n   = 0
    const max = 8   // 6 giros rpidos + 2 lentos 

    const flip = () => {
      const speed = n < max - 2 ? 65 : 120   // rapido al principio lento al final

      // Rotar hacia el canto — la cara queda oculta
      el.style.transition = `transform ${speed}ms ease-in`
      el.style.transform  = "perspective(200px) rotateY(90deg)"

      setTimeout(() => {
        // Cambiar el nmero mientras esta girado 
        el.textContent = n < max - 1
          ? Math.floor(Math.random() * 6) + 1
          : final

        // Volver al frente mostrando el numero nuevo
        el.style.transition = `transform ${speed}ms ease-out`
        el.style.transform  = "perspective(200px) rotateY(0deg)"

        n++
        if (n < max) {
          setTimeout(flip, speed * 2 + 10)
        } else {
          // Limpiar el transform para que el nmero final quede esttico y visible
          setTimeout(() => {
            el.style.transition = "none"
            el.style.transform  = ""
          }, speed + 10)
        }
      }, speed)
    }

    flip()
  }
}

// Conexin con Phoenix LiveView
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})

// Al navegar a otra pagina reproducir la animacin de salida
window.addEventListener("phx:page-loading-start", info => {
  topbar.show(300)
  if (info.detail?.kind === "redirect") {
    document.querySelectorAll(".page-emerge").forEach(el => {
      el.style.animation = "page-retreat 0.35s cubic-bezier(0.64,0,0.78,0) forwards"
    })
  }
})
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// en el mismo momento del clic, antes de que LiveView responda con el nuevo contenido
document.addEventListener("click", e => {
  const btn = e.target.closest("#inicio-modo-crear, #inicio-modo-unirse, #inicio-volver")
  if (btn) {
    document.querySelectorAll(".page-emerge").forEach(el => {
      el.style.animation = "page-retreat 0.28s cubic-bezier(0.64,0,0.78,0) forwards"
    })
  }
})

liveSocket.connect()
window.liveSocket = liveSocket
