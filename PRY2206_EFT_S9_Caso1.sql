/* ==============================================================
   PRY2206 - Programacion de Bases de Datos
   Evaluacion Final Transversal (EFT) - Semana 9
   Caso 1: Sistema de asignacion de puntajes para postulantes
           a becas de perfeccionamiento docente
   ============================================================== */

SET SERVEROUTPUT ON

-- ==============================================================
-- PACKAGE PKG_PUNTAJE_EXTRA
-- Contiene:
--   v_puntaje_extra : variable publica que almacena el puntaje
--                     extra calculado por la funcion del package.
--   FN_CALC_PUNTAJE_EXTRA: funcion publica que calcula el puntaje
--                     extra (regla de negocio 1.3).
-- ==============================================================
CREATE OR REPLACE PACKAGE PKG_PUNTAJE_EXTRA AS

    -- Variable publica para almacenar el puntaje extra calculado
    -- por la funcion FN_CALC_PUNTAJE_EXTRA (regla de negocio 1.3)
    v_puntaje_extra NUMBER := 0;

    -- Funcion que calcula el puntaje extra para postulantes que:
    --   1) Trabajan en MAS DE UN establecimiento, Y
    --   2) La suma de horas semanales supera las 30 horas
    -- El puntaje extra = porcentaje % de (ptje_annos_exp + ptje_pais_postula)
    FUNCTION FN_CALC_PUNTAJE_EXTRA (
        p_numrun        IN ANTECEDENTES_PERSONALES.numrun%TYPE,
        p_ptje_exp      IN NUMBER,
        p_ptje_pais     IN NUMBER,
        p_porcentaje    IN NUMBER
    ) RETURN NUMBER;

END PKG_PUNTAJE_EXTRA;
/

CREATE OR REPLACE PACKAGE BODY PKG_PUNTAJE_EXTRA AS

    -- ----------------------------------------------------------
    -- Implementacion de FN_CALC_PUNTAJE_EXTRA
    -- Calcula el puntaje extra si el postulante trabaja en mas
    -- de un establecimiento Y suma mas de 30 horas semanales.
    -- En caso contrario retorna 0.
    -- ----------------------------------------------------------
    FUNCTION FN_CALC_PUNTAJE_EXTRA (
        p_numrun        IN ANTECEDENTES_PERSONALES.numrun%TYPE,
        p_ptje_exp      IN NUMBER,
        p_ptje_pais     IN NUMBER,
        p_porcentaje    IN NUMBER
    ) RETURN NUMBER IS
        v_cant_establecimientos NUMBER := 0;
        v_total_horas           NUMBER := 0;
        v_puntaje               NUMBER := 0;
    BEGIN
        -- Cuenta la cantidad de establecimientos distintos donde trabaja
        -- el postulante y suma sus horas semanales totales
        SELECT COUNT(*), NVL(SUM(horas_semanales), 0)
          INTO v_cant_establecimientos, v_total_horas
          FROM ANTECEDENTES_LABORALES
         WHERE numrun = p_numrun;

        -- Regla 1.3: mas de un establecimiento Y mas de 30 horas totales
        IF v_cant_establecimientos > 1 AND v_total_horas > 30 THEN
            -- Puntaje extra = porcentaje % de la suma de puntajes 1.1 y 1.2
            v_puntaje := ROUND((p_ptje_exp + p_ptje_pais) * p_porcentaje / 100);
        ELSE
            v_puntaje := 0;
        END IF;

        RETURN v_puntaje;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN 0;
    END FN_CALC_PUNTAJE_EXTRA;

END PKG_PUNTAJE_EXTRA;
/

-- ==============================================================
-- FUNCION ALMACENADA FN_PTJE_ANNOS_EXPERIENCIA
-- Regla 1.1: obtiene el puntaje por anios de experiencia del
-- postulante. Considera la fecha de contrato MAS ANTIGUA
-- de todos sus registros en ANTECEDENTES_LABORALES.
-- Los anios de experiencia se calculan a la fecha de ejecucion.
-- En caso de error, registra en ERROR_PROCESO y retorna 0.
-- ==============================================================
CREATE OR REPLACE FUNCTION FN_PTJE_ANNOS_EXPERIENCIA (
    p_numrun IN ANTECEDENTES_PERSONALES.numrun%TYPE
) RETURN NUMBER IS
    v_fecha_ant    DATE;
    v_annos_exp    NUMBER;
    v_puntaje      NUMBER;
    v_msg_error    VARCHAR2(250);

    -- Excepcion NO PREDEFINIDA: violacion de restriccion CHECK (ORA-02290)
    e_check_violado EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_check_violado, -02290);
