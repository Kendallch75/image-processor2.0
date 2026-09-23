# Informe técnico — base

## 1. Arquitectura del sistema

La solución se divide en dos responsabilidades. Erlang lee y escribe la imagen PPM P3, divide la imagen en regiones, agrega halos, crea los procesos concurrentes, ejecuta una instancia independiente de Scheme por región, recibe los resultados y reconstruye la imagen. Scheme realiza exclusivamente las transformaciones de imagen.

## 2. División de la imagen

La imagen se divide horizontalmente en regiones de alturas lo más equilibradas posible. Si la altura no es divisible entre la cantidad de procesos, las primeras regiones reciben una fila adicional.

Para un kernel impar de tamaño `k`, el halo utilizado es `k div 2`. Cada región recibe filas adicionales superiores e inferiores cuando existen.

## 3. Procesamiento de bordes

La estrategia seleccionada es repetir el píxel más cercano. Cuando una coordenada solicitada está fuera de los límites de la imagen o de la región con halo, se limita al índice válido más cercano.

## 4. Modelo de concurrencia

El coordinador crea un proceso Erlang independiente por región mediante `spawn`. Cada trabajador ejecuta su propia instancia de Scheme. Los resultados se devuelven al coordinador mediante paso de mensajes con el índice original de la región.

## 5. Comunicación Erlang-Scheme

El protocolo de entrada utiliza una expresión Scheme:

```scheme
(request filtro tamano-kernel parametro filas-halo-arriba alto-bloque region-con-halo)
```

La región representa los píxeles como listas RGB `(R G B)`. Scheme procesa la región con halo y devuelve únicamente el bloque asignado. La respuesta contiene valores RGB separados por espacios; Erlang valida la cantidad esperada antes de reconstruir la imagen.

## 6. Filtros

Se implementan:

- Gaussian Blur 3x3 obligatorio.
- Gaussian Blur 5x5.
- Grayscale.
- Inversión de colores.
- Brightness.
- Threshold.
- Sharpen.
- Sobel.

## 7. Manejo de errores

El trabajador captura cualquier error de Scheme y lo informa al coordinador. Una ejecución fallida se reintenta una vez. Si vuelve a fallar, la imagen no se reconstruye silenciosamente y se informa qué región produjo el error.

## 8. Evaluación de rendimiento

Se deben ejecutar las configuraciones de 1, 2, 4 y 8 procesos sobre la misma imagen y filtro. El comando `--benchmark` genera automáticamente los tiempos y un archivo CSV.

Las métricas son:

```text
Sp = T1 / Tp
Ep = Sp / p
```

### Resultados

| Procesos | Tp (s) | Speedup | Eficiencia |
|---:|---:|---:|---:|
| 1 | completar | 1.000 | 1.000 |
| 2 | completar | completar | completar |
| 4 | completar | completar | completar |
| 8 | completar | completar | completar |

## 9. Análisis

Completar con los resultados reales. Se debe discutir el costo de crear procesos, iniciar intérpretes Scheme, serializar regiones, copiar halos, leer/escribir archivos temporales, reconstruir la imagen y realizar E/S del archivo PPM.

## 10. Limitaciones

El rendimiento puede verse limitado por el costo de iniciar una instancia Scheme por trabajador y por el intercambio de regiones mediante archivos temporales. Gaussian admite kernels 3x3 y 5x5; Sharpen y Sobel utilizan kernels 3x3.
