# PRY2206 - Experiencia 2, Semana 5

Programación de Bases de Datos - Manejando excepciones para controlar errores en un bloque PL/SQL anónimo complejo.

## Descripción

Bloque PL/SQL anónimo que calcula las asignaciones mensuales (movilización extra, tipo de contrato y profesión) de los profesionales de Dolphin Consulting, a partir de las asesorías realizadas en un mes/año determinado (parametrizado vía variable BIND).

## Contenido

- `PRY2206_Exp2_S5_Caso1.sql`: bloque PL/SQL completo (cursores con y sin parámetro, VARRAY, registro, excepciones predefinidas/no predefinidas/definidas por el usuario) + consultas de verificación.

## Ejecución

1. `PRY2206_Exp2_S5_Crea_usuario.sql` (crea el usuario).
2. `PRY2206_Exp2_S5_Crea_pobla_tablas.sql` (crea y puebla las tablas).
3. `PRY2206_Exp2_S5_Caso1.sql` (proceso, conectado con ese usuario).
