/* ==============================================================
   PRY2206 - Programacion de Bases de Datos
   Experiencia 3 - Semana 8
   Caso 1: Liquidacion de asignaciones especiales + Trigger
   Empresa: SPA Products
   ============================================================== */

SET SERVEROUTPUT ON

-- ==============================================================
-- PACKAGE PKG_LIQUIDACION
-- Contiene:
--   - Procedimiento para insertar errores (PRC_INSERT_ERROR)
--   - Funcion que retorna promedio ventas anno anterior (FN_PROMEDIO_VENTAS)
--   - Variable publica con el promedio calculado (v_promedio_ventas)
-- ==============================================================
CREATE OR REPLACE PACKAGE PKG_LIQUIDACION AS

    -- Variable publica usada por el procedimiento principal
    -- para recuperar el monto promedio de ventas del anno anterior
    v_promedio_ventas NUMBER := 0;

    -- Procedimiento que inserta los errores producidos al obtener
    -- porcentajes de antiguedad o escolaridad en ERROR_CALC
    PROCEDURE PRC_INSERT_ERROR (
        p_rutina    IN ERROR_CALC.RUTINA_ERROR%TYPE,
        p_descrip   IN ERROR_CALC.DESCRIP_ERROR%TYPE,
        p_usr       IN ERROR_CALC.DESCRIP_USER%TYPE
    );

    -- Funcion que retorna el promedio de ventas (VALOR_TOTAL de
    -- DETALLE_BOLETA) del anno anterior al anno procesado.
    -- Si no hay boletas ese anno, retorna 0.
    FUNCTION FN_PROMEDIO_VENTAS (
        p_anno IN NUMBER
    ) RETURN NUMBER;

END PKG_LIQUIDACION;
/

CREATE OR REPLACE PACKAGE BODY PKG_LIQUIDACION AS

    -- ----------------------------------------------------------
    -- Implementacion de PRC_INSERT_ERROR
    -- ----------------------------------------------------------
    PROCEDURE PRC_INSERT_ERROR (
        p_rutina    IN ERROR_CALC.RUTINA_ERROR%TYPE,
        p_descrip   IN ERROR_CALC.DESCRIP_ERROR%TYPE,
        p_usr       IN ERROR_CALC.DESCRIP_USER%TYPE
    ) IS
    BEGIN
        -- Inserta el error usando la secuencia SEQ_ERROR para el correlativo
        INSERT INTO ERROR_CALC (CORREL_ERROR, RUTINA_ERROR, DESCRIP_ERROR, DESCRIP_USER)
        VALUES (SEQ_ERROR.NEXTVAL, p_rutina, p_descrip, p_usr);
    END PRC_INSERT_ERROR;

    -- ----------------------------------------------------------
    -- Implementacion de FN_PROMEDIO_VENTAS
    -- Calcula el promedio de VALOR_TOTAL de DETALLE_BOLETA
    -- para todas las boletas del anno anterior al procesado.
    -- ----------------------------------------------------------
    FUNCTION FN_PROMEDIO_VENTAS (
        p_anno IN NUMBER
    ) RETURN NUMBER IS
        v_promedio NUMBER := 0;
        v_anno_anterior NUMBER := p_anno - 1;
    BEGIN
        -- Suma todos los VALOR_TOTAL de los detalles de boleta
        -- del anno anterior y los promedia por la cantidad de registros
        SELECT NVL(AVG(db.VALOR_TOTAL), 0)
          INTO v_promedio
          FROM DETALLE_BOLETA db
          JOIN BOLETA b ON b.NRO_BOLETA = db.NRO_BOLETA
         WHERE EXTRACT(YEAR FROM b.FECHA) = v_anno_anterior;

        RETURN v_promedio;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            -- No hubo boletas ese anno: retorna 0 segun enunciado
            RETURN 0;
        WHEN OTHERS THEN
            RETURN 0;
    END FN_PROMEDIO_VENTAS;

END PKG_LIQUIDACION;
/

