DROP DATABASE IF EXISTS inmobiliaria;
CREATE DATABASE inmobiliaria CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE inmobiliaria;

-- 1. TABLAS CATALOGO

CREATE TABLE tipo_propiedad (
    id_tipo_propiedad INT AUTO_INCREMENT PRIMARY KEY,
    nombre_tipo       VARCHAR(30) NOT NULL UNIQUE,
    porcentaje_comision DECIMAL(5,2) NOT NULL CHECK (porcentaje_comision >= 0 AND porcentaje_comision <= 100)
) ENGINE=InnoDB;

CREATE TABLE estado_propiedad (
    id_estado    INT AUTO_INCREMENT PRIMARY KEY,
    nombre_estado VARCHAR(30) NOT NULL UNIQUE
) ENGINE=InnoDB;

-- 2. ENTIDADES PRINCIPALES

CREATE TABLE propietario (
    id_propietario INT AUTO_INCREMENT PRIMARY KEY,
    nombre     VARCHAR(100) NOT NULL,
    documento  VARCHAR(20)  NOT NULL UNIQUE,
    telefono   VARCHAR(20),
    correo     VARCHAR(100),
    direccion  VARCHAR(150)
) ENGINE=InnoDB;

CREATE TABLE cliente (
    id_cliente INT AUTO_INCREMENT PRIMARY KEY,
    nombre     VARCHAR(100) NOT NULL,
    documento  VARCHAR(20)  NOT NULL UNIQUE,
    telefono   VARCHAR(20),
    correo     VARCHAR(100),
    direccion  VARCHAR(150)
) ENGINE=InnoDB;

CREATE TABLE agente (
    id_agente   INT AUTO_INCREMENT PRIMARY KEY,
    nombre      VARCHAR(100) NOT NULL,
    documento   VARCHAR(20)  NOT NULL UNIQUE,
    telefono    VARCHAR(20),
    correo      VARCHAR(100),
    fecha_contratacion DATE NOT NULL,
    usuario_mysql VARCHAR(50) UNIQUE COMMENT 'Login MySQL asociado a este agente'
) ENGINE=InnoDB;

CREATE TABLE propiedad (
    id_propiedad   INT AUTO_INCREMENT PRIMARY KEY,
    direccion      VARCHAR(150) NOT NULL,
    area           DECIMAL(8,2) NOT NULL,
    precio         DECIMAL(14,2) NOT NULL COMMENT 'Precio de venta o canon mensual segun modalidad',
    modalidad      ENUM('venta','arriendo') NOT NULL,
    id_tipo_propiedad INT NOT NULL,
    id_estado      INT NOT NULL,
    id_propietario INT NOT NULL,
    fecha_registro DATE NOT NULL DEFAULT (CURRENT_DATE),
    CONSTRAINT fk_propiedad_tipo FOREIGN KEY (id_tipo_propiedad) REFERENCES tipo_propiedad(id_tipo_propiedad),
    CONSTRAINT fk_propiedad_estado FOREIGN KEY (id_estado) REFERENCES estado_propiedad(id_estado),
    CONSTRAINT fk_propiedad_propietario FOREIGN KEY (id_propietario) REFERENCES propietario(id_propietario)
) ENGINE=InnoDB;

CREATE TABLE contrato (
    id_contrato   INT AUTO_INCREMENT PRIMARY KEY,
    id_propiedad  INT NOT NULL,
    id_cliente    INT NOT NULL,
    id_agente     INT NOT NULL,
    tipo_contrato ENUM('venta','arriendo') NOT NULL,
    fecha_inicio  DATE NOT NULL,
    fecha_fin     DATE NULL COMMENT 'NULL en venta; obligatoria logicamente en arriendo',
    valor         DECIMAL(14,2) NOT NULL COMMENT 'Valor de venta o canon mensual',
    deposito      DECIMAL(14,2) NULL COMMENT 'Solo aplica a arriendo',
    dia_pago      TINYINT NULL COMMENT 'Dia del mes de pago, solo arriendo',
    estado_contrato ENUM('activo','finalizado','cancelado') NOT NULL DEFAULT 'activo',
    CONSTRAINT fk_contrato_propiedad FOREIGN KEY (id_propiedad) REFERENCES propiedad(id_propiedad),
    CONSTRAINT fk_contrato_cliente FOREIGN KEY (id_cliente) REFERENCES cliente(id_cliente),
    CONSTRAINT fk_contrato_agente FOREIGN KEY (id_agente) REFERENCES agente(id_agente)
) ENGINE=InnoDB;

