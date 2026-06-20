/* ==============================================================
   PRY2206 - Programación de Bases de Datos
   Experiencia 2 - Semana 5
   Caso 1: Cálculo de asignaciones mensuales para los
   profesionales de Dolphin Consulting
   ============================================================== */

SET SERVEROUTPUT ON

-- ---------------------------------------------------------------
-- Variables BIND: fecha del proceso (formato MMYYYY) y monto
-- l&iacute;mite de asignaciones que paga la empresa
-- ---------------------------------------------------------------
VARIABLE g_fecha_proceso VARCHAR2(6)
VARIABLE g_monto_limite  NUMBER

BEGIN
    :g_fecha_proceso := '062021';   -- Mes y a&ntilde;o a procesar (junio 2021)
    :g_monto_limite  := 250000;     -- Monto l&iacute;mite de asignaciones por profesional
END;
/

DECLARE

    -- -------------------------------------------------------------
    -- VARRAY con los 5 porcentajes de movilizaci&oacute;n extra,
    -- en el orden: Santiago, &Ntilde;u&ntilde;oa, La Reina, La Florida, Macul
    -- -------------------------------------------------------------
    TYPE t_varray_movil IS VARRAY(5) OF NUMBER(3,2);
    v_porc_movil t_varray_movil := t_varray_movil(2, 4, 5, 7, 9);

    -- Mes y a&ntilde;o de proceso obtenidos a partir de la variable BIND
    v_mes_proceso  NUMBER(2) := TO_NUMBER(SUBSTR(:g_fecha_proceso, 1, 2));
    v_anno_proceso NUMBER(4) := TO_NUMBER(SUBSTR(:g_fecha_proceso, 3, 4));

    -- -------------------------------------------------------------
    -- Cursor SIN PARAMETRO: solo datos b&aacute;sicos de los
    -- profesionales que tuvieron al menos una asesor&iacute;a en el
    -- mes/a&ntilde;o que se est&aacute; procesando
    -- -------------------------------------------------------------
    CURSOR cur_profesionales IS
        SELECT DISTINCT p.numrun_prof, p.dvrun_prof, p.appaterno, p.apmaterno,
               p.nombre, p.sueldo, p.cod_tpcontrato, p.cod_profesion,
               pr.nombre_profesion, p.cod_comuna
        FROM profesional p
        JOIN profesion pr ON pr.cod_profesion = p.cod_profesion
        WHERE EXISTS (SELECT 1
                        FROM asesoria a
                       WHERE a.numrun_prof = p.numrun_prof
                         AND TO_NUMBER(TO_CHAR(a.inicio_asesoria, 'MM'))   = v_mes_proceso
                         AND TO_NUMBER(TO_CHAR(a.inicio_asesoria, 'YYYY')) = v_anno_proceso)
        ORDER BY pr.nombre_profesion, p.appaterno, p.nombre;

    -- -------------------------------------------------------------
    -- Cursor CON PARAMETRO: porcentaje de asignaci&oacute;n para
    -- una profesi&oacute;n determinada
    -- -------------------------------------------------------------
    CURSOR cur_porc_profesion (p_cod_profesion IN PORCENTAJE_PROFESION.cod_profesion%TYPE) IS
        SELECT pp.asignacion
          FROM PORCENTAJE_PROFESION pp
         WHERE pp.cod_profesion = p_cod_profesion;

    -- -------------------------------------------------------------
    -- REGISTRO usado para armar la fila que se inserta en el detalle
    -- -------------------------------------------------------------
    TYPE t_reg_detalle IS RECORD (
        run_profesional           VARCHAR2(15),
        nombre_profesional        VARCHAR2(50),
        profesion                 VARCHAR2(30),
        nro_asesorias             NUMBER(3),
        monto_honorarios          NUMBER(8),
        monto_movil_extra         NUMBER(8),
        monto_asig_tipocont       NUMBER(8),
        monto_asig_profesion      NUMBER(8),
        monto_total_asignaciones  NUMBER(8)
    );
    r_detalle t_reg_detalle;

    -- -------------------------------------------------------------
    -- Tabla PL/SQL (arreglo asociativo indexado por nombre de
    -- profesi&oacute;n) usada para acumular los totales del resumen
    -- mientras se procesa cada profesional
    -- -------------------------------------------------------------
    TYPE t_reg_resumen IS RECORD (
        total_asesorias            NUMBER(4),
        monto_total_honorarios     NUMBER(8),
        monto_total_movil_extra    NUMBER(8),
        monto_total_asig_tipocont  NUMBER(8),
        monto_total_asig_prof      NUMBER(8),
        monto_total_asignaciones   NUMBER(8)
    );
    TYPE t_tab_resumen IS TABLE OF t_reg_resumen INDEX BY VARCHAR2(30);
    v_resumen        t_tab_resumen;
    v_profesion_idx  VARCHAR2(30);

    -- Variables de trabajo para los c&aacute;lculos del proceso
    v_nro_asesorias   NUMBER(3);
    v_tot_honorarios  NUMBER(8);
    v_porc_incentivo  tipo_contrato.incentivo%TYPE;
    v_porc_asig_prof  PORCENTAJE_PROFESION.asignacion%TYPE;
    v_movil_extra     NUMBER(8);
    v_asig_tipocont   NUMBER(8);
    v_asig_profesion  NUMBER(8);
    v_total_asig      NUMBER(8);
    v_msg_error_oracle VARCHAR2(300);

    -- Excepci&oacute;n definida por el usuario: el total de
    -- asignaciones de un profesional supera el monto l&iacute;mite
    e_excede_limite EXCEPTION;

    -- Excepci&oacute;n NO PREDEFINIDA: se intenta insertar un valor
    -- NULO en una columna obligatoria (NOT NULL) del detalle
    e_valor_nulo EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_valor_nulo, -01400);