-- ==============================================================
-- FUNCION FN_PORC_ANTIGUEDAD
-- Retorna el porcentaje de antiguedad correspondiente a los
-- annos que lleva trabajando el empleado en la empresa.
-- En caso de error, llama a PRC_INSERT_ERROR y retorna 0.
-- ==============================================================
CREATE OR REPLACE FUNCTION FN_PORC_ANTIGUEDAD (
    p_run_empleado IN EMPLEADO.RUN_EMPLEADO%TYPE,
    p_fecha_contrato IN EMPLEADO.FECHA_CONTRATO%TYPE
) RETURN NUMBER IS
    v_annos_antiguedad NUMBER;
    v_porcentaje       PCT_ANTIGUEDAD.PORC_ANTIGUEDAD%TYPE;
    v_msg_error        VARCHAR2(300);
BEGIN
    -- Calcula los annos transcurridos desde la fecha de contrato
    -- hasta la fecha actual usando MONTHS_BETWEEN y SYSDATE
    v_annos_antiguedad := TRUNC(MONTHS_BETWEEN(SYSDATE, p_fecha_contrato) / 12);

    -- Busca el porcentaje en PCT_ANTIGUEDAD segun el tramo de annos
    SELECT PORC_ANTIGUEDAD
      INTO v_porcentaje
      FROM PCT_ANTIGUEDAD
     WHERE v_annos_antiguedad BETWEEN ANNOS_ANTIGUEDAD_INF AND ANNOS_ANTIGUEDAD_SUP;

    RETURN v_porcentaje;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- Excepcion predefinida: no existe tramo para esa antiguedad
        v_msg_error := SQLERRM;
        PKG_LIQUIDACION.PRC_INSERT_ERROR(
            'FN_PORC_ANTIGUEDAD',
            v_msg_error,
            'No se encontro tramo de antiguedad para el empleado ' || p_run_empleado
            || ' con ' || v_annos_antiguedad || ' annos de servicio'
        );
        RETURN 0;
    WHEN OTHERS THEN
        -- Cualquier otro error Oracle al leer porcentaje
        v_msg_error := SQLERRM;
        PKG_LIQUIDACION.PRC_INSERT_ERROR(
            'FN_PORC_ANTIGUEDAD',
            v_msg_error,
            'Error inesperado al obtener porcentaje de antiguedad para empleado ' || p_run_empleado
        );
        RETURN 0;
END FN_PORC_ANTIGUEDAD;
/

-- ==============================================================
-- FUNCION FN_PORC_ESCOLARIDAD
-- Retorna el porcentaje de escolaridad del empleado segun su
-- COD_ESCOLARIDAD desde PCT_NIVEL_ESTUDIOS.
-- En caso de error, llama a PRC_INSERT_ERROR y retorna 0.
-- ==============================================================
CREATE OR REPLACE FUNCTION FN_PORC_ESCOLARIDAD (
    p_run_empleado   IN EMPLEADO.RUN_EMPLEADO%TYPE,
    p_cod_escolaridad IN EMPLEADO.COD_ESCOLARIDAD%TYPE
) RETURN NUMBER IS
    v_porcentaje  PCT_NIVEL_ESTUDIOS.PORC_ESCOLARIDAD%TYPE;
    v_msg_error   VARCHAR2(300);
BEGIN
    -- Busca el porcentaje de escolaridad en PCT_NIVEL_ESTUDIOS
    -- segun el codigo de escolaridad del empleado
    SELECT PORC_ESCOLARIDAD
      INTO v_porcentaje
      FROM PCT_NIVEL_ESTUDIOS
     WHERE COD_ESCOLARIDAD = p_cod_escolaridad
       AND ROWNUM = 1;

    RETURN v_porcentaje;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        -- Excepcion predefinida: no hay porcentaje para esa escolaridad
        v_msg_error := SQLERRM;
        PKG_LIQUIDACION.PRC_INSERT_ERROR(
            'FN_PORC_ESCOLARIDAD',
            v_msg_error,
            'No se encontro porcentaje de escolaridad para el empleado ' || p_run_empleado
            || ' con cod_escolaridad=' || p_cod_escolaridad
        );
        RETURN 0;
    WHEN TOO_MANY_ROWS THEN
        -- Excepcion predefinida: mas de una fila retornada (datos inconsistentes)
        v_msg_error := SQLERRM;
        PKG_LIQUIDACION.PRC_INSERT_ERROR(
            'FN_PORC_ESCOLARIDAD',
            v_msg_error,
            'Se encontraron multiples porcentajes de escolaridad para el empleado ' || p_run_empleado
            || ' con cod_escolaridad=' || p_cod_escolaridad
        );
        RETURN 0;
    WHEN OTHERS THEN
        -- Cualquier otro error Oracle al leer porcentaje
        v_msg_error := SQLERRM;
        PKG_LIQUIDACION.PRC_INSERT_ERROR(
            'FN_PORC_ESCOLARIDAD',
            v_msg_error,
            'Error inesperado al obtener porcentaje de escolaridad para empleado ' || p_run_empleado
        );
        RETURN 0;
