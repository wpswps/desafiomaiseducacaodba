-- Tabela tenant
-- Vamos definir id como a chave primária e adicionar uma restrição de exclusividade no nome para garantir unicidade dos tenants.

CREATE TABLE tenant (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description VARCHAR(255)
);


-- Tabela person
-- A tabela person contém informações sobre indivíduos e é independente do tenant. Para melhorar o desempenho de consultas JSONB, definiremos um índice específico.

CREATE TABLE person (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    birth_date DATE,
    metadata JSONB
);

-- Índice para busca pelo nome das pessoas
CREATE INDEX idx_person_name ON person (name);

-- Índice para busca por data de nascimento, caso existam consultas por idade ou data de nascimento
CREATE INDEX idx_person_birth_date ON person (birth_date);

-- Índice para consultas em campos específicos do JSONB metadata
CREATE INDEX idx_person_metadata_gin ON person USING gin (metadata jsonb_path_ops);



-- Tabela institution
-- A tabela institution contém informações sobre as instituições e está associada a um tenant. Vamos adicionar uma chave estrangeira para tenant_id, garantindo integridade referencial, e criar um índice na coluna JSONB para melhorar as consultas.

CREATE TABLE institution (
    id SERIAL PRIMARY KEY,
    tenant_id INTEGER NOT NULL,
    name VARCHAR(100) NOT NULL,
    location VARCHAR(100),
    details JSONB,
    FOREIGN KEY (tenant_id) REFERENCES tenant(id) ON DELETE CASCADE
);

--- Índice para busca por tenant_id e nome da instituição
CREATE INDEX idx_institution_tenant_id ON institution (tenant_id);

-- Índice composto para busca por tenant_id e nome da instituição
CREATE INDEX idx_institution_tenant_name ON institution (tenant_id, name);

-- Índice para consultas em campos específicos do JSONB details
CREATE INDEX idx_institution_details_gin ON institution USING gin (details jsonb_path_ops);


-- Chave estrangeira: tenant_id: Assegura que cada institution esteja vinculada a um tenant válido. A restrição ON DELETE CASCADE garante que, ao remover um tenant, suas instituições sejam automaticamente excluídas.


-- Tabela course
-- A tabela course contém cursos oferecidos por uma instituição e é associada a um tenant. A inclusão de chaves estrangeiras para tenant_id e institution_id garante a integridade referencial.

CREATE TABLE course (
    id SERIAL PRIMARY KEY,
    tenant_id INTEGER NOT NULL,
    institution_id INTEGER NOT NULL,
    name VARCHAR(100) NOT NULL,
    duration INTEGER,
    details JSONB,
    FOREIGN KEY (tenant_id) REFERENCES tenant(id) ON DELETE CASCADE,
    FOREIGN KEY (institution_id) REFERENCES institution(id) ON DELETE CASCADE
);

-- Índice para consultas por tenant_id
CREATE INDEX idx_course_tenant_id ON course (tenant_id);

-- Índice composto para busca por tenant_id e institution_id
CREATE INDEX idx_course_tenant_institution ON course (tenant_id, institution_id);

-- Índice para consultas por nome do curso
CREATE INDEX idx_course_name ON course (name);

-- Índice para consultas em campos específicos do JSONB details
CREATE INDEX idx_course_details_gin ON course USING gin (details jsonb_path_ops);

--Temos duas Chaves estrangeira: 
-- tenant_id: Vincula cada curso a um tenant válido. A restrição ON DELETE CASCADE garante que, ao excluir um tenant, seus cursos sejam removidos.
-- institution_id: Assegura que o curso esteja associado a uma instituição válida. A exclusão em cascata (ON DELETE CASCADE) remove cursos caso a instituição associada seja excluída.


-- Tabela enrollment
-- A tabela enrollment contém informações de matrículas, associadas a um tenant, institution, e person. Vamos definir uma chave estrangeira para cada uma dessas associações e criar um índice para otimizar consultas com grande volume de dados.

CREATE TABLE enrollment (
    id SERIAL PRIMARY KEY,
    tenant_id INTEGER NOT NULL,
    institution_id INTEGER,
    person_id INTEGER NOT NULL,
    course_id INTEGER NOT NULL,
    enrollment_date DATE,
    status VARCHAR(20),
    FOREIGN KEY (tenant_id) REFERENCES tenant(id) ON DELETE CASCADE,
    FOREIGN KEY (institution_id) REFERENCES institution(id) ON DELETE SET NULL,
    FOREIGN KEY (person_id) REFERENCES person(id) ON DELETE CASCADE,
    FOREIGN KEY (course_id) REFERENCES course(id) ON DELETE CASCADE
);


CREATE UNIQUE INDEX idx_unique_enrollment ON enrollment (tenant_id, person_id, institution_id);

-- Índice composto para consultas multi-tenant
CREATE INDEX idx_enrollment_tenant_institution ON enrollment (tenant_id, institution_id);

