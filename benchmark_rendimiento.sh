#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

EJECUTABLE="./image_processor"
TEST_DIR="tests"
RESULT_DIR="benchmark_rendimiento"
PROCESOS=(1 2 4 8)
IMAGENES=(p1 p2 p3 p4 p5)
REPETICIONES=3

if [[ ! -x "$EJECUTABLE" ]]; then
    echo "Error: no encuentro $EJECUTABLE o no tiene permiso de ejecucion."
    echo "Ejecuta: chmod +x image_processor"
    exit 1
fi

mkdir -p "$RESULT_DIR"
ERRORES="$RESULT_DIR/errores.log"
: > "$ERRORES"

GENERAL_REP="$RESULT_DIR/resultados_por_repeticion.csv"
GENERAL_RES="$RESULT_DIR/resumen_promedios.csv"

echo "imagen,ancho,alto,pixeles,bytes,repeticion,procesos,tiempo_segundos,speedup,eficiencia" > "$GENERAL_REP"
echo "imagen,ancho,alto,pixeles,bytes,procesos,tiempo_promedio,tiempo_minimo,tiempo_maximo,speedup_promedio,eficiencia_promedio,throughput_pixeles_por_segundo" > "$GENERAL_RES"

leer_cabecera_ppm() {
    awk '
    {
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^#/) break
            token[++n] = $i
            if (n == 4) {
                print token[1], token[2], token[3], token[4]
                exit
            }
        }
    }' "$1"
}

agregar_repeticiones_csv() {
    local bench_csv="$1"
    local salida_csv="$2"
    local imagen="$3"
    local ancho="$4"
    local alto="$5"
    local pixeles="$6"
    local bytes="$7"
    local repeticion="$8"

    tail -n +2 "$bench_csv" | while IFS=',' read -r procesos tiempo speedup eficiencia resto; do
        [[ -z "${procesos:-}" ]] && continue
        echo "${imagen},${ancho},${alto},${pixeles},${bytes},${repeticion},${procesos},${tiempo},${speedup},${eficiencia}" >> "$salida_csv"
        echo "${imagen},${ancho},${alto},${pixeles},${bytes},${repeticion},${procesos},${tiempo},${speedup},${eficiencia}" >> "$GENERAL_REP"
    done
}

resumir_imagen() {
    local rep_csv="$1"
    local out_csv="$2"

    awk -F',' '
    NR==1 { next }
    {
        key=$7
        procesos=$7
        imagen=$1
        ancho=$2
        alto=$3
        pixeles=$4
        bytes=$5

        n[key]++
        tiempo[key]+=$8
        speedup[key]+=$9
        eficiencia[key]+=$10

        if (!(key in tmin) || $8 < tmin[key]) tmin[key]=$8
        if (!(key in tmax) || $8 > tmax[key]) tmax[key]=$8

        img[key]=imagen
        anc[key]=ancho
        alt[key]=alto
        pix[key]=pixeles
        byt[key]=bytes
        proc[key]=procesos
    }
    END {
        for (k in n) {
            tp=tiempo[k]/n[k]
            sp=speedup[k]/n[k]
            ep=eficiencia[k]/n[k]
            thr=pix[k]/tp
            printf "%s,%s,%s,%s,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
                img[k], anc[k], alt[k], pix[k], byt[k], proc[k],
                tp, tmin[k], tmax[k], sp, ep, thr
        }
    }' "$rep_csv" | sort -t',' -k6,6n >> "$out_csv"
}