END FN_PORC_ESCOLARIDAD;
/

-- ==============================================================
-- FUNCION FN_CUMPLE_CONDICION_ASIG_ESPECIAL
-- Determina si un vendedor cumple la condicion para recibir
-- la asignacion especial por antiguedad:
--   7% de sus ventas totales del anno procesado > promedio
--   de ventas del anno anterior (calculado por el Package).
-- Retorna 1 si cumple, 0 si no cumple.
-- ==============================================================
CREATE OR REPLACE FUNCTION FN_CUMPLE_CONDICION_ASIG_ESPECIAL (
    p_run_empleado IN EMPLEADO.RUN_EMPLEADO%TYPE,
    p_anno         IN NUMBER
) RETURN NUMBER IS
    v_ventas_vendedor NUMBER := 0;
    v_siete_pct       NUMBER := 0;
BEGIN
    -- Suma el VALOR_TOTAL de los detalles de boleta del vendedor
    -- durante el anno que se esta procesando
    SELECT NVL(SUM(db.VALOR_TOTAL), 0)
      INTO v_ventas_vendedor
      FROM DETALLE_BOLETA db
      JOIN BOLETA b ON b.NRO_BOLETA = db.NRO_BOLETA
     WHERE b.RUN_EMPLEADO = p_run_empleado
       AND EXTRACT(YEAR FROM b.FECHA) = p_anno;

    -- Calcula el 7% de las ventas totales del vendedor
    v_siete_pct := v_ventas_vendedor * 0.07;

    -- Compara con el promedio de ventas del anno anterior
    -- almacenado en la variable publica del Package
    IF v_siete_pct > PKG_LIQUIDACION.v_promedio_ventas THEN
        RETURN 1;  -- Cumple la condicion
    ELSE
        RETURN 0;  -- No cumple la condicion
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RETURN 0;
END FN_CUMPLE_CONDICION_ASIG_ESPECIAL;
/

-- ==============================================================
-- PROCEDIMIENTO PRC_CALCULAR_LIQUIDACION
-- Procedimiento principal que centraliza el calculo de las
-- asignaciones para la liquidacion mensual de todos los empleados.
-- Parametros:
--   p_mes  : mes del proceso (ej: 6)
--   p_anno : anno del proceso (ej: 2024)
-- ==============================================================
CREATE OR REPLACE PROCEDURE PRC_CALCULAR_LIQUIDACION (
    p_mes  IN NUMBER,
    p_anno IN NUMBER
) IS

    -- Cursor que recorre TODOS los empleados con sus datos necesarios
    CURSOR cur_empleados IS
        SELECT e.RUN_EMPLEADO,
               TRIM(e.NOMBRE) || ' ' || TRIM(e.paterno) || ' ' || TRIM(e.materno) AS nombre_completo,
               e.SUELDO_BASE,
               e.FECHA_CONTRATO,
               e.COD_ESCOLARIDAD,
               e.TIPO_EMPLEADO,
               e.COD_SALUD
          FROM EMPLEADO e
         ORDER BY e.RUN_EMPLEADO;

    -- Variables de trabajo para los calculos de cada empleado
    v_asig_especial   NUMBER := 0;
    v_asig_estudios   NUMBER := 0;
    v_total_haberes   NUMBER := 0;
    v_porc_ant        NUMBER := 0;
    v_porc_esc        NUMBER := 0;
    v_msg_error       VARCHAR2(300);

    -- Excepcion NO PREDEFINIDA: violacion de clave primaria (ORA-00001)
    -- Se dispara si se intenta insertar una liquidacion ya existente
    e_pk_duplicada EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_pk_duplicada, -00001);

    -- Constante: codigo de FONASA en la tabla PREVISION_SALUD
    -- (cod_salud=1 segun el insert del script de poblado)
    C_COD_FONASA CONSTANT NUMBER := 1;
    -- Constante: codigo de vendedor en TIPO_EMPLEADO
    -- (tipo_empleado=5 segun el insert del script de poblado)
    C_TIPO_VENDEDOR CONSTANT NUMBER := 5;

