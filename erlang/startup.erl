-module(startup).

-export([
    lector/1,
    escritor/2,
    dividir/3,
    reconstruir/4,
    trabajador/3,
    procesarImagen/4,
    procesarImagen/6,
    cli/1
]).

% ============================================================
% LECTURA Y ESCRITURA PPM P3
% ============================================================

lector(Filename) ->
    case file:read_file(Filename) of
        {ok, Binario} -> parsear(string:tokens(quitarComentarios(binary_to_list(Binario)), " \t\r\n"));
        {error, Razon} -> erlang:error({no_se_pudo_leer, Filename, Razon})
    end.

quitarComentarios([]) -> [];
quitarComentarios([$# | Resto]) -> quitarHastaSalto(Resto);
quitarComentarios([C | Resto]) -> [C | quitarComentarios(Resto)].

quitarHastaSalto([]) -> [];
quitarHastaSalto([$\n | Resto]) -> [$\n | quitarComentarios(Resto)];
quitarHastaSalto([_ | Resto]) -> quitarHastaSalto(Resto).

parsear(["P3", AnchoStr, AltoStr, MaxStr | TokensPixeles]) ->
    Ancho = list_to_integer(AnchoStr),
    Alto = list_to_integer(AltoStr),
    Max = list_to_integer(MaxStr),
    Pixeles = armarPixeles(TokensPixeles),
    case length(Pixeles) =:= Ancho * Alto of
        true -> {image, Ancho, Alto, Max, armarFilas(Ancho, Pixeles)};
        false -> erlang:error({cantidad_pixeles_incorrecta, Ancho * Alto, length(Pixeles)})
    end;
parsear(_) -> erlang:error(formato_ppm_invalido).

armarPixeles([]) -> [];
armarPixeles([RStr, GStr, BStr | Resto]) ->
    [{list_to_integer(RStr), list_to_integer(GStr), list_to_integer(BStr)} | armarPixeles(Resto)];
armarPixeles(_) -> erlang:error(rgb_incompleto).

armarFilas(_Ancho, []) -> [];
armarFilas(Ancho, Pixeles) ->
    {Fila, Resto} = lists:split(Ancho, Pixeles),
    [Fila | armarFilas(Ancho, Resto)].

escritor(Filename, {image, Ancho, Alto, Max, Filas}) ->
    case filelib:ensure_dir(Filename) of
        ok -> file:write_file(Filename, [cabecera(Ancho, Alto, Max) | formatoFilas(Filas)]);
        {error, Razon} -> {error, Razon}
    end.

cabecera(Ancho, Alto, Max) -> io_lib:format("P3~n~b ~b~n~b~n", [Ancho, Alto, Max]).

formatoFilas([]) -> [];
formatoFilas([Fila | Resto]) -> [formatoFila(Fila), "\n" | formatoFilas(Resto)].

formatoFila([]) -> [];
formatoFila([{R, G, B}]) -> io_lib:format("~b ~b ~b", [R, G, B]);
formatoFila([{R, G, B} | Resto]) -> [io_lib:format("~b ~b ~b  ", [R, G, B]) | formatoFila(Resto)].

% ============================================================
% DIVISION DE LA IMAGEN Y HALOS
% ============================================================

dividir({image, Ancho, Alto, Max, Filas}, NumProcesos, TamanoKernel)
  when NumProcesos > 0, TamanoKernel > 0, TamanoKernel rem 2 =:= 1 ->
    ProcesosReales = erlang:min(NumProcesos, Alto),
    TamanoHalo = TamanoKernel div 2,
    Tamanos = calcularTamanos(Alto, ProcesosReales),
    {Ancho, Alto, Max, construirZonas(Filas, Tamanos, TamanoHalo, 0, 1, Alto)};
dividir(_, _, _) -> erlang:error(parametros_division_invalidos).

calcularTamanos(Alto, NumProcesos) ->
    distribuirTamanos(NumProcesos, Alto div NumProcesos, Alto rem NumProcesos).

distribuirTamanos(0, _Base, _Resto) -> [];
distribuirTamanos(N, Base, 0) -> [Base | distribuirTamanos(N - 1, Base, 0)];
distribuirTamanos(N, Base, Resto) -> [Base + 1 | distribuirTamanos(N - 1, Base, Resto - 1)].

sublista(_Lista, _Inicio, 0) -> [];
sublista(Lista, Inicio, Cantidad) -> lists:sublist(lists:nthtail(Inicio, Lista), Cantidad).

construirZonas(_Filas, [], _TamanoHalo, _Inicio, _Indice, _Alto) -> [];
construirZonas(Filas, [Tamano | Resto], TamanoHalo, Inicio, Indice, Alto) ->
    InicioHaloArriba = erlang:max(0, Inicio - TamanoHalo),
    CantidadHaloArriba = Inicio - InicioHaloArriba,
    InicioAbajo = Inicio + Tamano,
    CantidadHaloAbajo = erlang:min(TamanoHalo, Alto - InicioAbajo),
    Bloque = sublista(Filas, Inicio, Tamano),
    HaloArriba = sublista(Filas, InicioHaloArriba, CantidadHaloArriba),
    HaloAbajo = sublista(Filas, InicioAbajo, CantidadHaloAbajo),
    [{region, Indice, Bloque, HaloArriba, HaloAbajo} |
     construirZonas(Filas, Resto, TamanoHalo, Inicio + Tamano, Indice + 1, Alto)].

% ============================================================
% RECONSTRUCCION
% ============================================================

reconstruir(Ancho, Alto, Max, Resultados) ->
    {image, Ancho, Alto, Max, concatenarFilas(ordenarPorIndice(Resultados))}.

ordenarPorIndice(Resultados) -> lists:keysort(1, Resultados).

concatenarFilas([]) -> [];
concatenarFilas([{_Indice, Filas} | Resto]) -> Filas ++ concatenarFilas(Resto).

% ============================================================
% TRABAJADORES ERLANG Y LLAMADA A SCHEME
% ============================================================

trabajador(Zona, ParametrosFiltro, PidCoordinador) ->
    {region, Indice, Bloque, HaloArriba, HaloAbajo} = Zona,
    try aplicarFiltro(HaloArriba, Bloque, HaloAbajo, ParametrosFiltro) of
        {ok, FilasProcesadas} -> PidCoordinador ! {resultado, Indice, FilasProcesadas};
        {error, Razon} -> PidCoordinador ! {error, Indice, Razon}
    catch
        Clase:Razon:Stack -> PidCoordinador ! {error, Indice, {Clase, Razon, Stack}}
    end.

aplicarFiltro(HaloArriba, Bloque, HaloAbajo, ParametrosFiltro) ->
    ejecutarSchemeConReintento(HaloArriba, Bloque, HaloAbajo, ParametrosFiltro, 1).

ejecutarSchemeConReintento(HaloArriba, Bloque, HaloAbajo, ParametrosFiltro, Intentos) ->
    case ejecutarScheme(HaloArriba, Bloque, HaloAbajo, ParametrosFiltro) of
        {ok, _} = Exito -> Exito;
        {error, _Razon} when Intentos > 0 ->
            ejecutarSchemeConReintento(HaloArriba, Bloque, HaloAbajo, ParametrosFiltro, Intentos - 1);
        {error, Razon} -> {error, Razon}
    end.

crearProcesos([], _ParametrosFiltro, _PidCoordinador) -> ok;
crearProcesos([Zona | RestoZonas], ParametrosFiltro, PidCoordinador) ->
    spawn(fun() -> trabajador(Zona, ParametrosFiltro, PidCoordinador) end),
    crearProcesos(RestoZonas, ParametrosFiltro, PidCoordinador).

recibirResultados(N) -> recibirResultados(N, [], []).

recibirResultados(0, Resultados, []) -> {ok, Resultados};
recibirResultados(0, _Resultados, Errores) -> {error, lists:reverse(Errores)};
recibirResultados(N, Resultados, Errores) ->
    receive
        {resultado, Indice, Filas} -> recibirResultados(N - 1, [{Indice, Filas} | Resultados], Errores);
        {error, Indice, Razon} -> recibirResultados(N - 1, Resultados, [{Indice, Razon} | Errores])
    end.

% ============================================================
% PROTOCOLO ERLANG -> SCHEME
% ============================================================

% Formato de solicitud:
% (request filtro tamano-kernel parametro filas-halo-arriba alto-bloque region-con-halo)

ejecutarScheme(HaloArriba, Bloque, HaloAbajo, {filtro, Filtro, Parametro, TamanoKernel}) ->
    Root = directorioProyecto(),
    Id = integer_to_list(erlang:unique_integer([positive, monotonic])),
    TmpDir = filename:join(Root, ".tmp"),
    Base = filename:join(TmpDir, "region_" ++ Id),
    Entrada = Base ++ ".in.scm",
    Salida = Base ++ ".out.txt",
    Wrapper = Base ++ ".run.scm",
    SchemeFile = filename:join([Root, "scheme", "image_processor.scm"]),
    ok = filelib:ensure_dir(Entrada),
    Region = HaloArriba ++ Bloque ++ HaloAbajo,
    try
        ejecutarSchemeArchivos(
            Entrada,
            Salida,
            Wrapper,
            SchemeFile,
            Filtro,
            Parametro,
            TamanoKernel,
            length(HaloArriba),
            length(Bloque),
            Region,
            length(hd(Bloque))
        )
    after
        borrarArchivo(Entrada),
        borrarArchivo(Salida),
        borrarArchivo(Wrapper)
    end.

ejecutarSchemeArchivos(Entrada, Salida, Wrapper, SchemeFile, Filtro, Parametro, TamanoKernel,
                       HaloArriba, AltoBloque, Region, Ancho) ->
    Solicitud = solicitudScheme(Filtro, TamanoKernel, Parametro, HaloArriba, AltoBloque, Region),
    WrapperContenido = [
        "(load ", schemeString(SchemeFile), ")\n",
        "(procesar-archivo ", schemeString(Entrada), " ", schemeString(Salida), ")\n"
    ],
    case file:write_file(Entrada, Solicitud) of
        ok ->
            case file:write_file(Wrapper, WrapperContenido) of
                ok -> ejecutarWrapper(Wrapper, Salida, Ancho, AltoBloque);
                {error, RazonWrapper} -> {error, {no_se_pudo_crear_wrapper, RazonWrapper}}
            end;
        {error, RazonEntrada} -> {error, {no_se_pudo_crear_entrada_scheme, RazonEntrada}}
    end.

ejecutarWrapper(Wrapper, Salida, Ancho, AltoBloque) ->
    case comandoScheme(Wrapper) of
        {ok, Comando} ->
            case ejecutarComando(Comando) of
                {ok, _Log} -> leerResultadoScheme(Salida, Ancho, AltoBloque);
                {error, RazonComando} -> {error, RazonComando}
            end;
        {error, _} = Error -> Error
    end.

solicitudScheme(Filtro, TamanoKernel, Parametro, HaloArriba, AltoBloque, Region) ->
    ["(request ", atom_to_list(Filtro), " ", integer_to_list(TamanoKernel), " ",
     integer_to_list(Parametro), " ", integer_to_list(HaloArriba), " ",
     integer_to_list(AltoBloque), " ", filasScheme(Region), ")\n"].

filasScheme([]) -> "()";
filasScheme([Fila | Resto]) -> ["(", filaScheme(Fila), filasSchemeResto(Resto), ")"].

filasSchemeResto([]) -> [];
filasSchemeResto([Fila | Resto]) -> [" ", filaScheme(Fila) | filasSchemeResto(Resto)].

filaScheme([]) -> "()";
filaScheme([Pixel | Resto]) -> ["(", pixelScheme(Pixel), filaSchemeResto(Resto), ")"].

filaSchemeResto([]) -> [];
filaSchemeResto([Pixel | Resto]) -> [" ", pixelScheme(Pixel) | filaSchemeResto(Resto)].

pixelScheme({R, G, B}) -> io_lib:format("(~b ~b ~b)", [R, G, B]).

schemeString(Texto) -> ["\"", escaparSchemeString(Texto), "\""].

escaparSchemeString([]) -> [];
escaparSchemeString([$\\ | Resto]) -> [$\\, $\\ | escaparSchemeString(Resto)];
escaparSchemeString([$\" | Resto]) -> [$\\, $\" | escaparSchemeString(Resto)];
escaparSchemeString([C | Resto]) -> [C | escaparSchemeString(Resto)].

leerResultadoScheme(Salida, Ancho, AltoEsperado) ->
    case file:read_file(Salida) of
        {ok, Binario} ->
            Tokens = string:tokens(binary_to_list(Binario), " \t\r\n"),
            try armarPixeles(Tokens) of
                Pixeles ->
                    case length(Pixeles) =:= Ancho * AltoEsperado of
                        true -> {ok, armarFilas(Ancho, Pixeles)};
                        false -> {error, {salida_scheme_incompleta, Ancho * AltoEsperado, length(Pixeles)}}
                    end
            catch
                _:_ -> {error, salida_scheme_invalida}
            end;
        {error, Razon} -> {error, {scheme_no_genero_salida, Razon}}
    end.

% ============================================================
% EJECUCION DEL INTERPRETE SCHEME
% ============================================================

comandoScheme(Wrapper) ->
    case os:getenv("SCHEME_CMD") of
        false -> detectarScheme(Wrapper);
        Cmd -> {ok, Cmd ++ " " ++ shellQuote(Wrapper)}
    end.

detectarScheme(Wrapper) ->
    case os:find_executable("guile") of
        false -> detectarRacket(Wrapper);
        Guile -> {ok, shellQuote(Guile) ++ " -s " ++ shellQuote(Wrapper)}
    end.

detectarRacket(Wrapper) ->
    case os:find_executable("racket") of
        false -> {error, no_se_encontro_interprete_scheme};
        Racket -> {ok, shellQuote(Racket) ++ " -f " ++ shellQuote(Wrapper)}
    end.

shellQuote(Texto) ->
    "'" ++ lists:flatten(string:replace(Texto, "'", "'\"'\"'", all)) ++ "'".

ejecutarComando(Comando) ->
    Port = open_port({spawn, Comando}, [exit_status, use_stdio, stderr_to_stdout, binary]),
    esperarComando(Port, []).

esperarComando(Port, Acumulado) ->
    receive
        {Port, {data, Datos}} -> esperarComando(Port, [Datos | Acumulado]);
        {Port, {exit_status, 0}} -> {ok, iolist_to_binary(lists:reverse(Acumulado))};
        {Port, {exit_status, Status}} ->
            {error, {scheme_fallo, Status, binary_to_list(iolist_to_binary(lists:reverse(Acumulado)))}}
    after timeoutScheme() ->
        catch port_close(Port),
        {error, scheme_timeout}
    end.

timeoutScheme() ->
    case os:getenv("SCHEME_TIMEOUT_MS") of
        false -> 300000;
        Texto -> list_to_integer(Texto)
    end.

borrarArchivo(Path) ->
    case file:delete(Path) of
        ok -> ok;
        {error, enoent} -> ok;
        {error, _} -> ok
    end.

directorioProyecto() ->
    {ok, Cwd} = file:get_cwd(),
    case code:which(?MODULE) of
        non_existing -> buscarDirectorioProyecto([Cwd]);
        Beam ->
            BeamDir = filename:dirname(filename:absname(Beam)),
            buscarDirectorioProyecto([Cwd, BeamDir, filename:dirname(BeamDir)])
    end.

buscarDirectorioProyecto([Candidato | Resto]) ->
    Scheme = filename:join([Candidato, "scheme", "image_processor.scm"]),
    case filelib:is_file(Scheme) of
        true -> Candidato;
        false -> buscarDirectorioProyecto(Resto)
    end;
buscarDirectorioProyecto([]) -> erlang:error(no_se_encontro_directorio_proyecto).

% ============================================================
% PROCESAMIENTO COMPLETO
% ============================================================

rutaSalidaResultados(ArchivoSalida) ->
    Root = directorioProyecto(),
    filename:join([Root, "results", filename:basename(ArchivoSalida)]).

% Compatibilidad con la interfaz anterior: Gaussian por defecto.
procesarImagen(ArchivoEntrada, ArchivoSalida, NumProcesos, TamanoKernel) ->
    procesarImagen(ArchivoEntrada, ArchivoSalida, NumProcesos, gaussian, 0, TamanoKernel).

procesarImagen(ArchivoEntrada, ArchivoSalida, NumProcesos, Filtro, Parametro, TamanoKernel) ->
    SalidaResultados = rutaSalidaResultados(ArchivoSalida),
    case validarFiltro(Filtro, Parametro, TamanoKernel) of
        ok ->
            try
                Img = lector(ArchivoEntrada),
                TamanoDivision = tamanoKernelDivision(Filtro, TamanoKernel),
                {Ancho, Alto, Max, Zonas} = dividir(Img, NumProcesos, TamanoDivision),
                ParametrosFiltro = {filtro, Filtro, Parametro, TamanoKernel},
                crearProcesos(Zonas, ParametrosFiltro, self()),
                case recibirResultados(length(Zonas)) of
                    {ok, Resultados} ->
                        Reconstruida = reconstruir(Ancho, Alto, Max, Resultados),
                        case escritor(SalidaResultados, Reconstruida) of
                            ok -> ok;
                            {error, RazonEscritura} -> {error, {no_se_pudo_escribir_salida, RazonEscritura}}
                        end;
                    {error, Errores} -> {error, {fallaron_regiones, Errores}}
                end
            catch
                Clase:Razon:Stack -> {error, {Clase, Razon, Stack}}
            end;
        {error, _} = Error -> Error
    end.

tamanoKernelDivision(gaussian, TamanoKernel) -> TamanoKernel;
tamanoKernelDivision(sharpen, _TamanoKernel) -> 3;
tamanoKernelDivision(sobel, _TamanoKernel) -> 3;
tamanoKernelDivision(_, _TamanoKernel) -> 1.

validarFiltro(gaussian, _Parametro, 3) -> ok;
validarFiltro(gaussian, _Parametro, 5) -> ok;
validarFiltro(grayscale, _Parametro, _TamanoKernel) -> ok;
validarFiltro(invert, _Parametro, _TamanoKernel) -> ok;
validarFiltro(brightness, Parametro, _TamanoKernel) when is_integer(Parametro) -> ok;
validarFiltro(threshold, Parametro, _TamanoKernel) when is_integer(Parametro), Parametro >= 0, Parametro =< 255 -> ok;
validarFiltro(sharpen, _Parametro, _TamanoKernel) -> ok;
validarFiltro(sobel, _Parametro, _TamanoKernel) -> ok;
validarFiltro(Filtro, Parametro, TamanoKernel) -> {error, {parametros_filtro_invalidos, Filtro, Parametro, TamanoKernel}}.


% ============================================================
% INTERFAZ DE LINEA DE COMANDOS
% ============================================================

cli([Entrada, Salida, ProcesosStr | ArgsFiltro]) ->
    try list_to_integer(ProcesosStr) of
        Procesos ->
            case parsearFiltroArgs(ArgsFiltro) of
                {ok, Filtro, Parametro, Kernel} ->
                    case procesarImagen(Entrada, Salida, Procesos, Filtro, Parametro, Kernel) of
                        ok -> io:format("Imagen generada: ~s~n", [Salida]), ok;
                        {error, Razon} -> io:format("Error: ~p~n", [Razon]), {error, Razon}
                    end;
                {error, RazonFiltro} -> mostrarUso(RazonFiltro)
            end
    catch
        _:_ -> mostrarUso(numero_procesos_invalido)
    end;
cli(_) -> mostrarUso(argumentos_invalidos).

parsearFiltroArgs([]) -> {ok, gaussian, 0, 3};
parsearFiltroArgs(["gaussian"]) -> {ok, gaussian, 0, 3};
parsearFiltroArgs(["gaussian", KernelStr]) -> parsearGaussian(KernelStr);
parsearFiltroArgs(["grayscale"]) -> {ok, grayscale, 0, 1};
parsearFiltroArgs(["invert"]) -> {ok, invert, 0, 1};
parsearFiltroArgs(["brightness", ParamStr]) -> parsearParametro(brightness, ParamStr, 1);
parsearFiltroArgs(["threshold", ParamStr]) -> parsearParametro(threshold, ParamStr, 1);
parsearFiltroArgs(["sharpen"]) -> {ok, sharpen, 0, 3};
parsearFiltroArgs(["sobel"]) -> {ok, sobel, 0, 3};
parsearFiltroArgs(_) -> {error, filtro_o_parametros_invalidos}.

parsearGaussian(KernelStr) ->
    try list_to_integer(KernelStr) of
        Kernel ->
            case validarFiltro(gaussian, 0, Kernel) of
                ok -> {ok, gaussian, 0, Kernel};
                {error, _} -> {error, kernel_gaussiano_invalido}
            end
    catch
        _:_ -> {error, kernel_gaussiano_invalido}
    end.

parsearParametro(Filtro, ParamStr, Kernel) ->
    try list_to_integer(ParamStr) of
        Parametro ->
            case validarFiltro(Filtro, Parametro, Kernel) of
                ok -> {ok, Filtro, Parametro, Kernel};
                {error, _} -> {error, parametro_filtro_invalido}
            end
    catch
        _:_ -> {error, parametro_filtro_invalido}
    end.

mostrarUso(Razon) ->
    io:format("Error: ~p~n", [Razon]),
    io:format("Uso:\n"),
    io:format("  ./image_processor entrada.ppm salida.ppm PROCESOS\n"),
    io:format("  ./image_processor entrada.ppm salida.ppm PROCESOS gaussian [3|5]\n"),
    io:format("  ./image_processor entrada.ppm salida.ppm PROCESOS grayscale\n"),
    io:format("  ./image_processor entrada.ppm salida.ppm PROCESOS invert\n"),
    io:format("  ./image_processor entrada.ppm salida.ppm PROCESOS brightness CANTIDAD\n"),
    io:format("  ./image_processor entrada.ppm salida.ppm PROCESOS threshold LIMITE\n"),
    io:format("  ./image_processor entrada.ppm salida.ppm PROCESOS sharpen\n"),
    io:format("  ./image_processor entrada.ppm salida.ppm PROCESOS sobel\n"),
    {error, Razon}.

