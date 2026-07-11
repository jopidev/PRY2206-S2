# PRY2206 - Programación de Bases de Datos

## Experiencia 2 - Semana 5

Manejando excepciones para controlar errores en un bloque PL/SQL anónimo complejo.

### Descripción

Bloque PL/SQL anónimo que calcula las asignaciones mensuales (movilización extra, tipo de contrato y profesión) de los profesionales de Dolphin Consulting, a partir de las asesorías realizadas en un mes/año determinado (parametrizado vía variable BIND).

### Contenido

- `PRY2206_Exp2_S5_Caso1.sql`: bloque PL/SQL completo (cursores con y sin parámetro, VARRAY, registro, excepciones predefinidas/no predefinidas/definidas por el usuario) + consultas de verificación.

### Ejecución

1. `PRY2206_Exp2_S5_Crea_usuario.sql` (crea el usuario).
2. `PRY2206_Exp2_S5_Crea_pobla_tablas.sql` (crea y puebla las tablas).
3. `PRY2206_Exp2_S5_Caso1.sql` (proceso, conectado con ese usuario).

---

## Experiencia 3 - Semana 8

Desarrollando un programa PL/SQL con Package, funciones almacenadas, procedimiento y trigger.

### Descripción

Programa PL/SQL que calcula las liquidaciones mensuales de empleados de SPA Products, incluyendo asignación especial por antigüedad (solo vendedores que cumplen condición de ventas) y asignación por nivel de estudios (solo empleados FONASA).

### Contenido

- `PRY2206_Exp3_S8_Caso1.sql`: Package PKG_LIQUIDACION, funciones FN_PORC_ANTIGUEDAD / FN_PORC_ESCOLARIDAD / FN_CUMPLE_CONDICION_ASIG_ESPECIAL, procedimiento PRC_CALCULAR_LIQUIDACION y trigger TRG_PROTEGE_PRODUCTO.

### Ejecución

1. `PRY2206_Exp3_S8_Crea_usuario.sql` (crea el usuario).
2. `PRY2206_Exp3_S8_Crea_pobla_tablas.SQL` (crea y puebla las tablas).
3. `PRY2206_Exp3_S8_Caso1.sql` (proceso, conectado con ese usuario).