BEGIN
    -- Obtiene la fecha de contrato mas antigua del postulante
    -- considerando todos sus antecedentes laborales
    SELECT MIN(fecha_contrato)
      INTO v_fecha_ant
      FROM ANTECEDENTES_LABORALES
     WHERE numrun = p_numrun;

    -- Calcula los anios de experiencia desde la fecha mas antigua
    -- hasta la fecha actual de ejecucion del proceso
    v_annos_exp := TRUNC(MONTHS_BETWEEN(SYSDATE, v_fecha_ant) / 12);

    -- Busca el puntaje en la tabla PTJE_ANNOS_EXPERIENCIA segun
    -- el rango de anios que corresponde al postulante
    SELECT ptje_experiencia
      INTO v_puntaje
      FROM PTJE_ANNOS_EXPERIENCIA
     WHERE v_annos_exp BETWEEN rango_annos_ini AND rango_annos_ter;

    RETURN v_puntaje;

EXCEPTION
    -- Excepcion predefinida: no existe tramo para esa antiguedad
    WHEN NO_DATA_FOUND THEN
        v_msg_error := SQLERRM;
        INSERT INTO ERROR_PROCESO (id_error, rutina_error, mensaje_error)
        VALUES (SEQ_ERROR.NEXTVAL,
                'FN_PTJE_ANNOS_EXPERIENCIA',
                SUBSTR('No se encontro tramo de experiencia para numrun=' || p_numrun
                       || '. Error: ' || v_msg_error, 1, 250));
        RETURN 0;
    -- Excepcion no predefinida: violacion de restriccion CHECK
    WHEN e_check_violado THEN
        v_msg_error := SQLERRM;
        INSERT INTO ERROR_PROCESO (id_error, rutina_error, mensaje_error)
        VALUES (SEQ_ERROR.NEXTVAL,
                'FN_PTJE_ANNOS_EXPERIENCIA',
                SUBSTR('Violacion de restriccion al leer puntaje para numrun=' || p_numrun
                       || '. Error: ' || v_msg_error, 1, 250));
        RETURN 0;
    -- Cualquier otro error Oracle al obtener el puntaje de experiencia
    WHEN OTHERS THEN
        v_msg_error := SQLERRM;
        INSERT INTO ERROR_PROCESO (id_error, rutina_error, mensaje_error)
        VALUES (SEQ_ERROR.NEXTVAL,
                'FN_PTJE_ANNOS_EXPERIENCIA',
                SUBSTR('Error al obtener puntaje experiencia para numrun=' || p_numrun
                       || '. Error: ' || v_msg_error, 1, 250));
        RETURN 0;
END FN_PTJE_ANNOS_EXPERIENCIA;
/

-- ==============================================================
-- FUNCION ALMACENADA FN_PTJE_PAIS_POSTULA
-- Regla 1.2: obtiene el puntaje segun el pais al que pertenece
-- la institucion que imparte el programa de pasantia elegido.
-- En caso de error, registra en ERROR_PROCESO y retorna 0.
-- ==============================================================
CREATE OR REPLACE FUNCTION FN_PTJE_PAIS_POSTULA (
    p_numrun IN ANTECEDENTES_PERSONALES.numrun%TYPE
) RETURN NUMBER IS
    v_cod_pais  NUMBER;
    v_puntaje   NUMBER;
    v_msg_error VARCHAR2(250);
BEGIN
    -- Obtiene el pais de la institucion que imparte el programa
    -- al que postula el postulante, navegando por las relaciones:
    -- POSTULACION -> PASANTIA -> INSTITUCION -> PAIS
    SELECT i.cod_pais
      INTO v_cod_pais
      FROM POSTULACION_PASANTIA_PERFEC pp
      JOIN PASANTIA_PERFECCIONAMIENTO  pa ON pa.cod_programa = pp.cod_programa
      JOIN INSTITUCION                  i  ON i.cod_inst      = pa.cod_inst
     WHERE pp.numrun = p_numrun;

    -- Busca el puntaje en PTJE_PAIS_POSTULA segun el pais obtenido
    SELECT ptje_pais
      INTO v_puntaje
      FROM PTJE_PAIS_POSTULA
     WHERE cod_pais = v_cod_pais;

    RETURN v_puntaje;