CREATE TABLE pago (
    id_pago       INT AUTO_INCREMENT PRIMARY KEY,
    id_contrato   INT NOT NULL,
    fecha_esperada DATE NOT NULL,
    fecha_pago    DATE NULL,
    monto         DECIMAL(14,2) NOT NULL,
    mora          DECIMAL(14,2) NOT NULL DEFAULT 0,
    metodo_pago   VARCHAR(30) NULL,
    estado_pago   ENUM('pendiente','pagado','atrasado') NOT NULL DEFAULT 'pendiente',
    CONSTRAINT fk_pago_contrato FOREIGN KEY (id_contrato) REFERENCES contrato(id_contrato)
) ENGINE=InnoDB;

-- 3. TABLAS DE AUDITORIA

CREATE TABLE auditoria_propiedad (
    id_auditoria   INT AUTO_INCREMENT PRIMARY KEY,
    id_propiedad   INT NOT NULL,
    estado_anterior VARCHAR(30),
    estado_nuevo    VARCHAR(30),
    fecha_cambio    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_mysql   VARCHAR(100),
    CONSTRAINT fk_auditoria_propiedad FOREIGN KEY (id_propiedad) REFERENCES propiedad(id_propiedad)
) ENGINE=InnoDB;

CREATE TABLE auditoria_contrato (
    id_auditoria  INT AUTO_INCREMENT PRIMARY KEY,
    id_contrato   INT NOT NULL,
    accion        VARCHAR(30) NOT NULL DEFAULT 'creacion',
    fecha_registro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    usuario_mysql VARCHAR(100),
    detalle       VARCHAR(255),
    CONSTRAINT fk_auditoria_contrato FOREIGN KEY (id_contrato) REFERENCES contrato(id_contrato)
) ENGINE=InnoDB;

-- 4. TABLA DE REPORTES (poblada por el evento programado)

CREATE TABLE reporte_pagos_pendientes (
    id_reporte      INT AUTO_INCREMENT PRIMARY KEY,
    fecha_generacion DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_contrato     INT NOT NULL,
    id_cliente      INT NOT NULL,
    id_propiedad    INT NOT NULL,
    monto_pendiente DECIMAL(14,2) NOT NULL,
    CONSTRAINT fk_reporte_contrato FOREIGN KEY (id_contrato) REFERENCES contrato(id_contrato)
) ENGINE=InnoDB;

-- 5. INDICES DE OPTIMIZACION

CREATE INDEX idx_propiedad_estado_tipo ON propiedad(id_estado, id_tipo_propiedad);
CREATE INDEX idx_propiedad_modalidad ON propiedad(modalidad);
CREATE INDEX idx_contrato_tipo_estado ON contrato(tipo_contrato, estado_contrato);
CREATE INDEX idx_pago_contrato_estado ON pago(id_contrato, estado_pago);
CREATE INDEX idx_pago_fecha_esperada ON pago(fecha_esperada);


SELECT id_contrato, SUM(monto+mora) AS deuda
FROM pago
WHERE estado_pago <> 'pagado' AND fecha_esperada <= CURDATE()
GROUP BY id_contrato;

-- 6. FUNCIONES PERSONALIZADAS (UDFs)

DELIMITER $$