BEGIN

    -- -----------------------------------------------------------
    -- Se truncan las tablas de resultado para permitir reejecutar
    -- el bloque las veces que se requiera
    -- -----------------------------------------------------------
    EXECUTE IMMEDIATE 'TRUNCATE TABLE detalle_asignacion_mes';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE resumen_mes_profesion';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE errores_proceso';

    -- -----------------------------------------------------------
    -- Se elimina y se vuelve a crear la secuencia usada para el
    -- ID de la tabla de errores
    -- -----------------------------------------------------------
    BEGIN
        EXECUTE IMMEDIATE 'DROP SEQUENCE sq_error';
    EXCEPTION
        WHEN OTHERS THEN
            NULL; -- la secuencia a&uacute;n no exist&iacute;a, se continua sin problema
    END;
    EXECUTE IMMEDIATE 'CREATE SEQUENCE sq_error START WITH 1 INCREMENT BY 1';

    -- -----------------------------------------------------------
    -- Se recorre cada profesional con asesor&iacute;as en el
    -- mes/a&ntilde;o procesado
    -- -----------------------------------------------------------
    FOR reg_prof IN cur_profesionales LOOP

        -- SELECT por separado: cantidad de asesor&iacute;as y total
        -- de honorarios del profesional en el periodo procesado
        -- (funciones de grupo COUNT y SUM en la misma sentencia)
        SELECT COUNT(*), SUM(a.honorario)
          INTO v_nro_asesorias, v_tot_honorarios
          FROM asesoria a
         WHERE a.numrun_prof = reg_prof.numrun_prof
           AND TO_NUMBER(TO_CHAR(a.inicio_asesoria, 'MM'))   = v_mes_proceso
           AND TO_NUMBER(TO_CHAR(a.inicio_asesoria, 'YYYY')) = v_anno_proceso;

        -- SELECT por separado: porcentaje de incentivo seg&uacute;n
        -- el tipo de contrato del profesional. Se controla la
        -- excepci&oacute;n PREDEFINIDA NO_DATA_FOUND.
        BEGIN
            SELECT tc.incentivo
              INTO v_porc_incentivo
              FROM tipo_contrato tc
             WHERE tc.cod_tpcontrato = reg_prof.cod_tpcontrato;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_msg_error_oracle := SQLERRM;
                INSERT INTO errores_proceso (error_id, mensaje_error_oracle, mensaje_error_usr)
                VALUES (sq_error.NEXTVAL, v_msg_error_oracle,
                        'No se encontro el tipo de contrato del profesional ' || reg_prof.numrun_prof);
                v_porc_incentivo := 0;
        END;

        -- SELECT por separado, a trav&eacute;s del CURSOR CON PARAMETRO
        -- cur_porc_profesion: porcentaje de asignaci&oacute;n por
        -- profesi&oacute;n. Se controla CUALQUIER error Oracle al
        -- recuperarlo (bloque anidado)
        BEGIN
            OPEN cur_porc_profesion(reg_prof.cod_profesion);
            FETCH cur_porc_profesion INTO v_porc_asig_prof;
            IF cur_porc_profesion%NOTFOUND THEN
                CLOSE cur_porc_profesion;
                RAISE NO_DATA_FOUND;
            END IF;
            CLOSE cur_porc_profesion;
        EXCEPTION
            WHEN OTHERS THEN
                IF cur_porc_profesion%ISOPEN THEN
                    CLOSE cur_porc_profesion;
                END IF;
                v_msg_error_oracle := SQLERRM;
                INSERT INTO errores_proceso (error_id, mensaje_error_oracle, mensaje_error_usr)
                VALUES (sq_error.NEXTVAL, v_msg_error_oracle,
                        'No se pudo obtener el porcentaje de asignacion de la profesion '
                        || reg_prof.nombre_profesion || ' (profesional ' || reg_prof.numrun_prof || ')');
                v_porc_asig_prof := 0;
        END;

        -- -------------------------------------------------------
        -- Todos los c&aacute;lculos se realizan en PL/SQL, no en SQL
        -- -------------------------------------------------------

        -- Asignaci&oacute;n de movilizaci&oacute;n extra seg&uacute;n comuna.
        -- Se compara por COD_COMUNA (numero) y no por nombre, para evitar
        -- problemas de codificaci&oacute;n de caracteres con tildes/enie
        -- (82=Santiago, 83=Nunoa, 85=La Reina, 86=La Florida, 89=Macul)
        IF reg_prof.cod_comuna = 82 AND v_tot_honorarios < 350000 THEN
            v_movil_extra := ROUND(v_tot_honorarios * v_porc_movil(1) / 100);
        ELSIF reg_prof.cod_comuna = 83 THEN
            v_movil_extra := ROUND(v_tot_honorarios * v_porc_movil(2) / 100);
        ELSIF reg_prof.cod_comuna = 85 AND v_tot_honorarios < 400000 THEN
            v_movil_extra := ROUND(v_tot_honorarios * v_porc_movil(3) / 100);
        ELSIF reg_prof.cod_comuna = 86 AND v_tot_honorarios < 800000 THEN
            v_movil_extra := ROUND(v_tot_honorarios * v_porc_movil(4) / 100);
        ELSIF reg_prof.cod_comuna = 89 AND v_tot_honorarios < 680000 THEN
            v_movil_extra := ROUND(v_tot_honorarios * v_porc_movil(5) / 100);
        ELSE
            v_movil_extra := 0;
        END IF;

        -- Asignaci&oacute;n por tipo de contrato, sobre el total de honorarios
        v_asig_tipocont := ROUND(v_tot_honorarios * v_porc_incentivo / 100);

        -- Asignaci&oacute;n por profesi&oacute;n, sobre el sueldo del profesional
        v_asig_profesion := ROUND(reg_prof.sueldo * v_porc_asig_prof / 100);

        -- Total de asignaciones del profesional
        v_total_asig := v_movil_extra + v_asig_tipocont + v_asig_profesion;

        -- Excepci&oacute;n definida por el usuario: el total supera el l&iacute;mite
        BEGIN
            IF v_total_asig > :g_monto_limite THEN
                RAISE e_excede_limite;
            END IF;
        EXCEPTION
            WHEN e_excede_limite THEN
                INSERT INTO errores_proceso (error_id, mensaje_error_oracle, mensaje_error_usr)
                VALUES (sq_error.NEXTVAL, NULL,
                        'El total de asignaciones del profesional ' || reg_prof.numrun_prof
                        || ' supera el monto limite de ' || :g_monto_limite);
                v_total_asig := :g_monto_limite;
        END;

        -- -------------------------------------------------------
        -- Se arma el REGISTRO y se inserta en el detalle del mes
        -- -------------------------------------------------------
        r_detalle.run_profesional          := reg_prof.numrun_prof || '-' || reg_prof.dvrun_prof;
        r_detalle.nombre_profesional       := SUBSTR(TRIM(reg_prof.appaterno) || ' ' || TRIM(reg_prof.apmaterno) || ' ' || TRIM(reg_prof.nombre), 1, 50);
        r_detalle.profesion                := reg_prof.nombre_profesion;
        r_detalle.nro_asesorias            := v_nro_asesorias;
        r_detalle.monto_honorarios         := v_tot_honorarios;
        r_detalle.monto_movil_extra        := v_movil_extra;
        r_detalle.monto_asig_tipocont      := v_asig_tipocont;
        r_detalle.monto_asig_profesion     := v_asig_profesion;
        r_detalle.monto_total_asignaciones := v_total_asig;

        BEGIN
        INSERT INTO detalle_asignacion_mes (
            mes_proceso, anno_proceso, run_profesional, nombre_profesional, profesion,
            nro_asesorias, monto_honorarios, monto_movil_extra, monto_asig_tipocont,
            monto_asig_profesion, monto_total_asignaciones)
        VALUES (
            v_mes_proceso, v_anno_proceso, r_detalle.run_profesional, r_detalle.nombre_profesional,
            r_detalle.profesion, r_detalle.nro_asesorias, r_detalle.monto_honorarios,
            r_detalle.monto_movil_extra, r_detalle.monto_asig_tipocont,
            r_detalle.monto_asig_profesion, r_detalle.monto_total_asignaciones);
        EXCEPTION
            WHEN e_valor_nulo THEN
                v_msg_error_oracle := SQLERRM;
                INSERT INTO errores_proceso (error_id, mensaje_error_oracle, mensaje_error_usr)
                VALUES (sq_error.NEXTVAL, v_msg_error_oracle,
                        'No se pudo insertar el detalle del profesional ' || reg_prof.numrun_prof
                        || ' por valores nulos en columnas obligatorias');
        END;

        -- -------------------------------------------------------
        -- Se acumulan los totales por profesi&oacute;n para el resumen
        -- -------------------------------------------------------
        v_profesion_idx := reg_prof.nombre_profesion;

        IF v_resumen.EXISTS(v_profesion_idx) THEN
            v_resumen(v_profesion_idx).total_asesorias           := v_resumen(v_profesion_idx).total_asesorias + v_nro_asesorias;
            v_resumen(v_profesion_idx).monto_total_honorarios     := v_resumen(v_profesion_idx).monto_total_honorarios + v_tot_honorarios;
            v_resumen(v_profesion_idx).monto_total_movil_extra    := v_resumen(v_profesion_idx).monto_total_movil_extra + v_movil_extra;
            v_resumen(v_profesion_idx).monto_total_asig_tipocont  := v_resumen(v_profesion_idx).monto_total_asig_tipocont + v_asig_tipocont;
            v_resumen(v_profesion_idx).monto_total_asig_prof      := v_resumen(v_profesion_idx).monto_total_asig_prof + v_asig_profesion;
            v_resumen(v_profesion_idx).monto_total_asignaciones   := v_resumen(v_profesion_idx).monto_total_asignaciones + v_total_asig;
        ELSE
            v_resumen(v_profesion_idx).total_asesorias           := v_nro_asesorias;
            v_resumen(v_profesion_idx).monto_total_honorarios     := v_tot_honorarios;
            v_resumen(v_profesion_idx).monto_total_movil_extra    := v_movil_extra;
            v_resumen(v_profesion_idx).monto_total_asig_tipocont  := v_asig_tipocont;
            v_resumen(v_profesion_idx).monto_total_asig_prof      := v_asig_profesion;
            v_resumen(v_profesion_idx).monto_total_asignaciones   := v_total_asig;
        END IF;

    END LOOP;

    -- -----------------------------------------------------------
    -- Se recorre el resumen acumulado (ordenado en forma ascendente
    -- por profesi&oacute;n) y se inserta en RESUMEN_MES_PROFESION
    -- -----------------------------------------------------------
    v_profesion_idx := v_resumen.FIRST;
    WHILE v_profesion_idx IS NOT NULL LOOP

        INSERT INTO resumen_mes_profesion (
            anno_mes_proceso, profesion, total_asesorias, monto_total_honorarios,
            monto_total_movil_extra, monto_total_asig_tipocont, monto_total_asig_prof,
            monto_total_asignaciones)
        VALUES (
            v_anno_proceso * 100 + v_mes_proceso, v_profesion_idx,
            v_resumen(v_profesion_idx).total_asesorias,
            v_resumen(v_profesion_idx).monto_total_honorarios,
            v_resumen(v_profesion_idx).monto_total_movil_extra,
            v_resumen(v_profesion_idx).monto_total_asig_tipocont,
            v_resumen(v_profesion_idx).monto_total_asig_prof,
            v_resumen(v_profesion_idx).monto_total_asignaciones);

        v_profesion_idx := v_resumen.NEXT(v_profesion_idx);
    END LOOP;

    -- -----------------------------------------------------------
    -- Se confirma la transacci&oacute;n solo si el proceso termin&oacute;
    -- correctamente
    -- -----------------------------------------------------------
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Proceso finalizado correctamente para el periodo ' || :g_fecha_proceso);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error inesperado en el proceso: ' || SQLERRM);

END;
/

-- ==============================================================
-- Consultas de verificaci&oacute;n de los resultados del proceso
-- ==============================================================
SELECT * FROM detalle_asignacion_mes ORDER BY profesion, run_profesional;
SELECT * FROM resumen_mes_profesion ORDER BY profesion;
SELECT * FROM errores_proceso ORDER BY error_id;
