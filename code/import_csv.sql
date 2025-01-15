-- ***CADA UNO DE LOS PASOS SE TIENEN QUE EJECUTAR INDIVIDUALMENTE***

-- Paso 1. Creación de Directorio para Oracle
-- Creamos un directorio para que Oracle busque el archivo y damos permisos al usuario con que vamos a conectarnos y crear la tabla en su esquema
-- En este directorio podremos dejar los archivos .CSV que necesitamos

CREATE OR REPLACE DIRECTORY csv_dir AS '/directorio/ejemplo/creado';
GRANT READ, WRITE ON DIRECTORY csv_dir TO tu_usuario;

-- Paso 2. Comprobamos que Oracle es capaz de leer el archivo
-- Bloque de código PL SQL para comprobar que conectados al usuario podemos acceder al directorio y leer el archivo
DECLARE
    file_handle UTL_FILE.FILE_TYPE;
BEGIN
    file_handle := UTL_FILE.FOPEN('CSV_DIR', 'datos.csv', 'R');
    DBMS_OUTPUT.PUT_LINE('Archivo leído correctamente.');
    UTL_FILE.FCLOSE(file_handle);
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error al leer el archivo: ' || SQLERRM);
END;
/

-- Paso 3. Script para leer los archivos del CSV y crear una tabla en base a estos
DECLARE
    file_handle UTL_FILE.FILE_TYPE;
    line VARCHAR2(4000);
    column_names VARCHAR2(4000);
    column_values VARCHAR2(4000);
    table_name VARCHAR2(100) := 'dynamic_table'; -- Nombre de la tabla
    column_definitions VARCHAR2(4000);
    col_name VARCHAR2(100);
    col_value VARCHAR2(4000);
    col_count PLS_INTEGER := 0;
    col_type VARCHAR2(50);
    is_first_line BOOLEAN := TRUE;
BEGIN
    -- Abrir el archivo
    file_handle := UTL_FILE.FOPEN('CSV_DIR', 'datos.csv', 'R');
    
    -- Leer la cabecera (primer línea) para obtener los nombres de las columnas
    UTL_FILE.GET_LINE(file_handle, line);
    column_names := line;
    
    -- Procesar los nombres de las columnas
    FOR i IN 1..REGEXP_COUNT(column_names, '[^,]+') LOOP
        col_name := REGEXP_SUBSTR(column_names, '[^,]+', 1, i);
        col_name := TRIM(col_name); -- Eliminar espacios en blanco
        col_count := col_count + 1;
        
        -- Inferir tipo de datos a partir de la segunda línea
        IF is_first_line THEN
            UTL_FILE.GET_LINE(file_handle, line); -- Leer segunda línea
            column_values := line;
            is_first_line := FALSE;
        END IF;

        col_value := REGEXP_SUBSTR(column_values, '[^,]+', 1, i);
        
        -- Inferir tipo de datos
        BEGIN
            col_type := CASE 
                            WHEN col_value IS NULL THEN 'VARCHAR2(4000)'
                            WHEN LENGTH(TRIM(col_value)) = LENGTH(TO_NUMBER(col_value)) THEN 'NUMBER'
                            ELSE 'VARCHAR2(4000)'
                        END;
        EXCEPTION
            WHEN OTHERS THEN
                col_type := 'VARCHAR2(4000)';
        END;

        -- Construir definición de columna
        column_definitions := column_definitions || col_name || ' ' || col_type || ', ';
    END LOOP;

    -- Crear la tabla dinámica
    EXECUTE IMMEDIATE 'CREATE TABLE ' || table_name || ' (' || RTRIM(column_definitions, ', ') || ')';
    
    -- Volver a abrir el archivo para insertar los datos (desde la segunda línea)
    UTL_FILE.FCLOSE(file_handle);
    file_handle := UTL_FILE.FOPEN('CSV_DIR', 'datos.csv', 'R');
    
    -- Ignorar la cabecera
    UTL_FILE.GET_LINE(file_handle, line);
    
    -- Insertar los datos
    LOOP
        BEGIN
            UTL_FILE.GET_LINE(file_handle, line);

            -- Construir e insertar los valores
            EXECUTE IMMEDIATE 'INSERT INTO ' || table_name || ' VALUES (' ||
                REGEXP_REPLACE(line, '([^,]+)', '''\1''') || ')';
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                EXIT;
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('Error en línea: ' || line);
        END;
    END LOOP;

    -- Cerrar el archivo
    UTL_FILE.FCLOSE(file_handle);
    COMMIT;

    DBMS_OUTPUT.PUT_LINE('Tabla creada e insertada: ' || table_name);

EXCEPTION
    WHEN OTHERS THEN
        IF UTL_FILE.IS_OPEN(file_handle) THEN
            UTL_FILE.FCLOSE(file_handle);
        END IF;
        RAISE;
END;
/