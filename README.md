# Procesamiento paralelo de imágenes con Scheme y Erlang

Procesador paralelo de imágenes PPM P3 desarrollado con Erlang y Scheme.

Erlang se encarga de dividir la imagen y ejecutar los procesos concurrentes, mientras que Scheme aplica el filtro solicitado a cada región.

La explicación técnica del funcionamiento interno se encuentra en la documentación PDF del proyecto.

## Requisitos

Es necesario tener instalado:

* Erlang/OTP
* GNU Guile o Racket

Se recomienda GNU Guile.

El programa busca automáticamente:

1. `guile`
2. `racket`, si Guile no está disponible

Para comprobar las instalaciones:

```bash
erl -version
guile --version
```

o:

```bash
racket --version
```

## Ejecución

Los comandos deben ejecutarse desde la raíz del proyecto.

La estructura general es:

```bash
./image_processor ENTRADA SALIDA PROCESOS FILTRO PARAMETROS
```

Por ejemplo:

```bash
./image_processor photos/p1.ppm results/salida.ppm 4 gaussian 3
```

Donde:

* `photos/p1.ppm` es la imagen de entrada.
* `results/salida.ppm` es la imagen que se generará.
* `4` es la cantidad de procesos Erlang.
* `gaussian` es el filtro.
* `3` es el tamaño del kernel.

## Ejecución mínima

También se puede ejecutar sin especificar un filtro:

```bash
./image_processor photos/p1.ppm results/salida.ppm 1
./image_processor photos/p1.ppm results/salida.ppm 2
./image_processor photos/p1.ppm results/salida.ppm 4
./image_processor photos/p1.ppm results/salida.ppm 8
```

En este caso se utiliza automáticamente:

```text
gaussian 3
```

es decir, Gaussian Blur con kernel `3x3`.

## Filtros disponibles

### Gaussian Blur

Nombre:

```text
gaussian
```

Uso:

```bash
./image_processor entrada.ppm salida.ppm PROCESOS gaussian TAMANO_KERNEL
```

Ejemplos:

```bash
./image_processor photos/p1.ppm results/gaussian3.ppm 4 gaussian 3
./image_processor photos/p1.ppm results/gaussian5.ppm 4 gaussian 5
./image_processor photos/p1.ppm results/gaussian7.ppm 4 gaussian 7
```

El tamaño del kernel debe ser un número:

* entero;
* positivo;
* impar.

Por ejemplo:

```text
1, 3, 5, 7, 9, ...
```

### Escala de grises

Nombre:

```text
grayscale
```

Uso:

```bash
./image_processor photos/p1.ppm results/grayscale.ppm 4 grayscale
```

### Inversión de colores

Nombre:

```text
invert
```

Uso:

```bash
./image_processor photos/p1.ppm results/invert.ppm 4 invert
```

### Brillo

Nombre:

```text
brightness
```

Uso:

```bash
./image_processor entrada.ppm salida.ppm PROCESOS brightness CANTIDAD
```

Aumentar brillo:

```bash
./image_processor photos/p1.ppm results/brillo.ppm 4 brightness 30
```

Disminuir brillo:

```bash
./image_processor photos/p1.ppm results/oscuro.ppm 4 brightness -30
```

### Threshold

Nombre:

```text
threshold
```

Uso:

```bash
./image_processor entrada.ppm salida.ppm PROCESOS threshold LIMITE
```

Ejemplo:

```bash
./image_processor photos/p1.ppm results/threshold.ppm 4 threshold 128
```

El límite debe estar entre:

```text
0 y 255
```

### Sharpen

Nombre:

```text
sharpen
```

Uso:

```bash
./image_processor photos/p1.ppm results/sharpen.ppm 4 sharpen
```

### Sobel

Nombre:

```text
sobel
```

Uso:

```bash
./image_processor photos/p1.ppm results/sobel.ppm 4 sobel
```

## Resumen de filtros

| Filtro           | Nombre       | Parámetro                    |
| ---------------- | ------------ | ---------------------------- |
| Gaussian Blur    | `gaussian`   | Tamaño impar del kernel      |
| Escala de grises | `grayscale`  | Ninguno                      |
| Invertir colores | `invert`     | Ninguno                      |
| Brillo           | `brightness` | Cantidad positiva o negativa |
| Threshold        | `threshold`  | Valor entre 0 y 255          |
| Sharpen          | `sharpen`    | Ninguno                      |
| Sobel            | `sobel`      | Ninguno                      |