-- Índice composto para filtros de busca multi-tenant e por pessoa
CREATE INDEX idx_enrollment_tenant_person ON enrollment (tenant_id, person_id);

-- Índice para consultas por course_id
CREATE INDEX idx_enrollment_course_id ON enrollment (course_id);

-- Índice para consultas por status de matrícula
CREATE INDEX idx_enrollment_status ON enrollment (status);

-- Índice composto para tenant_id, institution_id e course_id
CREATE INDEX idx_enrollment_tenant_institution_course ON enrollment (tenant_id, institution_id, course_id);


--Temos quatro Chaves estrangeira:
-- tenant_id: Vincula a matrícula a um tenant válido. Com ON DELETE CASCADE, remove a matrícula ao excluir o tenant.
-- institution_id: Relaciona a matrícula a uma institution, que pode ser nula. Com ON DELETE SET NULL, institution_id será ajustado para NULL caso a instituição seja removida.
-- person_id: Garante que cada matrícula se relacione a uma pessoa existente. A exclusão em cascata (ON DELETE CASCADE) garante que, ao excluir uma pessoa, suas matrículas sejam removidas.
-- course_id: Assegura que a matrícula está associada a um curso válido. Com ON DELETE CASCADE, o registro de matrícula será excluído caso o curso seja removido.

ALTER TABLE enrollment
ADD COLUMN is_deleted BOOLEAN DEFAULT FALSE;

CREATE UNIQUE INDEX idx_unique_active_enrollment 
ON enrollment (tenant_id, person_id, institution_id)
WHERE is_deleted = FALSE;

-----------------------------------------------------------------------

SELECT 
    e.course_id,
    COUNT(*) AS enrollment_count
FROM 
    enrollment e
JOIN 
    person p ON e.person_id = p.id
WHERE 
    e.tenant_id = <tenant_id>
    AND e.institution_id = <institution_id>
    AND e.is_deleted = FALSE
    AND p.metadata::text @@ plainto_tsquery('<termo_de_busca>')
GROUP BY 
    e.course_id;


CREATE INDEX idx_person_metadata_fulltext 
ON person 
USING gin (to_tsvector('english', metadata::text));

--------------------------------------------------------------------------


SELECT 
    p.id AS person_id,
    p.name AS person_name,
    p.metadata,
    e.enrollment_date,
    e.status
FROM 
    enrollment e
JOIN 
    person p ON e.person_id = p.id
WHERE 
    e.tenant_id = <tenant_id>
    AND e.institution_id = <institution_id>
    AND e.course_id = <course_id>
    AND e.is_deleted = FALSE
ORDER BY 
    p.name
LIMIT <page_size> OFFSET <offset_value>;

---------------------------------------------------------------------------------------------


---------Redefinição da Tabela enrollment com Particionamento-----------------

CREATE TABLE enrollment (
    id SERIAL PRIMARY KEY,
    tenant_id INTEGER NOT NULL,
    institution_id INTEGER,
    course_id INTEGER NOT NULL,
    person_id INTEGER NOT NULL,
    enrollment_date DATE NOT NULL,
    status VARCHAR(20),
    is_deleted BOOLEAN DEFAULT FALSE,
    CONSTRAINT fk_tenant FOREIGN KEY (tenant_id) REFERENCES tenant(id),
    CONSTRAINT fk_institution FOREIGN KEY (institution_id) REFERENCES institution(id),
    CONSTRAINT fk_course FOREIGN KEY (course_id) REFERENCES course(id),
    CONSTRAINT fk_person FOREIGN KEY (person_id) REFERENCES person(id),
    UNIQUE (tenant_id, institution_id, person_id, course_id)
) PARTITION BY LIST (tenant_id);


-------Criação das Partições------------

CREATE TABLE enrollment_tenant_1 PARTITION OF enrollment FOR VALUES IN (1);
CREATE TABLE enrollment_tenant_2 PARTITION OF enrollment FOR VALUES IN (2);

--------- Índices nas Partições-----------

CREATE INDEX idx_enrollment_institution_id_tenant_1 ON enrollment_tenant_1 (institution_id);
CREATE INDEX idx_enrollment_course_id_tenant_1 ON enrollment_tenant_1 (course_id);
CREATE INDEX idx_enrollment_person_id_tenant_1 ON enrollment_tenant_1 (person_id);



------Essa estrutura particionada aumenta a eficiência do banco de dados em cenários multi-tenant e melhora o tempo de resposta para consultas que envolvem grandes volumes de dados, comuns em cursos EAD.


---------------Uso de JSONB de Forma Eficiente----------------
/*Como a tabela person possui uma coluna metadata em formato JSONB, considere a criação de índices GIN 
(Generalized Inverted Index) sobre essa coluna, caso você faça muitas buscas neste campo:*/

CREATE INDEX idx_person_metadata ON person USING GIN (metadata);

----Isso acelera as consultas que filtram informações contidas em metadata, especialmente se você fizer buscas por campos específicos do JSONB.