BEGIN

    -- ----------------------------------------------------------
    -- Trunca las tablas de resultado para permitir reejecutar
    -- el proceso las veces que sea necesario
    -- ----------------------------------------------------------
    EXECUTE IMMEDIATE 'TRUNCATE TABLE LIQUIDACION_EMPLEADO';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE ERROR_CALC';

    -- ----------------------------------------------------------
    -- Inicializa la variable publica del Package con el promedio
    -- de ventas del anno anterior al que se esta procesando.
    -- Esto hace disponible el valor a todas las funciones del proceso.
    -- ----------------------------------------------------------
    PKG_LIQUIDACION.v_promedio_ventas := PKG_LIQUIDACION.FN_PROMEDIO_VENTAS(p_anno);

    DBMS_OUTPUT.PUT_LINE('Promedio ventas anno anterior (' || (p_anno - 1) || '): $'
                         || TO_CHAR(ROUND(PKG_LIQUIDACION.v_promedio_ventas), 'FM999G999G999'));

    -- ----------------------------------------------------------
    -- Recorre cada empleado y calcula sus asignaciones
    -- ----------------------------------------------------------
    FOR reg IN cur_empleados LOOP

        -- Inicializa las asignaciones en 0 para cada empleado
        v_asig_especial := 0;
        v_asig_estudios := 0;

        -- -------------------------------------------------------
        -- ASIGNACION ESPECIAL POR ANTIGUEDAD (solo vendedores)
        -- Se aplica si:
        --   1) El empleado es vendedor (TIPO_EMPLEADO = 5)
        --   2) El 7% de sus ventas anuales > promedio anno anterior
        -- -------------------------------------------------------
        IF reg.TIPO_EMPLEADO = C_TIPO_VENDEDOR THEN
            -- Verifica la condicion de ventas usando la funcion almacenada
            IF FN_CUMPLE_CONDICION_ASIG_ESPECIAL(reg.RUN_EMPLEADO, p_anno) = 1 THEN
                -- Obtiene el porcentaje segun antiguedad usando la funcion almacenada
                v_porc_ant := FN_PORC_ANTIGUEDAD(reg.RUN_EMPLEADO, reg.FECHA_CONTRATO);
                -- Calcula la asignacion especial como % del sueldo base
                v_asig_especial := ROUND(reg.SUELDO_BASE * v_porc_ant / 100);
            END IF;
        END IF;

        -- -------------------------------------------------------
        -- ASIGNACION POR NIVEL DE ESTUDIOS (solo empleados FONASA)
        -- Se aplica si el sistema de salud del empleado es FONASA
        -- -------------------------------------------------------
        IF reg.COD_SALUD = C_COD_FONASA THEN
            -- Obtiene el porcentaje segun nivel de estudios
            v_porc_esc := FN_PORC_ESCOLARIDAD(reg.RUN_EMPLEADO, reg.COD_ESCOLARIDAD);
            -- Calcula la asignacion de estudios como % del sueldo base
            v_asig_estudios := ROUND(reg.SUELDO_BASE * v_porc_esc / 100);
        END IF;

        -- -------------------------------------------------------
        -- Calcula el total de haberes:
        -- sueldo_base + asig_especial + asig_estudios
        -- -------------------------------------------------------
        v_total_haberes := reg.SUELDO_BASE + v_asig_especial + v_asig_estudios;

        -- -------------------------------------------------------
        -- Inserta el resultado en LIQUIDACION_EMPLEADO.
        -- Controla la excepcion NO PREDEFINIDA e_pk_duplicada
        -- (ORA-00001) en caso de que el TRUNCATE no se haya
        -- ejecutado y el registro ya exista.
        -- -------------------------------------------------------
        BEGIN
            INSERT INTO LIQUIDACION_EMPLEADO (
                MES, ANNO, RUN_EMPLEADO, NOMBRE_EMPLEADO,
                SUELDO_BASE, ASIG_ESPECIAL, ASIG_ESTUDIOS, TOTAL_HABERES
            ) VALUES (
                p_mes, p_anno, reg.RUN_EMPLEADO,
                SUBSTR(reg.nombre_completo, 1, 50),
                reg.SUELDO_BASE, v_asig_especial, v_asig_estudios, v_total_haberes
            );
        EXCEPTION
            WHEN e_pk_duplicada THEN
                -- Excepcion no predefinida: registro ya existe para este periodo
                v_msg_error := SQLERRM;
                PKG_LIQUIDACION.PRC_INSERT_ERROR(
                    'PRC_CALCULAR_LIQUIDACION',
                    v_msg_error,
                    'Liquidacion duplicada para empleado ' || reg.RUN_EMPLEADO
                    || ' en periodo ' || p_mes || '/' || p_anno
                );
        END;

    END LOOP;

    -- Confirma la transaccion solo si el proceso termino correctamente
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Proceso finalizado correctamente para ' || p_mes || '/' || p_anno);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error critico en PRC_CALCULAR_LIQUIDACION: ' || SQLERRM);
END PRC_CALCULAR_LIQUIDACION;
/