for imagen in "${IMAGENES[@]}"; do
    entrada="$TEST_DIR/${imagen}.ppm"

    echo
    echo "============================================================"
    echo "IMAGEN: $entrada"
    echo "FILTRO DE RENDIMIENTO: gaussian 3 (obligatorio)"
    echo "REPETICIONES POR CONFIGURACION: $REPETICIONES"
    echo "PROCESOS: ${PROCESOS[*]}"
    echo "============================================================"

    if [[ ! -f "$entrada" ]]; then
        echo "No existe $entrada. Se omite."
        echo "[$imagen] No existe $entrada" >> "$ERRORES"
        continue
    fi

    read -r magic ancho alto maximo <<< "$(leer_cabecera_ppm "$entrada")"

    if [[ "$magic" != "P3" || -z "${ancho:-}" || -z "${alto:-}" ]]; then
        echo "El archivo no parece ser un PPM P3 valido. Se omite."
        echo "[$imagen] PPM P3 invalido" >> "$ERRORES"
        continue
    fi

    pixeles=$((ancho * alto))
    bytes=$(stat -c%s "$entrada")

    carpeta="$RESULT_DIR/$imagen"
    mkdir -p "$carpeta/benchmarks" "$carpeta/logs"

    REP_CSV="$carpeta/resultados_repeticiones_${imagen}.csv"
    RES_CSV="$carpeta/resumen_${imagen}.csv"
    echo "imagen,ancho,alto,pixeles,bytes,repeticion,procesos,tiempo_segundos,speedup,eficiencia" > "$REP_CSV"
    echo "imagen,ancho,alto,pixeles,bytes,procesos,tiempo_promedio,tiempo_minimo,tiempo_maximo,speedup_promedio,eficiencia_promedio,throughput_pixeles_por_segundo" > "$RES_CSV"

    echo "Tamano: ${ancho}x${alto} (${pixeles} pixeles)"
    echo "Archivo: ${bytes} bytes"

    for rep in $(seq 1 "$REPETICIONES"); do
        prefijo="$carpeta/benchmarks/${imagen}_rep${rep}"
        log="$carpeta/logs/${imagen}_rep${rep}.log"

        echo "  -> repeticion $rep/$REPETICIONES"

        if "$EJECUTABLE" --benchmark "$entrada" "$prefijo" gaussian 3 >"$log" 2>&1; then
            bench_csv="${prefijo}_benchmark.csv"
            if [[ -f "$bench_csv" ]]; then
                agregar_repeticiones_csv "$bench_csv" "$REP_CSV" "$imagen" "$ancho" "$alto" "$pixeles" "$bytes" "$rep"
                echo "     benchmark: OK"
            else
                echo "     benchmark: ERROR (no se genero CSV)"
                echo "[$imagen][rep=$rep] no se genero CSV" >> "$ERRORES"
                cat "$log" >> "$ERRORES"
                echo >> "$ERRORES"
            fi
        else
            echo "     benchmark: ERROR"
            echo "[$imagen][rep=$rep] error benchmark" >> "$ERRORES"
            cat "$log" >> "$ERRORES"
            echo >> "$ERRORES"
        fi
    done

    resumir_imagen "$REP_CSV" "$RES_CSV"
    tail -n +2 "$RES_CSV" >> "$GENERAL_RES"

    echo "Resumen por repeticiones: $REP_CSV"
    echo "Resumen promedio:        $RES_CSV"
done

echo
echo "============================================================"
echo "TERMINADO"
echo "============================================================"
echo "Resumen por repeticion: $GENERAL_REP"
echo "Resumen de promedios:   $GENERAL_RES"

if [[ -s "$ERRORES" ]]; then
    echo "Hubo uno o mas errores. Revisa: $ERRORES"
else
    rm -f "$ERRORES"
    echo "No se detectaron errores."
fi

echo
echo "Columnas de resultados_por_repeticion.csv:"
echo "imagen, ancho, alto, pixeles, bytes, repeticion, procesos, tiempo_segundos, speedup, eficiencia"
echo
echo "Columnas de resumen_promedios.csv:"
echo "imagen, ancho, alto, pixeles, bytes, procesos, tiempo_promedio, tiempo_minimo, tiempo_maximo, speedup_promedio, eficiencia_promedio, throughput_pixeles_por_segundo"
