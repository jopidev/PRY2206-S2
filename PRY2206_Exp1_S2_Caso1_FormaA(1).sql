-- truncar tabla antes de ejecutar el bloque
TRUNCATE TABLE DETALLE_DE_CLIENTES;

-- variables bind para el periodo y mes de proceso
VARIABLE v_periodo VARCHAR2(10);
VARIABLE v_mes VARCHAR2(2);

BEGIN
    :v_periodo := TO_CHAR(SYSDATE, 'MMYYYY');
    :v_mes := TO_CHAR(SYSDATE, 'MM');
END;
/

DECLARE
    -- datos del cliente
    v_id_cli      CLIENTE.id_cli%TYPE;
    v_rut         CLIENTE.numrun_cli%TYPE;
    v_appaterno   CLIENTE.appaterno_cli%TYPE;
    v_pnombre     CLIENTE.pnombre_cli%TYPE;
    v_renta       CLIENTE.renta%TYPE;
    v_tipo        CLIENTE.id_tipo_cli%TYPE;
    v_fnac        CLIENTE.fecha_nac_cli%TYPE;
    v_comuna      COMUNA.nombre_comuna%TYPE;

    -- variables de calculo
    v_edad     NUMBER(3);
    v_puntaje  NUMBER(10) := 0;
    v_correo   DETALLE_DE_CLIENTES.CORREO_CORP%TYPE;
    v_nombre   DETALLE_DE_CLIENTES.CLIENTE%TYPE;
    v_porc     TRAMO_EDAD.PORCENTAJE%TYPE;

    -- contadores para validar que se procesaron todos
    v_cnt   NUMBER(6) := 0;
    v_total NUMBER(6) := 0;

    -- cursor que trae todos los clientes con su comuna
    -- se hace join con comuna para poder comparar el nombre en las reglas
    CURSOR c_cli IS
        SELECT cl.id_cli, cl.numrun_cli, cl.appaterno_cli, cl.apmaterno_cli,
               cl.pnombre_cli, cl.snombre_cli, cl.renta, cl.id_tipo_cli,
               cl.fecha_nac_cli,
               NVL(co.nombre_comuna, 'SIN COMUNA') nombre_comuna
        FROM CLIENTE cl
        LEFT JOIN COMUNA co ON cl.id_comuna = co.id_comuna
        ORDER BY cl.id_cli;

BEGIN
    -- obtener total de clientes para comparar al final
    SELECT COUNT(*) INTO v_total FROM CLIENTE;

    FOR r IN c_cli LOOP

        -- cargar datos del registro actual
        v_id_cli    := r.id_cli;
        v_rut       := r.numrun_cli;
        v_appaterno := r.appaterno_cli;
        v_pnombre   := r.pnombre_cli;
        v_renta     := r.renta;
        v_tipo      := r.id_tipo_cli;
        v_fnac      := r.fecha_nac_cli;
        v_comuna    := r.nombre_comuna;
        v_puntaje   := 0;

        -- calcular edad en años completos usando months_between
        v_edad := FLOOR(MONTHS_BETWEEN(SYSDATE, v_fnac) / 12);

        -- regla b: renta sobre 800k y no vive en las comunas excluidas
        IF v_renta > 800000 AND v_comuna NOT IN ('La Reina', 'Las Condes', 'Vitacura') THEN
            v_puntaje := ROUND(v_renta * 0.03);

        -- regla c: si no aplico b, revisar si es cliente VIP o Extranjero
        ELSIF v_tipo IN ('B', 'D') THEN
            v_puntaje := v_edad * 30;
        END IF;

        -- regla d: si el puntaje sigue en 0 buscar en tramo_edad segun año actual
        IF v_puntaje = 0 THEN
            BEGIN
                -- busca el porcentaje correspondiente a la edad del cliente en el año en curso
                SELECT PORCENTAJE INTO v_porc
                FROM TRAMO_EDAD
                WHERE ANNO_VIG = EXTRACT(YEAR FROM SYSDATE)
                  AND v_edad BETWEEN TRAMO_INF AND TRAMO_SUP
                  AND ROWNUM = 1;

                v_puntaje := ROUND(v_renta * (v_porc / 100));
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    v_puntaje := 0;
            END;
        END IF;

        -- armar nombre completo
        v_nombre := r.appaterno_cli || ' ' || r.apmaterno_cli || ' ' || r.pnombre_cli
                    || CASE WHEN r.snombre_cli IS NOT NULL THEN ' ' || r.snombre_cli ELSE '' END;

        -- generar correo: appaterno(min)+edad+*+1ra letra nombre+dia nac+mes proceso+dominio
        v_correo := LOWER(v_appaterno) || v_edad || '*'
                    || LOWER(SUBSTR(v_pnombre, 1, 1))
                    || TO_CHAR(v_fnac, 'DD')
                    || :v_mes
                    || '@LogiCarg.cl';

        -- insertar registro en la tabla de detalle
        INSERT INTO DETALLE_DE_CLIENTES (IDC, RUT, CLIENTE, EDAD, PUNTAJE, CORREO_CORP, PERIODO)
        VALUES (v_id_cli, v_rut, v_nombre, v_edad, v_puntaje, v_correo, :v_periodo);

        v_cnt := v_cnt + 1;

    END LOOP;

    -- verificar que se procesaron todos los clientes antes de confirmar
    IF v_cnt = v_total THEN
        COMMIT;
        DBMS_OUTPUT.PUT_LINE('Proceso finalizado correctamente. Clientes procesados: ' || v_cnt);
    ELSE
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Proceso finalizado con errores. Se deshacen las transacciones.');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/