EXCEPTION
    -- Excepcion predefinida: no existe postulacion o puntaje para ese pais
    WHEN NO_DATA_FOUND THEN
        v_msg_error := SQLERRM;
        INSERT INTO ERROR_PROCESO (id_error, rutina_error, mensaje_error)
        VALUES (SEQ_ERROR.NEXTVAL,
                'FN_PTJE_PAIS_POSTULA',
                SUBSTR('No se encontro puntaje de pais para numrun=' || p_numrun
                       || '. Error: ' || v_msg_error, 1, 250));
        RETURN 0;
    -- Excepcion predefinida: mas de un registro retornado (datos inconsistentes)
    WHEN TOO_MANY_ROWS THEN
        v_msg_error := SQLERRM;
        INSERT INTO ERROR_PROCESO (id_error, rutina_error, mensaje_error)
        VALUES (SEQ_ERROR.NEXTVAL,
                'FN_PTJE_PAIS_POSTULA',
                SUBSTR('Multiples postulaciones encontradas para numrun=' || p_numrun
                       || '. Error: ' || v_msg_error, 1, 250));
        RETURN 0;
    -- Cualquier otro error Oracle al obtener el puntaje de pais
    WHEN OTHERS THEN
        v_msg_error := SQLERRM;
        INSERT INTO ERROR_PROCESO (id_error, rutina_error, mensaje_error)
        VALUES (SEQ_ERROR.NEXTVAL,
                'FN_PTJE_PAIS_POSTULA',
                SUBSTR('Error al obtener puntaje pais para numrun=' || p_numrun
                       || '. Error: ' || v_msg_error, 1, 250));
        RETURN 0;
END FN_PTJE_PAIS_POSTULA;
/

-- ==============================================================
-- TRIGGER TRG_RESULTADO_POSTULACION
-- Se activa automaticamente AFTER INSERT en DETALLE_PUNTAJE_POSTULACION.
-- Calcula el puntaje final (suma de los 3 puntajes) y determina
-- si el postulante queda SELECCIONADO (>= 2500) o NO SELECCIONADO.
-- Inserta el resultado en la tabla RESULTADO_POSTULACION.
-- ==============================================================
CREATE OR REPLACE TRIGGER TRG_RESULTADO_POSTULACION
AFTER INSERT ON DETALLE_PUNTAJE_POSTULACION
FOR EACH ROW
DECLARE
    v_ptje_final   NUMBER;
    v_resultado    VARCHAR2(20);
    -- Constante: puntaje minimo para quedar seleccionado
    C_PUNTAJE_MIN CONSTANT NUMBER := 2500;
BEGIN
    -- Calcula el puntaje final sumando los 3 puntajes del detalle:
    -- puntaje por pais + puntaje por experiencia + puntaje extra
    v_ptje_final := :NEW.ptje_pais_postula + :NEW.ptje_annos_exp + :NEW.ptje_extra;

    -- Determina el resultado segun el puntaje final obtenido
    IF v_ptje_final >= C_PUNTAJE_MIN THEN
        v_resultado := 'SELECCIONADO';
    ELSE
        v_resultado := 'NO SELECCIONADO';
    END IF;

    -- Inserta el resultado en RESULTADO_POSTULACION con el run,
    -- puntaje final y resultado de la postulacion
    INSERT INTO RESULTADO_POSTULACION (run_postulante, ptje_final_post, resultado_post)
    VALUES (:NEW.run_postulante, v_ptje_final, v_resultado);

END TRG_RESULTADO_POSTULACION;
/

-- ==============================================================
-- PROCEDIMIENTO ALMACENADO PRC_PROCESAR_POSTULACIONES
-- Procedimiento principal que procesa TODOS los postulantes.
-- Parametro de entrada:
--   p_porcentaje: porcentaje para calculo de puntaje extra (regla 1.3)
--                 ingresado en forma parametrica via variable BIND.
-- Integra las funciones almacenadas y el package para calcular
-- los puntajes y llenar la tabla DETALLE_PUNTAJE_POSTULACION.
-- El trigger se activa automaticamente con cada INSERT.
-- ==============================================================
CREATE OR REPLACE PROCEDURE PRC_PROCESAR_POSTULACIONES (
    p_porcentaje IN NUMBER
) IS

    -- Cursor que recorre TODOS los postulantes registrados,
    -- ordenados por numrun segun lo indicado en el enunciado
    CURSOR cur_postulantes IS
        SELECT ap.numrun,
               ap.dvrun,
               TRIM(ap.pnombre) || ' ' || NVL(TRIM(ap.snombre) || ' ', '')
               || TRIM(ap.apaterno) || ' ' || TRIM(ap.amaterno) AS nombre_completo
          FROM ANTECEDENTES_PERSONALES ap
         WHERE EXISTS (SELECT 1
                         FROM POSTULACION_PASANTIA_PERFEC pp
                        WHERE pp.numrun = ap.numrun)
         ORDER BY ap.numrun;

    -- Variables para almacenar los puntajes calculados
    v_ptje_exp      NUMBER := 0;
    v_ptje_pais     NUMBER := 0;
    v_ptje_extra    NUMBER := 0;
    v_run_formato   VARCHAR2(13);

    -- Excepcion NO PREDEFINIDA: violacion de clave primaria al insertar
    -- en DETALLE_PUNTAJE_POSTULACION (ORA-00001)
    e_pk_duplicada EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_pk_duplicada, -00001);

    v_msg_error VARCHAR2(250);