## Cantidad de procesos

La cantidad de procesos se indica después del archivo de salida:

```bash
./image_processor entrada.ppm salida.ppm PROCESOS ...
```

Por ejemplo:

```bash
./image_processor photos/p1.ppm results/salida.ppm 1 gaussian 3
./image_processor photos/p1.ppm results/salida.ppm 2 gaussian 3
./image_processor photos/p1.ppm results/salida.ppm 4 gaussian 3
./image_processor photos/p1.ppm results/salida.ppm 8 gaussian 3
```

Si se solicitan más procesos que filas tiene la imagen, el programa limita automáticamente la cantidad utilizada.

## Formato de las imágenes

El programa trabaja con imágenes:

```text
PPM P3
```

Ejemplo de encabezado válido:

```text
P3
501 890
255
```

La imagen de entrada debe estar en este formato.

## Carpeta de resultados

Se recomienda guardar las imágenes generadas dentro de:

```text
results/
```

Por ejemplo:

```bash
./image_processor photos/p1.ppm results/p1_sobel.ppm 8 sobel
```

La ruta de salida debe indicarse explícitamente en el comando.

## Timeout de Scheme

Cada instancia de Scheme tiene un tiempo máximo de ejecución.

El valor predeterminado es:

```text
300000 ms
```

equivalente a 5 minutos.

Puede cambiarse antes de ejecutar el programa:

```bash
export SCHEME_TIMEOUT_MS=600000
```

Por ejemplo, `600000` corresponde a 10 minutos.

## Uso desde Erlang

También es posible utilizar directamente el módulo `startup`.

Para Gaussian Blur:

```erlang
startup:procesarImagen(
    "photos/p1.ppm",
    "results/salida.ppm",
    4,
    3
).
```

La función utilizada es:

```text
procesarImagen/4
```

y utiliza Gaussian Blur automáticamente.

Para seleccionar un filtro manualmente se utiliza:

```text
procesarImagen/6
```

Su formato es:

```erlang
startup:procesarImagen(
    Entrada,
    Salida,
    Procesos,
    Filtro,
    Parametro,
    TamanoKernel
).
```

Ejemplo con Sobel:

```erlang
startup:procesarImagen(
    "photos/p1.ppm",
    "results/sobel.ppm",
    4,
    sobel,
    0,
    3
).
```

Ejemplo con Gaussian `7x7`:

```erlang
startup:procesarImagen(
    "photos/p1.ppm",
    "results/gaussian7.ppm",
    4,
    gaussian,
    0,
    7
).
```

## Compilación manual

Normalmente no es necesario compilar manualmente si se utiliza:

```bash
./image_processor
```

Para compilar `startup.erl` manualmente:

```bash
erlc -o erlang erlang/startup.erl
```

Luego se puede abrir Erlang:

```bash
erl -pa erlang
```

y ejecutar, por ejemplo:

```erlang
startup:procesarImagen(
    "photos/p1.ppm",
    "results/salida.ppm",
    4,
    gaussian,
    0,
    3
).
```

## Ejemplos rápidos

Gaussian `3x3`:

```bash
./image_processor photos/p1.ppm results/p1_gaussian.ppm 8 gaussian 3
```

Gaussian `7x7`:

```bash
./image_processor photos/p1.ppm results/p1_gaussian7.ppm 8 gaussian 7
```

Escala de grises:

```bash
./image_processor photos/p1.ppm results/p1_grayscale.ppm 8 grayscale
```

Invertir:

```bash
./image_processor photos/p1.ppm results/p1_invert.ppm 8 invert
```

Aumentar brillo:

```bash
./image_processor photos/p1.ppm results/p1_brightness.ppm 8 brightness 30
```

Threshold:

```bash
./image_processor photos/p1.ppm results/p1_threshold.ppm 8 threshold 128
```

Sharpen:

```bash
./image_processor photos/p1.ppm results/p1_sharpen.ppm 8 sharpen
```

Sobel:

```bash
./image_processor photos/p1.ppm results/p1_sobel.ppm 8 sobel
```

## Estructura básica

```text
image-processor/
├── image_processor
├── erlang/
│   └── startup.erl
├── scheme/
│   └── image_processor.scm
├── photos/
│   └── ...
├── results/
│   └── ...
├── docs/
│   └── ...
└── README.md
```

Para información sobre la implementación, paralelización, halos, convolución, generación de kernels y funcionamiento de los filtros, consultar el informe técnico del proyecto.

