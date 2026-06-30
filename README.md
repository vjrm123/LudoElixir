# LudoElixir

Juego de Ludo multijugador en tiempo real, construido con Elixir, Phoenix LiveView y OTP.

## Requisitos

- Elixir `~> 1.15` con OTP 26+
- Node.js (solo necesario para `esbuild` / `tailwind` si se reinstalan)

## Ejecución

```bash
# 1. Clonar el repositorio
git clone <repo-url> && cd LudoElixir

# 2. Instalar dependencias + assets (tailwind + esbuild)
mix setup

# 3. Iniciar el servidor (http://localhost:4000)
mix phx.server

# Alternativa: arrancar con consola IEx
iex -S mix phx.server
```

Abrir `http://localhost:4000` en el navegador. Para probar el multijugador en local,
abrir varias pestañas o ventanas distintas y unirse a la misma sala con el código
generado.

## Pruebas

```bash
# Ejecutar toda la suite (30 tests)
mix test

# Ejecutar solo los tests del motor de reglas
mix test test/ludo/reglas_test.exs

# Pre-commit: compila con warnings-as-errors, formatea y corre tests
mix precommit
```

## Exponer el servidor con ngrok

Para que otras personas puedan unirse a una sala desde fuera de tu red local
(sin desplegar a producción), se puede usar [ngrok](https://ngrok.com/) para
crear un túnel HTTPS público hacia `http://localhost:4000`.

### 1. Instalar ngrok

```bash
brew install ngrok          # macOS
# o descargar el binario desde https://ngrok.com/download
```

### 2. Crear cuenta y enlazar el authtoken

1. Registrarse gratis en https://dashboard.ngrok.com/signup
2. Copiar el authtoken desde https://dashboard.ngrok.com/get-started/your-authtoken
3. Guardarlo en la configuración local de ngrok (solo se hace una vez):

```bash
ngrok config add-authtoken <TU_AUTHTOKEN>
```

### 3. Arrancar el servidor y el túnel

En una terminal, levantar Phoenix:

```bash
mix phx.server
```

En otra terminal, exponer el puerto 4000:

```bash
ngrok http 4000
```

ngrok mostrará una URL pública del tipo `https://xxxx-xxxx.ngrok-free.dev` que
redirige a tu `localhost:4000`. Compartir esa URL para que cualquiera pueda
unirse a la sala desde su navegador.

> El config de desarrollo ya tiene `check_origin: false`
> ([config/dev.exs](config/dev.exs)), por lo que LiveView acepta el host de
> ngrok sin cambios adicionales.

## Build de producción

```bash
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```
