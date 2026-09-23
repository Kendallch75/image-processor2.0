; ============================================================
; PROYECTO FUNCIONAL
; PROCESAMIENTO DE IMAGENES EN SCHEME
; ============================================================

; FUNCIONES GENERALES

(define longitud
  (lambda (lista)
    (cond
      ((null? lista) 0)
      (else (+ 1 (longitud (cdr lista)))))))

(define obtener
  (lambda (lista n)
    (cond
      ((= n 0) (car lista))
      (else (obtener (cdr lista) (- n 1))))))

(define clamp
  (lambda (valor)
    (cond
      ((< valor 0) 0)
      ((> valor 255) 255)
      (else valor))))

(define clamp-pixel
  (lambda (pixel)
    (map clamp pixel)))

(define absoluto
  (lambda (valor)
    (cond
      ((< valor 0) (- 0 valor))
      (else valor))))

(define fallar
  (lambda ()
    (car '())))

(define sumar-pixel
  (lambda (pixel-a pixel-b)
    (map + pixel-a pixel-b)))

(define sumar-pixeles
  (lambda (pixeles)
    (cond
      ((null? pixeles) '(0 0 0))
      (else (sumar-pixel (car pixeles) (sumar-pixeles (cdr pixeles)))))))

(define multiplicar-pixel
  (lambda (pixel peso)
    (map (lambda (componente) (* componente peso)) pixel)))

(define dividir-pixel
  (lambda (pixel divisor)
    (map (lambda (componente) (quotient componente divisor)) pixel)))

; MANEJO DE MATRICES Y BORDES

(define pixel
  (lambda (imagen fila columna)
    (obtener (obtener imagen fila) columna)))

; Estrategia de borde: repetir el pixel mas cercano.
(define limitar-indice
  (lambda (indice limite)
    (cond
      ((< indice 0) 0)
      ((>= indice limite) (- limite 1))
      (else indice))))

(define pixel-borde
  (lambda (imagen fila columna)
    (pixel imagen
           (limitar-indice fila (longitud imagen))
           (limitar-indice columna (longitud (car imagen))))))

; VECINDAD PARA KERNEL IMPAR

(define vecindad-fila
  (lambda (imagen fila columna desplazamiento limite)
    (cond
      ((> desplazamiento limite) '())
      (else (append (list (pixel-borde imagen fila (+ columna desplazamiento)))
                    (vecindad-fila imagen fila columna (+ desplazamiento 1) limite))))))

(define vecindad-aux
  (lambda (imagen fila columna desplazamiento limite)
    (cond
      ((> desplazamiento limite) '())
      (else (append (list (vecindad-fila imagen (+ fila desplazamiento) columna (- 0 limite) limite))
                    (vecindad-aux imagen fila columna (+ desplazamiento 1) limite))))))

(define vecindad-kernel
  (lambda (imagen fila columna kernel)
    ((lambda (radio)
       (vecindad-aux imagen fila columna (- 0 radio) radio))
     (quotient (longitud kernel) 2))))

; CONVOLUCION

(define aplicar-pesos-fila
  (lambda (pixeles pesos)
    (cond
      ((null? pixeles) '())
      (else (append (list (multiplicar-pixel (car pixeles) (car pesos)))
                    (aplicar-pesos-fila (cdr pixeles) (cdr pesos)))))))

(define aplicar-pesos
  (lambda (vecindad kernel)
    (cond
      ((null? vecindad) '())
      (else (append (aplicar-pesos-fila (car vecindad) (car kernel))
                    (aplicar-pesos (cdr vecindad) (cdr kernel)))))))

(define sumar-numeros
  (lambda (lista)
    (cond
      ((null? lista) 0)
      (else (+ (car lista) (sumar-numeros (cdr lista)))))))

(define sumar-kernel
  (lambda (kernel)
    (cond
      ((null? kernel) 0)
      (else (+ (sumar-numeros (car kernel)) (sumar-kernel (cdr kernel)))))))

(define convolucion
  (lambda (vecindad kernel)
    (sumar-pixeles (aplicar-pesos vecindad kernel))))

(define convolucion-div
  (lambda (vecindad kernel divisor)
    (clamp-pixel (dividir-pixel (convolucion vecindad kernel) divisor))))

; ============================================================
; 1. GAUSSIAN BLUR
; ============================================================

; 3x3: suma 16
; 5x5: suma 256
(define fila-pascal-aux
  (lambda (n k anterior)
    (cond
      ((> k n) '())
      ((= k 0)
       (append (list 1)
               (fila-pascal-aux n 1 1)))
      (else
       ((lambda (actual)
          (append (list actual)
                  (fila-pascal-aux n (+ k 1) actual)))
        (quotient (* anterior (- (+ n 1) k)) k))))))

(define fila-pascal
  (lambda (n)
    (fila-pascal-aux n 0 1)))

(define multiplicar-fila-kernel
  (lambda (fila peso)
    (map (lambda (valor) (* valor peso)) fila)))

(define construir-kernel
  (lambda (fila pesos)
    (cond
      ((null? pesos) '())
      (else
       (append
        (list (multiplicar-fila-kernel fila (car pesos)))
        (construir-kernel fila (cdr pesos)))))))

(define generar-kernel-gaussian
  (lambda (tamano)
    ((lambda (fila)
       (construir-kernel fila fila))
     (fila-pascal (- tamano 1)))))

(define kernel-gaussian
  (lambda (tamano)
    (cond
      ((< tamano 1) (fallar))
      ((= (modulo tamano 2) 0) (fallar))
      (else (generar-kernel-gaussian tamano)))))

(define gaussian-pixel
  (lambda (imagen fila columna kernel)
    (convolucion-div (vecindad-kernel imagen fila columna kernel) kernel (sumar-kernel kernel))))

(define gaussian-fila
  (lambda (imagen fila columna ancho kernel)
    (cond
      ((= columna ancho) '())
      (else (append (list (gaussian-pixel imagen fila columna kernel))
                    (gaussian-fila imagen fila (+ columna 1) ancho kernel))))))

(define gaussian-aux
  (lambda (imagen fila alto ancho kernel)
    (cond
      ((= fila alto) '())
      (else (append (list (gaussian-fila imagen fila 0 ancho kernel))
                    (gaussian-aux imagen (+ fila 1) alto ancho kernel))))))

; Interfaz solicitada en el proyecto.
(define gaussian
  (lambda (image-region kernel)
    (gaussian-aux image-region 0 (longitud image-region) (longitud (car image-region)) kernel)))

; ============================================================
; 2. GRAYSCALE
; ============================================================

(define grayscale-pixel
  (lambda (pixel)
    ((lambda (gris) (list gris gris gris))
     (quotient (+ (* 30 (car pixel))
                  (* 59 (car (cdr pixel)))
                  (* 11 (car (cdr (cdr pixel)))))
               100))))

(define grayscale
  (lambda (image-region)
    (map (lambda (fila) (map grayscale-pixel fila)) image-region)))

; ============================================================
; 3. INVERSION DE COLORES
; ============================================================

(define invert-pixel
  (lambda (pixel)
    (map (lambda (componente) (- 255 componente)) pixel)))

(define invert
  (lambda (image-region)
    (map (lambda (fila) (map invert-pixel fila)) image-region)))

; ============================================================
; 4. BRIGHTNESS
; ============================================================

(define brightness-pixel
  (lambda (pixel cantidad)
    (map (lambda (componente) (clamp (+ componente cantidad))) pixel)))

(define brightness
  (lambda (image-region cantidad)
    (map (lambda (fila) (map (lambda (p) (brightness-pixel p cantidad)) fila)) image-region)))

; ============================================================
; 5. THRESHOLD
; ============================================================

(define intensidad
  (lambda (pixel)
    (quotient (+ (* 30 (car pixel))
                 (* 59 (car (cdr pixel)))
                 (* 11 (car (cdr (cdr pixel)))))
              100)))

(define threshold-pixel
  (lambda (pixel limite)
    (cond
      ((>= (intensidad pixel) limite) '(255 255 255))
      (else '(0 0 0)))))

(define threshold
  (lambda (image-region limite)
    (map (lambda (fila) (map (lambda (p) (threshold-pixel p limite)) fila)) image-region)))

; ============================================================
; 6. SHARPEN
; ============================================================

(define kernel-sharpen
  (lambda () '((0 -1 0) (-1 5 -1) (0 -1 0))))

(define sharpen-pixel
  (lambda (imagen fila columna)
    (clamp-pixel (convolucion (vecindad-kernel imagen fila columna (kernel-sharpen)) (kernel-sharpen)))))

(define sharpen-fila
  (lambda (imagen fila columna ancho)
    (cond
      ((= columna ancho) '())
      (else (append (list (sharpen-pixel imagen fila columna))
                    (sharpen-fila imagen fila (+ columna 1) ancho))))))

(define sharpen-aux
  (lambda (imagen fila alto ancho)
    (cond
      ((= fila alto) '())
      (else (append (list (sharpen-fila imagen fila 0 ancho))
                    (sharpen-aux imagen (+ fila 1) alto ancho))))))

(define sharpen
  (lambda (image-region)
    (sharpen-aux image-region 0 (longitud image-region) (longitud (car image-region)))))

; ============================================================
; 7. SOBEL
; ============================================================

(define kernel-sobel-x
  (lambda () '((-1 0 1) (-2 0 2) (-1 0 1))))

(define kernel-sobel-y
  (lambda () '((-1 -2 -1) (0 0 0) (1 2 1))))

(define combinar-gradientes
  (lambda (gx gy)
    (map (lambda (x y) (clamp (+ (absoluto x) (absoluto y)))) gx gy)))

(define sobel-pixel
  (lambda (imagen fila columna)
    (combinar-gradientes
      (convolucion (vecindad-kernel imagen fila columna (kernel-sobel-x)) (kernel-sobel-x))
      (convolucion (vecindad-kernel imagen fila columna (kernel-sobel-y)) (kernel-sobel-y)))))

(define sobel-fila
  (lambda (imagen fila columna ancho)
    (cond
      ((= columna ancho) '())
      (else (append (list (sobel-pixel imagen fila columna))
                    (sobel-fila imagen fila (+ columna 1) ancho))))))

(define sobel-aux
  (lambda (imagen fila alto ancho)
    (cond
      ((= fila alto) '())
      (else (append (list (sobel-fila imagen fila 0 ancho))
                    (sobel-aux imagen (+ fila 1) alto ancho))))))

(define sobel
  (lambda (image-region)
    (sobel-aux image-region 0 (longitud image-region) (longitud (car image-region)))))

; ============================================================
; PROTOCOLO ERLANG -> SCHEME
;
; Solicitud:
; (request filtro tamano-kernel parametro filas-halo-arriba
;          alto-bloque region-con-halo)
;
; Scheme devuelve SOLO las filas del bloque asignado.
; ============================================================

(define aplicar-filtro
  (lambda (region filtro parametro tamano-kernel)
    (cond
      ((eq? filtro 'gaussian) (gaussian region (kernel-gaussian tamano-kernel)))
      ((eq? filtro 'grayscale) (grayscale region))
      ((eq? filtro 'invert) (invert region))
      ((eq? filtro 'brightness) (brightness region parametro))
      ((eq? filtro 'threshold) (threshold region parametro))
      ((eq? filtro 'sharpen) (sharpen region))
      ((eq? filtro 'sobel) (sobel region))
      (else (fallar)))))

(define saltar
  (lambda (lista cantidad)
    (cond
      ((= cantidad 0) lista)
      (else (saltar (cdr lista) (- cantidad 1))))))

(define tomar
  (lambda (lista cantidad)
    (cond
      ((= cantidad 0) '())
      (else (append (list (car lista)) (tomar (cdr lista) (- cantidad 1)))))))

(define recortar-filas
  (lambda (imagen inicio cantidad)
    (tomar (saltar imagen inicio) cantidad)))

(define procesar-solicitud
  (lambda (solicitud)
    ((lambda (filtro tamano-kernel parametro halo-arriba alto-bloque region)
       (recortar-filas
         (aplicar-filtro region filtro parametro tamano-kernel)
         halo-arriba
         alto-bloque))
     (obtener solicitud 1)
     (obtener solicitud 2)
     (obtener solicitud 3)
     (obtener solicitud 4)
     (obtener solicitud 5)
     (obtener solicitud 6))))

; ============================================================
; ENTRADA / SALIDA DEL PROTOCOLO
; ============================================================

(define leer-solicitud
  (lambda (archivo)
    (call-with-input-file archivo (lambda (puerto) (read puerto)))))

(define escribir-pixel
  (lambda (pixel puerto)
    (display (car pixel) puerto)
    (display " " puerto)
    (display (car (cdr pixel)) puerto)
    (display " " puerto)
    (display (car (cdr (cdr pixel))) puerto)))

(define escribir-fila
  (lambda (fila puerto)
    (cond
      ((null? fila) (newline puerto))
      (else (escribir-pixel (car fila) puerto)
            (display " " puerto)
            (escribir-fila (cdr fila) puerto)))))

(define escribir-region-puerto
  (lambda (region puerto)
    (cond
      ((null? region) 'ok)
      (else (escribir-fila (car region) puerto)
            (escribir-region-puerto (cdr region) puerto)))))

(define escribir-region
  (lambda (archivo region)
    (call-with-output-file archivo
      (lambda (puerto) (escribir-region-puerto region puerto)))))

(define procesar-archivo
  (lambda (archivo-entrada archivo-salida)
    (escribir-region archivo-salida (procesar-solicitud (leer-solicitud archivo-entrada)))))