-- 6.1 Comision de un agente sobre un contrato (venta o arriendo)
-- Supuesto validado con el cliente: se calcula sobre contrato.valor
-- (precio de venta o canon mensual), usando el % del tipo de propiedad.
CREATE FUNCTION fn_calcular_comision(p_id_contrato INT)
RETURNS DECIMAL(14,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_comision DECIMAL(14,2);

    SELECT c.valor * (tp.porcentaje_comision / 100)
    INTO v_comision
    FROM contrato c
    JOIN propiedad p ON p.id_propiedad = c.id_propiedad
    JOIN tipo_propiedad tp ON tp.id_tipo_propiedad = p.id_tipo_propiedad
    WHERE c.id_contrato = p_id_contrato;

    RETURN IFNULL(v_comision, 0);
END$$

-- 6.2 Deuda pendiente de un contrato de arriendo
-- Formula acordada: suma de (monto + mora) de pagos cuya fecha
-- esperada ya paso y que no estan marcados como 'pagado'.
CREATE FUNCTION fn_calcular_deuda_arriendo(p_id_contrato INT)
RETURNS DECIMAL(14,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_deuda DECIMAL(14,2);
    DECLARE v_tipo ENUM('venta','arriendo');

    SELECT tipo_contrato INTO v_tipo
    FROM contrato WHERE id_contrato = p_id_contrato;

    IF v_tipo IS NULL OR v_tipo <> 'arriendo' THEN
        RETURN 0;
    END IF;

    SELECT IFNULL(SUM(monto + mora), 0)
    INTO v_deuda
    FROM pago
    WHERE id_contrato = p_id_contrato
      AND estado_pago <> 'pagado'
      AND fecha_esperada <= CURDATE();

    RETURN v_deuda;
END$$

-- 6.3 Total de propiedades disponibles por tipo
CREATE FUNCTION fn_total_disponibles_por_tipo(p_nombre_tipo VARCHAR(30))
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total INT;

    SELECT COUNT(*)
    INTO v_total
    FROM propiedad p
    JOIN tipo_propiedad tp ON tp.id_tipo_propiedad = p.id_tipo_propiedad
    JOIN estado_propiedad ep ON ep.id_estado = p.id_estado
    WHERE tp.nombre_tipo = p_nombre_tipo
      AND ep.nombre_estado = 'disponible';

    RETURN IFNULL(v_total, 0);
END$$

DELIMITER ;

-- 7. TRIGGERS

DELIMITER $$

-- 7.1 Auditoria de cambio de estado de una propiedad
CREATE TRIGGER trg_propiedad_after_update
AFTER UPDATE ON propiedad
FOR EACH ROW
BEGIN
    IF OLD.id_estado <> NEW.id_estado THEN
        INSERT INTO auditoria_propiedad (id_propiedad, estado_anterior, estado_nuevo, usuario_mysql)
        VALUES (
            NEW.id_propiedad,
            (SELECT nombre_estado FROM estado_propiedad WHERE id_estado = OLD.id_estado),
            (SELECT nombre_estado FROM estado_propiedad WHERE id_estado = NEW.id_estado),
            CURRENT_USER()
        );
    END IF;
END$$

-- 7.2 Auditoria de registro de un nuevo contrato
CREATE TRIGGER trg_contrato_after_insert_auditoria
AFTER INSERT ON contrato
FOR EACH ROW
BEGIN
    INSERT INTO auditoria_contrato (id_contrato, accion, usuario_mysql, detalle)
    VALUES (
        NEW.id_contrato,
        'creacion',
        CURRENT_USER(),
        CONCAT('Contrato tipo ', NEW.tipo_contrato, ' por valor ', NEW.valor)
    );
END$$

-- 7.3 Actualizacion automatica del estado de la propiedad al firmar contrato
-- (agregado por consistencia del sistema; dispara ademas el trigger 7.1)
CREATE TRIGGER trg_contrato_after_insert_estado
AFTER INSERT ON contrato
FOR EACH ROW
BEGIN
    UPDATE propiedad
    SET id_estado = (
        SELECT id_estado FROM estado_propiedad
        WHERE nombre_estado = IF(NEW.tipo_contrato = 'venta', 'vendida', 'arrendada')
    )
    WHERE id_propiedad = NEW.id_propiedad;
END$$

DELIMITER ;

-- 8. SEGURIDAD: ROLES Y PRIVILEGIOS

CREATE ROLE IF NOT EXISTS 'rol_admin', 'rol_agente', 'rol_contador';

-- Administrador: control total sobre la base de datos
GRANT ALL PRIVILEGES ON inmobiliaria.* TO 'rol_admin';

-- Agente: gestiona clientes, propiedades y contratos; solo lectura de catalogos y propietarios; SIN acceso a pagos ni reportes financieros
GRANT SELECT, INSERT, UPDATE ON inmobiliaria.cliente TO 'rol_agente';
GRANT SELECT, INSERT, UPDATE ON inmobiliaria.propiedad TO 'rol_agente';
GRANT SELECT, INSERT, UPDATE ON inmobiliaria.contrato TO 'rol_agente';
GRANT SELECT ON inmobiliaria.propietario TO 'rol_agente';
GRANT SELECT ON inmobiliaria.tipo_propiedad TO 'rol_agente';
GRANT SELECT ON inmobiliaria.estado_propiedad TO 'rol_agente';
GRANT EXECUTE ON FUNCTION inmobiliaria.fn_calcular_comision TO 'rol_agente';
GRANT EXECUTE ON FUNCTION inmobiliaria.fn_total_disponibles_por_tipo TO 'rol_agente';

-- Contador: lectura de contratos/propiedades; gestion de pagos y reportes; SIN acceso a gestion de propiedades/clientes
GRANT SELECT ON inmobiliaria.contrato TO 'rol_contador';
GRANT SELECT ON inmobiliaria.propiedad TO 'rol_contador';
GRANT SELECT ON inmobiliaria.cliente TO 'rol_contador';
GRANT SELECT, INSERT, UPDATE ON inmobiliaria.pago TO 'rol_contador';
GRANT SELECT ON inmobiliaria.reporte_pagos_pendientes TO 'rol_contador';
GRANT EXECUTE ON FUNCTION inmobiliaria.fn_calcular_deuda_arriendo TO 'rol_contador';

-- Creacion de usuarios de ejemplo (cambiar contraseñas en un entorno real)
CREATE USER IF NOT EXISTS 'admin_ricardo'@'localhost' IDENTIFIED BY 'adminUser#01';
CREATE USER IF NOT EXISTS 'agente_juanp'@'localhost' IDENTIFIED BY 'agenteUser#01';
CREATE USER IF NOT EXISTS 'contador_maria'@'localhost' IDENTIFIED BY 'contadorUser#01';

GRANT 'rol_admin' TO 'admin_ricardo'@'localhost';
GRANT 'rol_agente' TO 'agente_juanp'@'localhost';
GRANT 'rol_contador' TO 'contador_maria'@'localhost';

SET DEFAULT ROLE 'rol_admin' TO 'admin_ricardo'@'localhost';
SET DEFAULT ROLE 'rol_agente' TO 'agente_juanp'@'localhost';
SET DEFAULT ROLE 'rol_contador' TO 'contador_maria'@'localhost';

-- 9. EVENTO PROGRAMADO MENSUAL

SET GLOBAL event_scheduler = ON;

DELIMITER $$

CREATE EVENT IF NOT EXISTS evento_reporte_mensual
ON SCHEDULE EVERY 1 MONTH
STARTS (DATE_ADD(CURRENT_DATE, INTERVAL 1 MONTH))
DO
BEGIN
    INSERT INTO reporte_pagos_pendientes (id_contrato, id_cliente, id_propiedad, monto_pendiente)
    SELECT
        c.id_contrato,
        c.id_cliente,
        c.id_propiedad,
        fn_calcular_deuda_arriendo(c.id_contrato) AS deuda
    FROM contrato c
    WHERE c.tipo_contrato = 'arriendo'
      AND c.estado_contrato = 'activo'
      AND fn_calcular_deuda_arriendo(c.id_contrato) > 0;
END$$

DELIMITER ;

-- 10. DATOS DE PRUEBA

INSERT INTO tipo_propiedad (nombre_tipo, porcentaje_comision) VALUES
('casa', 3.00),
('apartamento', 3.50),
('local_comercial', 5.00);

INSERT INTO estado_propiedad (nombre_estado) VALUES
('disponible'), ('reservada'), ('arrendada'), ('vendida'), ('en_mantenimiento');

INSERT INTO propietario (nombre, documento, telefono, correo, direccion) VALUES
('Luis Fernando Rojas', '1098765432', '3001112233', 'luis.rojas@correo.com', 'Cra 10 # 20-30, Bucaramanga'),
('Marta Elena Diaz', '1087654321', '3004445566', 'marta.diaz@correo.com', 'Calle 15 # 8-40, Floridablanca');

INSERT INTO cliente (nombre, documento, telefono, correo, direccion) VALUES
('Andrea Gomez', '1122334455', '3007778899', 'andrea.gomez@correo.com', 'Cra 27 # 45-12, Bucaramanga'),
('Carlos Mendoza', '1099887766', '3009990011', 'carlos.mendoza@correo.com', 'Calle 33 # 10-05, Giron');

INSERT INTO agente (nombre, documento, telefono, correo, fecha_contratacion, usuario_mysql) VALUES
('Juan Pablo Sierra', '1010101010', '3011234567', 'juanp.sierra@inmobiliaria.com', '2023-02-01', 'agente_juanp'),
('Diana Torres', '1020202020', '3012345678', 'diana.torres@inmobiliaria.com', '2022-06-15', NULL);

-- El contador tambien puede modelarse como registro de referencia (opcional):
-- se mantiene fuera del alcance de "agente" ya que no vende ni arrienda.

INSERT INTO propiedad (direccion, area, precio, modalidad, id_tipo_propiedad, id_estado, id_propietario) VALUES
('Cra 10 # 20-30 Apto 501, Bucaramanga', 85.50, 320000000.00, 'venta', 2, 1, 1),
('Calle 15 # 8-40 Casa, Floridablanca', 150.00, 1800000.00, 'arriendo', 1, 1, 2),
('Local 3, Centro Comercial Cabecera, Bucaramanga', 45.00, 2500000.00, 'arriendo', 3, 1, 1);

-- Contrato de venta (dispara triggers: auditoria_contrato + cambio de estado a 'vendida')
INSERT INTO contrato (id_propiedad, id_cliente, id_agente, tipo_contrato, fecha_inicio, fecha_fin, valor, deposito, dia_pago) VALUES
(1, 1, 1, 'venta', '2026-08-01', NULL, 320000000.00, NULL, NULL);

INSERT INTO pago (id_contrato, fecha_esperada, fecha_pago, monto, mora, metodo_pago, estado_pago) VALUES
(1, '2026-08-01', '2026-08-01', 320000000.00, 0, 'transferencia', 'pagado');

-- Contrato de arriendo (dispara triggers: auditoria_contrato + cambio de estado a 'arrendada')
INSERT INTO contrato (id_propiedad, id_cliente, id_agente, tipo_contrato, fecha_inicio, fecha_fin, valor, deposito, dia_pago) VALUES
(2, 2, 2, 'arriendo', '2026-06-05', '2027-06-05', 1800000.00, 1800000.00, 5);

-- Pagos de arriendo: uno pagado, dos pendientes/atrasados para probar la UDF de deuda
INSERT INTO pago (id_contrato, fecha_esperada, fecha_pago, monto, mora, metodo_pago, estado_pago) VALUES
(2, '2026-06-05', '2026-06-05', 1800000.00, 0, 'transferencia', 'pagado'),
(2, '2026-07-05', NULL, 1800000.00, 50000, NULL, 'atrasado'),
(2, '2026-08-05', NULL, 1800000.00, 0, NULL, 'pendiente');

-- 11. CONSULTAS DE VERIFICACION (ejemplo de uso)

SELECT fn_calcular_comision(1);              -- comision venta apto (3.5%)
SELECT fn_calcular_comision(2);               -- comision arriendo casa (3%)
SELECT fn_calcular_deuda_arriendo(2);          -- deuda pendiente contrato arriendo
SELECT fn_total_disponibles_por_tipo('local_comercial');
SELECT * FROM auditoria_propiedad;
SELECT * FROM auditoria_contrato;











-- --------------------------- Pruebas de confirmación ----------------------------------

-- Correr por bloques (no todo de una vez) para poder leer cada resultado


USE inmobiliaria;

SHOW TABLES;

-- Debe listar las 11 tablas: agente, auditoria_contrato, auditoria_propiedad,
-- cliente, contrato, estado_propiedad, pago, propiedad, propietario,
-- reporte_pagos_pendientes, tipo_propiedad

SELECT TABLE_NAME, COLUMN_NAME, CONSTRAINT_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
FROM information_schema.KEY_COLUMN_USAGE
WHERE TABLE_SCHEMA = 'inmobiliaria' AND REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY TABLE_NAME;

-- Debe mostrar cada FK apuntando a la tabla/columna correcta
-- (contrato -> propiedad/cliente/agente, pago -> contrato, etc.)

-- Prueba de integridad referencial: esto DEBE FALLAR (error 1452)
-- porque el id_cliente 999 no existe
INSERT INTO contrato (id_propiedad, id_cliente, id_agente, tipo_contrato, fecha_inicio, valor)
VALUES (1, 999, 1, 'venta', CURDATE(), 100000);

-- BLOQUE 2: Datos de prueba cargados

SELECT * FROM propiedad;
SELECT * FROM contrato;
SELECT * FROM pago;

-- BLOQUE 3: Funciones (UDFs)

-- 3.1 Comision (venta apto 3.5% sobre 320,000,000 = 11,200,000)
SELECT fn_calcular_comision(1) AS comision_venta_esperada_11200000;

-- 3.2 Comision (arriendo casa 3% sobre 1,800,000 = 54,000)
SELECT fn_calcular_comision(2) AS comision_arriendo_esperada_54000;

-- 3.3 Deuda pendiente (contrato 2 arriendo: cuota atrasada 1.8M+50K mora
--     + cuota pendiente 1.8M = 3,650,000, si ya paso su fecha_esperada)
SELECT fn_calcular_deuda_arriendo(2) AS deuda_esperada_3650000;

-- 3.4 Total disponibles por tipo
SELECT fn_total_disponibles_por_tipo('casa') AS casas_disponibles;
SELECT fn_total_disponibles_por_tipo('apartamento') AS aptos_disponibles;
SELECT fn_total_disponibles_por_tipo('local_comercial') AS locales_disponibles;

-- BLOQUE 4: Triggers

-- 4.1 Ver que los triggers existen
SHOW TRIGGERS FROM inmobiliaria;

-- 4.2 Probar trigger de cambio de estado + auditoria de propiedad:
--     forzamos un cambio manual de estado y verificamos que quede auditado
UPDATE propiedad SET id_estado = 5 WHERE id_propiedad = 3; -- 5 = en_mantenimiento
SELECT * FROM auditoria_propiedad WHERE id_propiedad = 3;
-- Debe aparecer una fila: estado_anterior='disponible', estado_nuevo='en_mantenimiento'

-- Revertir para no dejar datos de prueba sucios
UPDATE propiedad SET id_estado = 1 WHERE id_propiedad = 3; -- vuelve a disponible

-- 4.3 Probar trigger de nuevo contrato (auditoria + cambio de estado propiedad)
-- Usamos la propiedad 3 (local comercial, disponible) y la dejamos en arriendo
INSERT INTO contrato (id_propiedad, id_cliente, id_agente, tipo_contrato, fecha_inicio, fecha_fin, valor, deposito, dia_pago)
VALUES (3, 1, 2, 'arriendo', CURDATE(), DATE_ADD(CURDATE(), INTERVAL 12 MONTH), 2500000, 2500000, 10);

SELECT * FROM auditoria_contrato ORDER BY id_auditoria DESC LIMIT 1;
-- Debe mostrar 'creacion' para el contrato recien insertado

SELECT ep.nombre_estado FROM propiedad p
JOIN estado_propiedad ep ON ep.id_estado = p.id_estado
WHERE p.id_propiedad = 3;
-- Debe mostrar 'arrendada' (el trigger cambio el estado automaticamente)

SELECT * FROM auditoria_propiedad WHERE id_propiedad = 3 ORDER BY id_auditoria DESC LIMIT 1;
-- Debe mostrar el cambio disponible -> arrendada, generado por el mismo INSERT


-- BLOQUE 5: Roles y privilegios

SELECT user, host FROM mysql.user WHERE user IN ('rol_admin','rol_agente','rol_contador');
SHOW GRANTS FOR 'rol_admin';
SHOW GRANTS FOR 'rol_agente';
SHOW GRANTS FOR 'rol_contador';

SELECT user, host FROM mysql.user WHERE user IN ('admin_ricardo','agente_juanp','contador_maria');
SHOW GRANTS FOR 'agente_juanp'@'localhost';
SHOW GRANTS FOR 'contador_maria'@'localhost';

-- Prueba real de restriccion: conectate con el usuario agente y confirma
-- que SI puede leer/escribir propiedad pero NO puede tocar pago:
--   mysql -u agente_juanp -p inmobiliaria
--   SELECT * FROM pago;      -- debe dar ERROR 1142 (access denied)
--   SELECT * FROM propiedad; -- debe funcionar

-- Prueba real con el contador:
--   mysql -u contador_maria -p inmobiliaria
--   UPDATE propiedad SET precio = 999 WHERE id_propiedad = 1; -- debe fallar
--   SELECT * FROM pago;                                       -- debe funcionar

-- BLOQUE 6: Evento programado

SHOW VARIABLES LIKE 'event_scheduler';
-- Debe decir ON. Si dice OFF: SET GLOBAL event_scheduler = ON;

SELECT event_name, status, interval_value, interval_field, starts, last_executed
FROM information_schema.events
WHERE event_schema = 'inmobiliaria';
-- status debe ser ENABLED

-- Para no esperar un mes completo, puedes simular su ejecucion manualmente:
INSERT INTO reporte_pagos_pendientes (id_contrato, id_cliente, id_propiedad, monto_pendiente)
SELECT c.id_contrato, c.id_cliente, c.id_propiedad, fn_calcular_deuda_arriendo(c.id_contrato)
FROM contrato c
WHERE c.tipo_contrato = 'arriendo'
  AND c.estado_contrato = 'activo'
  AND fn_calcular_deuda_arriendo(c.id_contrato) > 0;

SELECT * FROM reporte_pagos_pendientes;
-- Debe listar el contrato 2 con monto_pendiente = 3650000

-- Alternativa para probar el evento real sin esperar un mes: cambia
-- temporalmente su intervalo (solo en ambiente de pruebas, no en produccion):
--   ALTER EVENT evento_reporte_mensual ON SCHEDULE EVERY 1 MINUTE;
--   -- esperar 60-90 segundos y revisar reporte_pagos_pendientes
--   ALTER EVENT evento_reporte_mensual ON SCHEDULE EVERY 1 MONTH;


-- BLOQUE 7: Indices / optimizacion

SHOW INDEX FROM propiedad;
SHOW INDEX FROM pago;
SHOW INDEX FROM contrato;

EXPLAIN SELECT id_contrato, SUM(monto+mora) AS deuda
FROM pago
WHERE estado_pago <> 'pagado' AND fecha_esperada <= CURDATE()
GROUP BY id_contrato;
-- En la columna "key" debe aparecer idx_pago_fecha_esperada o
-- idx_pago_contrato_estado (NO debe decir NULL con type=ALL,
-- eso indicaria un full table scan sin usar indice)

EXPLAIN SELECT * FROM propiedad WHERE id_estado = 1 AND id_tipo_propiedad = 2;
-- key debe ser idx_propiedad_estado_tipo

