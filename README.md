# Procesamiento paralelo de imágenes con Scheme y Erlang

Implementación del proyecto usando imágenes PPM P3. Erlang coordina la concurrencia y divide la imagen; cada trabajador ejecuta una instancia independiente de Scheme para transformar su región.

## Requisitos

- Erlang/OTP con `erl`, `erlc` y `escript`.
- GNU Guile (recomendado) o Racket.

El programa detecta automáticamente:

1. `guile` y lo ejecuta con `guile -s`.
2. si no existe Guile, `racket` con `racket -f`.

Si el profesor utiliza otro Scheme, se puede indicar el comando:

```bash
export SCHEME_CMD="comando-del-interprete"
```

El comando indicado debe aceptar como último argumento un archivo `.scm` para ejecutar.

## Restricciones aplicadas en Scheme

El archivo `scheme/image_processor.scm` no utiliza `if`, `set!`, `let`, `while` ni `cons`. Las funciones se definen con `lambda`; se utilizan `cond`, recursión, listas y `map`.

## Ejecución mínima

Desde la raíz del proyecto:

```bash
./image_processor tests/entrada.ppm salida.ppm 1
./image_processor tests/entrada.ppm salida.ppm 2
./image_processor tests/entrada.ppm salida.ppm 4
./image_processor tests/entrada.ppm salida.ppm 8
```

Sin indicar filtro se utiliza Gaussian Blur 3x3.

## Filtros

```bash
./image_processor entrada.ppm salida.ppm 4 gaussian 3
./image_processor entrada.ppm salida.ppm 4 gaussian 5
./image_processor entrada.ppm salida.ppm 4 grayscale
./image_processor entrada.ppm salida.ppm 4 invert
./image_processor entrada.ppm salida.ppm 4 brightness 30
./image_processor entrada.ppm salida.ppm 4 brightness -30
./image_processor entrada.ppm salida.ppm 4 threshold 128
./image_processor entrada.ppm salida.ppm 4 sharpen
./image_processor entrada.ppm salida.ppm 4 sobel
```

## Benchmark

El modo benchmark ejecuta 1, 2, 4 y 8 procesos, genera una imagen por configuración y un CSV con tiempo, speedup y eficiencia.

```bash
./image_processor --benchmark tests/entrada.ppm resultados/gaussian gaussian 3
```

Produce:

```text
resultados/gaussian_1.ppm
resultados/gaussian_2.ppm
resultados/gaussian_4.ppm
resultados/gaussian_8.ppm
resultados/gaussian_benchmark.csv
```

Las métricas son:

```text
Sp = T1 / Tp
Ep = Sp / p
```

## Protocolo Erlang -> Scheme

Cada trabajador crea una solicitud independiente con la forma:

```scheme
(request filtro tamano-kernel parametro filas-halo-arriba alto-bloque region-con-halo)
```

Por ejemplo:

```scheme
(request gaussian 3 0 1 20 (((255 0 0) (0 255 0)) ...))
```

Scheme procesa la región completa recibida, incluyendo el halo, pero recorta el resultado antes de devolverlo. Por ello solamente devuelve las filas pertenecientes al bloque asignado al proceso Erlang.

La salida de Scheme es una secuencia de componentes RGB separados por espacios. Erlang conoce el ancho y la altura esperados, valida la cantidad de píxeles y reconstruye las filas.

## Halo y bordes

Para un kernel impar de tamaño `k`, Erlang utiliza:

```text
halo = k / 2
```

Cada región recibe las filas vecinas que necesita. En los límites reales de la imagen, Scheme utiliza la estrategia **repetir el píxel más cercano**.

Gaussian admite 3x3 y 5x5. Sharpen y Sobel utilizan kernel 3x3. Los filtros sin convolución no requieren halo.

## Tolerancia a fallos

Cada trabajador captura errores de su instancia de Scheme y los comunica al coordinador. Si una ejecución de Scheme falla, se realiza un reintento automático. Si vuelve a fallar, el coordinador cancela la generación de la imagen final y devuelve las regiones que fallaron.

También se detectan:

- ausencia de intérprete Scheme;
- salida de Scheme inexistente o incompleta;
- timeout de Scheme;
- PPM inválido;
- cantidad incorrecta de píxeles;
- filtro o parámetros inválidos.

El timeout por defecto es de 300000 ms. Se puede cambiar con:

```bash
export SCHEME_TIMEOUT_MS=600000
```

## Estructura

```text
image-processor/
├── image_processor
├── erlang/
│   └── startup.erl
├── scheme/
│   └── image_processor.scm
├── tests/
│   ├── entrada.ppm
│   └── probar.sh
├── docs/
│   └── informe_base.md
├── funcionales.pdf
└── README.md
```

## Compilación manual de Erlang

No es necesaria si se usa `./image_processor`, porque el `escript` compila `startup.erl` automáticamente. Para compilar manualmente:

```bash
erlc -o erlang erlang/startup.erl
```

Después se puede usar el shell de Erlang:

```erlang
startup:procesarImagen("tests/entrada.ppm", "salida.ppm", 4, 3).
startup:procesarImagen("tests/entrada.ppm", "salida_sobel.ppm", 4, sobel, 0, 3).
startup:benchmark("tests/entrada.ppm", "resultados/prueba", gaussian, 0, 3).
```