BEGIN

    -- ----------------------------------------------------------
    -- Trunca las tres tablas resultantes del proceso para
    -- permitir la reejecution limpia del procedimiento
    -- ----------------------------------------------------------
    EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_PUNTAJE_POSTULACION';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE RESULTADO_POSTULACION';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERROR_PROCESO';

    DBMS_OUTPUT.PUT_LINE('Porcentaje puntaje extra: ' || p_porcentaje || '%');
    DBMS_OUTPUT.PUT_LINE('Inicio del proceso de postulaciones...');

    -- ----------------------------------------------------------
    -- Recorre cada postulante y calcula sus puntajes
    -- ----------------------------------------------------------
    FOR reg IN cur_postulantes LOOP

        -- Formatea el run como "numrun-dvrun" para el campo run_postulante
        v_run_formato := reg.numrun || '-' || reg.dvrun;

        -- Obtiene el puntaje por anios de experiencia usando la
        -- funcion almacenada FN_PTJE_ANNOS_EXPERIENCIA (regla 1.1)
        v_ptje_exp := FN_PTJE_ANNOS_EXPERIENCIA(reg.numrun);

        -- Obtiene el puntaje por pais de la institucion usando la
        -- funcion almacenada FN_PTJE_PAIS_POSTULA (regla 1.2)
        v_ptje_pais := FN_PTJE_PAIS_POSTULA(reg.numrun);

        -- Calcula el puntaje extra usando la funcion del Package
        -- y almacena el resultado en la variable publica del Package
        PKG_PUNTAJE_EXTRA.v_puntaje_extra :=
            PKG_PUNTAJE_EXTRA.FN_CALC_PUNTAJE_EXTRA(
                reg.numrun, v_ptje_exp, v_ptje_pais, p_porcentaje
            );
        v_ptje_extra := PKG_PUNTAJE_EXTRA.v_puntaje_extra;

        -- Inserta el detalle de puntajes en DETALLE_PUNTAJE_POSTULACION.
        -- El TRIGGER TRG_RESULTADO_POSTULACION se dispara automaticamente
        -- con este INSERT e inserta el resultado en RESULTADO_POSTULACION.
        BEGIN
            INSERT INTO DETALLE_PUNTAJE_POSTULACION (
                run_postulante, nombre_postulante,
                ptje_annos_exp, ptje_pais_postula, ptje_extra
            ) VALUES (
                v_run_formato,
                SUBSTR(reg.nombre_completo, 1, 60),
                v_ptje_exp, v_ptje_pais, v_ptje_extra
            );
        EXCEPTION
            -- Excepcion no predefinida: registro duplicado (ORA-00001)
            WHEN e_pk_duplicada THEN
                v_msg_error := SQLERRM;
                INSERT INTO ERROR_PROCESO (id_error, rutina_error, mensaje_error)
                VALUES (SEQ_ERROR.NEXTVAL,
                        'PRC_PROCESAR_POSTULACIONES',
                        SUBSTR('Registro duplicado para run=' || v_run_formato
                               || '. Error: ' || v_msg_error, 1, 250));
        END;

    END LOOP;

    -- Confirma la transaccion solo si el proceso termino correctamente
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Proceso finalizado correctamente.');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error critico en PRC_PROCESAR_POSTULACIONES: ' || SQLERRM);
END PRC_PROCESAR_POSTULACIONES;
/

-- ==============================================================
-- VARIABLE BIND: porcentaje para el calculo del puntaje extra
-- El valor se ingresa en forma parametrica segun lo indicado
-- en el enunciado (ejemplo: 35%)
-- ==============================================================
VARIABLE g_porcentaje NUMBER
BEGIN
    :g_porcentaje := 35;  -- Porcentaje para el puntaje extra (regla 1.3)
END;
/

-- ==============================================================
-- EJECUCION DEL PROCEDIMIENTO PRINCIPAL
-- ==============================================================
BEGIN
    PRC_PROCESAR_POSTULACIONES(:g_porcentaje);
END;
/

-- ==============================================================
-- CONSULTAS DE VERIFICACION DE RESULTADOS
-- ==============================================================
SELECT run_postulante,
       nombre_postulante,
       ptje_annos_exp,
       ptje_pais_postula,
       ptje_extra
  FROM DETALLE_PUNTAJE_POSTULACION
 ORDER BY run_postulante;

SELECT run_postulante,
       ptje_final_post,
       resultado_post
  FROM RESULTADO_POSTULACION
 ORDER BY run_postulante;

SELECT id_error,
       rutina_error,
       mensaje_error
  FROM ERROR_PROCESO
 ORDER BY id_error;