-- ==============================================================
-- TRIGGER TRG_PROTEGE_PRODUCTO
-- Trigger a nivel de fila sobre la tabla PRODUCTO.
-- Reglas:
--   - De lunes a viernes (dias 2-6): impide INSERT y DELETE
--     generando errores Oracle (-20501 y -20500 resp.)
--   - SI permite UPDATE de lunes a viernes.
--   - Si el nuevo valor unitario supera el 10% del promedio
--     de todas las ventas del anno anterior, recalcula el
--     VALOR_TOTAL de todos los detalles de boleta del producto
--     (VALOR_TOTAL = CANTIDAD * nuevo VALOR_UNITARIO).
-- ==============================================================
CREATE OR REPLACE TRIGGER TRG_PROTEGE_PRODUCTO
BEFORE INSERT OR UPDATE OR DELETE ON PRODUCTO
FOR EACH ROW
DECLARE
    v_dia_semana  NUMBER;
    v_promedio    NUMBER := 0;
    v_umbral      NUMBER := 0;
    v_anno_ant    NUMBER := EXTRACT(YEAR FROM SYSDATE) - 1;
BEGIN
    -- Obtiene el dia de la semana: 1=domingo, 2=lunes, ... 6=viernes, 7=sabado
    v_dia_semana := TO_NUMBER(TO_CHAR(SYSDATE, 'D'));

    -- ----------------------------------------------------------
    -- De lunes a viernes (dias 2 a 6): bloquear INSERT y DELETE
    -- ----------------------------------------------------------
    IF v_dia_semana BETWEEN 2 AND 6 THEN

        IF INSERTING THEN
            -- Error ORA-20501: impide agregar productos en dias habiles
            RAISE_APPLICATION_ERROR(-20501,
                'TABLA DE PRODUCTO PROTEGIDA: No se pueden agregar productos de lunes a viernes.');
        END IF;

        IF DELETING THEN
            -- Error ORA-20500: impide eliminar productos en dias habiles
            RAISE_APPLICATION_ERROR(-20500,
                'TABLA DE PRODUCTO PROTEGIDA: No se pueden eliminar productos de lunes a viernes.');
        END IF;

    END IF;

    -- ----------------------------------------------------------
    -- Si es UPDATE (permitido de lunes a viernes):
    -- Verifica si el nuevo valor unitario supera el 10% del
    -- promedio de ventas del anno anterior. Si lo supera,
    -- recalcula VALOR_TOTAL de los detalles de boleta del producto.
    -- ----------------------------------------------------------
    IF UPDATING THEN

        -- Calcula el promedio de VALOR_TOTAL de los detalles de boleta
        -- del anno anterior al anno en curso
        SELECT NVL(AVG(db.VALOR_TOTAL), 0)
          INTO v_promedio
          FROM DETALLE_BOLETA db
          JOIN BOLETA b ON b.NRO_BOLETA = db.NRO_BOLETA
         WHERE EXTRACT(YEAR FROM b.FECHA) = v_anno_ant;

        -- Calcula el umbral: 10% del promedio de ventas anno anterior
        v_umbral := v_promedio * 0.10;

        -- Si el nuevo valor unitario supera el umbral, recalcula
        -- los VALOR_TOTAL de todos los detalles del producto afectado
        IF :NEW.VALOR_UNITARIO > v_umbral THEN
            UPDATE DETALLE_BOLETA
               SET VALOR_TOTAL = CANTIDAD * :NEW.VALOR_UNITARIO,
                   VUNITARIO   = :NEW.VALOR_UNITARIO
             WHERE COD_PRODUCTO = :NEW.COD_PRODUCTO;

            DBMS_OUTPUT.PUT_LINE('Trigger: recalculo VALOR_TOTAL en DETALLE_BOLETA '
                || 'para producto ' || :NEW.COD_PRODUCTO
                || '. Nuevo valor unitario: $' || :NEW.VALOR_UNITARIO
                || '. Umbral 10% promedio ventas ' || v_anno_ant || ': $' || ROUND(v_umbral));
        END IF;

    END IF;

END TRG_PROTEGE_PRODUCTO;
/

-- ==============================================================
-- EJECUCION DEL PROCESO PRINCIPAL
-- Fecha de proceso: junio 2024
-- La fecha se genera a partir de SYSDATE (mes y anno actuales
-- son los parametros que se pasan al procedimiento).
-- ==============================================================
BEGIN
    PRC_CALCULAR_LIQUIDACION(
        p_mes  => EXTRACT(MONTH FROM ADD_MONTHS(SYSDATE, 0)),  -- mes actual desde SYSDATE
        p_anno => EXTRACT(YEAR  FROM ADD_MONTHS(SYSDATE, 0))   -- anno actual desde SYSDATE
    );
END;
/

-- ==============================================================
-- CONSULTAS DE VERIFICACION
-- ==============================================================
SELECT * FROM LIQUIDACION_EMPLEADO ORDER BY RUN_EMPLEADO;
SELECT * FROM ERROR_CALC ORDER BY CORREL_ERROR;

-- ==============================================================
-- TEST DEL TRIGGER
-- ==============================================================

-- Test 1: Intentar insertar un producto (debe fallar lunes-viernes)
-- (Ejecuta este INSERT en un dia de semana para ver el error ORA-20501)
-- INSERT INTO PRODUCTO VALUES (99, 'PRODUCTO TEST', 'UN', 5000, 10, 2, 'N');

-- Test 2: Actualizar valor unitario del producto 19 a 1000 pesos
-- (No supera el umbral, no recalcula detalles)
UPDATE PRODUCTO SET VALOR_UNITARIO = 1000 WHERE COD_PRODUCTO = 19;
COMMIT;
SELECT VUNITARIO, VALOR_TOTAL, CANTIDAD FROM DETALLE_BOLETA WHERE COD_PRODUCTO = 19;

-- Test 3: Actualizar valor unitario del producto 19 a 10000 pesos
-- (Puede superar el umbral segun el promedio anno anterior, recalcula)
UPDATE PRODUCTO SET VALOR_UNITARIO = 10000 WHERE COD_PRODUCTO = 19;
COMMIT;
SELECT VUNITARIO, VALOR_TOTAL, CANTIDAD FROM DETALLE_BOLETA WHERE COD_PRODUCTO = 19;
