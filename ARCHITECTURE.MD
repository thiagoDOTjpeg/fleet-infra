# 🏗️ Arquitetura do Sistema - Plataforma Logística

Este documento detalha as decisões de arquitetura, stack tecnológico e estratégias de dados adotadas para o desenvolvimento da plataforma de entregas.

## 1. Contexto do Sistema (C4 Model - Nível 1)

Visão macro das interações entre os usuários, a plataforma e sistemas externos.

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#fff', 'edgeLabelBackground':'#ffffff', 'tertiaryColor': 'transparent', 'background': 'transparent', 'lineColor': '#000'}}}%%
graph TD
    classDef person fill:#08427b,stroke:#052e56,color:#fff,rx:10,ry:10;
    classDef system fill:#1168bd,stroke:#0b4884,color:#fff,rx:10,ry:10;
    classDef external fill:#999999,stroke:#6b6b6b,color:#fff,rx:10,ry:10;

    User[("Cliente / Entregador")]:::person
    Admin[("Administrador")]:::person

    System[("Plataforma de Logística")]:::system

    Maps[("Open Street Map")]:::external

    User -->|"Usa o App para pedidos/entregas"| System
    Admin -->|"Gerencia operações"| System

    System -->|"Geocodificação e Rotas"| Maps
```

## 2. Arquitetura Técnica (C4 Model - Nível 2)

O sistema segue uma arquitetura de Microsserviços orientada a eventos.
O fluxo de dados prioriza:

### Segurança no edge (API Gateway)

### Performance na escrita de geolocalização (Write-Behind)

```mermaid
%%{init: {'theme': 'base', 'themeVariables': { 'primaryColor': '#fff', 'edgeLabelBackground':'#ffffff', 'tertiaryColor': 'transparent', 'background': 'transparent', 'lineColor': '#ffffff'}}}%%
graph TD
    %% --- Definição de Estilos (Classes) ---
    classDef frontend fill:#e1bee7,stroke:#4a148c,stroke-width:2px,color:#000,rx:10,ry:10;
    classDef gateway fill:#37474f,stroke:#000,stroke-width:2px,color:#fff,shape:hexagon;
    classDef javaSvc fill:#bbdefb,stroke:#0d47a1,stroke-width:2px,color:#000;
    classDef nodeSvc fill:#c8e6c9,stroke:#1b5e20,stroke-width:2px,color:#000;
    classDef phpSvc fill:#ffe0b2,stroke:#e65100,stroke-width:2px,color:#000;
    classDef database fill:#cfd8dc,stroke:#455a64,stroke-width:2px,color:#000,shape:cylinder;
    classDef queue fill:#fff9c4,stroke:#fbc02d,stroke-width:2px,color:#000,stroke-dasharray: 5 5;

    %% --- Estrutura do Diagrama ---
    subgraph Clients ["📱 Frontends (SPA Angular)"]
        direction LR
        MobileApp("App (Cliente/Entregador)")
        AdminWeb("Backoffice Web (Admin)")
    end

    subgraph Edge ["🛡️ Edge Layer"]
        Nginx{{"API Gateway (Nginx)"}}
    end

    subgraph Services ["⚙️ Backend Microservices"]
    subgraph Data ["💾 Persistence & Messaging"]
        Redis[("Redis (Cache & Buffer)")]
        RabbitMQ[["RabbitMQ (Events)"]]
        DB_Core[("DB_Orders (Postgres)")]
        DB_Geo[("DB_Tracking (PostGIS)")]
    end
        AuthSvc["Auth Service (Java)"]
        CoreSvc["Core/Order Service (Java)"]
        TrackSvc["Tracking Service (NodeJS)"]
        AdminSvc["Backoffice Service (PHP)"]
    end

    %% --- Conexões ---
    MobileApp -->|"HTTPS/JSON (REST)"| Nginx
    AdminWeb -->|"HTTPS/JSON (REST)"| Nginx

    Nginx -->|"HTTP/1.1 (auth_request)"| AuthSvc
    Nginx -->|"HTTP/1.1 (REST)"| CoreSvc
    Nginx -->|"HTTP/1.1 (REST)"| TrackSvc
    Nginx -->|"HTTP/1.1 (REST)"| AdminSvc

    CoreSvc -->|"TCP/5432 (SQL)"| DB_Core
    AdminSvc -->|"TCP/5432 (SQL)"| DB_Core

    %% Fluxos Assíncronos
    AuthSvc -.->|"RESP Protocol"| Redis
    linkStyle 8 stroke:#1565c0,stroke-width:2px,stroke-dasharray: 5 5;

    CoreSvc -.->|"AMQP 0-9-1 (Pub)"| RabbitMQ
    linkStyle 9 stroke:#f57f17,stroke-width:2px,stroke-dasharray: 5 5;

    RabbitMQ -.->|"AMQP 0-9-1 (Sub)"| TrackSvc
    linkStyle 10 stroke:#f57f17,stroke-width:2px,stroke-dasharray: 5 5;

    TrackSvc -.->|"RESP Protocol (GEOADD)"| Redis
    linkStyle 11 stroke:#2e7d32,stroke-width:2px,stroke-dasharray: 5 5;

    TrackSvc --->|"TCP/5432 (Batch Insert)"| DB_Geo

    class MobileApp,AdminWeb frontend;
    class Nginx gateway;
    class AuthSvc,CoreSvc javaSvc;
    class TrackSvc nodeSvc;
    class AdminSvc phpSvc;
    class DB_Core,DB_Geo,Redis database;
    class RabbitMQ queue;

    CoreSvc ~~~ DB_Core
```

## 3. Stack Tecnológico

A escolha segue Polyglot Programming, usando a melhor ferramenta para cada responsabilidade.

### Componentes, Tecnologias e Responsabilidades

| Componente       | Tecnologia              | Responsabilidade                                  |
| :--------------- | :---------------------- | :------------------------------------------------ |
| API Gateway      | Nginx                   | Roteamento, SSL, Rate Limiting                    |
| Auth Service     | Java (Spring Boot)      | Autenticação e JWT                                |
| Core Service     | Java (Spring Boot)      | Pedidos e pagamentos                              |
| Tracking Service | Node.js (NestJS)        | Telemetria e geo-cálculos                         |
| Backoffice       | PHP                     | Administração e relatórios                        |
| Bancos           | PostgreSQL + PostGIS    | Dados relacionais e espaciais                     |
| Cache/Buffer     | Redis                   | Cache, geolocalização em tempo real, write-behind |
| Mensageria       | RabbitMQ                | Comunicação assíncrona (AMQP 0-9-1)               |
| Observabilidade  | Prometheus + Grafana    | Métricas, dashboards e alertas                    |
| Logs             | Loki + Promtail         | Agregação centralizada de logs                    |
| Tracing          | OpenTelemetry           | Distributed tracing entre serviços                |
| CI/CD            | GitHub Actions + Docker | Build, testes e deploy automatizado               |
| Registry         | Docker Hub + Watchtower | Distribuição de imagens e auto-update             |

## 4. Decisões Estratégicas (Key Design Decisions)

### 4.1. Autenticação Centralizada (Gateway Offloading)

**Decisão:** O Nginx (ou API Gateway) valida o token JWT via sub-request (`auth_request`) antes de encaminhar para os microsserviços.

**Benefício:** Os serviços internos (`fleet-orders`, `fleet-tracking`) não precisam implementar lógica de validação de token, focando apenas no domínio. Permite revogação centralizada e simplifica a gestão de dependências de segurança.

### 4.2. Telemetria em Alta Frequência (Write-Behind Pattern)

**Problema:** Milhares de coordenadas de entregadores chegando a cada 3 segundos gerariam gargalo de I/O se fossem inseridas linha a linha no banco.

**Solução:**

- **Entrada:** O serviço de Tracking grava no Redis (Geo Set/Lists) para latência sub-milissegundo.
- **Buffer:** O Redis atua como um buffer temporário de alta velocidade.
- **Persistência:** Um Cron Job (Worker) coleta esses dados e faz Batch Inserts no PostGIS a cada 60 segundos.

### 4.3. Consistência Eventual e Confiabilidade (Transactional Outbox)

**Problema:** O risco de "Dual Write" (salvar no banco e falhar ao enviar para o RabbitMQ).

**Solução:** Implementação do **Transactional Outbox Pattern** no `fleet-auth`. O evento é salvo na mesma transação do banco de dados e um polling publisher garante o envio para o RabbitMQ, assegurando que nenhuma mensagem de negócio seja perdida em caso de falha de rede.

## 5. Modelagem de Dados

### db_fleet_tracking

> Modelagem voltada para rastreamento de entregadores, eventos e zonas de atuação. Utiliza PostGIS para dados espaciais e integrações com o serviço de pedidos via UUID.

```mermaid
erDiagram
    DRIVERS ||--|{ DRIVER_LOCATIONS : "tracks location"
    DRIVERS ||--|{ DRIVER_AVAILABILITY_ZONES : "operates in"
    DRIVERS ||--o{ ORDER_TRACKING_EVENTS : "generates events"

    DRIVERS {
        uuid id PK
        varchar name
        varchar phone
        varchar cnh
        varchar vehicle_plate
        boolean is_online
        boolean is_available
        uuid current_order_id "Referência ao pedido atual (integração externa)"
        geography location "Localização atual (PostGIS POINT)"
        timestamp last_location_update "Última atualização de localização"
        int total_deliveries "Total de entregas realizadas"
        decimal rating "Média de avaliações"
    }

    DRIVER_LOCATIONS {
        uuid id PK
        uuid driver_id FK "Referência ao entregador"
        uuid order_id "Referência ao pedido (integração externa)"
        decimal latitude
        decimal longitude
        geography location "Posição registrada (PostGIS POINT)"
        decimal speed "Velocidade no momento"
        timestamp recorded_at "Data/hora do registro"
    }

    DRIVER_AVAILABILITY_ZONES {
        uuid id PK
        uuid driver_id FK "Referência ao entregador"
        varchar zone_name "Nome da zona de atuação"
        geography zone_polygon "Área de atuação (PostGIS POLYGON)"
        boolean active "Zona ativa"
    }

    ORDER_TRACKING_EVENTS {
        uuid id PK
        uuid order_id "Referência ao pedido (integração externa)"
        uuid driver_id FK "Referência ao entregador"
        varchar event_type "Ex: 'pickup', 'delivered'"
        decimal latitude
        decimal longitude
        geography location "Localização do evento"
        jsonb metadata "Informações adicionais do evento"
        timestamp created_at "Data/hora do evento"
    }
```

### db_fleet_orders

> Modelagem voltada para pedidos, clientes, lojas e histórico de status. Integração com rastreamento via UUID, snapshots para auditoria e campos explicativos.

#### auth_schema

```mermaid
erDiagram
    USERS ||--o{ REFRESH_TOKENS : has
    USERS ||--o{ USER_ROLES : assigned
    ROLES ||--o{ USER_ROLES : contains

    USERS {
        uuid id PK
        varchar name
        varchar email
        varchar password
        varchar user_type
        boolean enabled
        boolean account_non_expired
        boolean account_non_locked
        boolean credentials_non_expired
        timestamp created_at
        timestamp updated_at
    }

    ROLES {
        uuid id PK
        varchar name
        timestamp created_at
    }

    USER_ROLES {
        uuid user_id PK
        uuid role_id PK
        timestamp assigned_at
    }

    REFRESH_TOKENS {
        uuid id PK
        varchar token_hash
        uuid user_id FK
        uuid parent_id
        uuid session_id
        timestamp expires_at
        boolean revoked
        boolean used
        timestamp created_at
        timestamp updated_at
        bigint version
    }
```

---

#### orders_schema

```mermaid
erDiagram
    SHOPS ||--o{ ITEMS : sells
    SHOPS ||--o{ ORDERS : "receives from"
    CLIENTS ||--o{ ORDERS : places
    CLIENTS ||--o{ PAYMENT_METHODS : "has methods"
    ORDERS ||--o{ ORDER_ITEMS : contains
    ITEMS ||--o{ ORDER_ITEMS : "included in"
    ORDERS ||--o{ ORDER_STATUS_HISTORY : "status changes"

    PRICING_CONFIG {
        uuid id PK
        varchar region
        decimal base_fee
        decimal price_per_km
        decimal surge_multiplier
    }

    SHOPS {
        uuid id PK
        uuid owner_user_id "ID do usuário (auth.users)"
        varchar name
        varchar address
        decimal latitude
        decimal longitude
        geography location
        boolean active
    }

    CLIENTS {
        uuid id PK
        uuid user_id "ID do usuário (auth.users)"
        varchar cpf
        uuid default_payment_method_id
        boolean active
    }

    ITEMS {
        uuid id PK
        uuid shop_id FK
        varchar name
        decimal price
        boolean active
    }

    ORDERS {
        uuid id PK
        uuid client_id FK
        uuid shop_id FK
        uuid driver_user_id "Usuário externo (auth.users)"
        varchar pickup_address
        decimal pickup_latitude
        decimal pickup_longitude
        varchar delivery_address
        decimal delivery_latitude
        decimal delivery_longitude
        geography pickup_location
        geography delivery_location
        decimal distance_km
        decimal total
        varchar status
        varchar driver_name
        varchar driver_phone
    }

    PAYMENT_METHODS {
        uuid id PK
        uuid client_id FK
        varchar type
        varchar card_last4
        boolean is_default
    }

    ORDER_ITEMS {
        uuid id PK
        uuid order_id FK
        uuid item_id FK
        int quantity
        decimal price_at_moment
    }

    ORDER_STATUS_HISTORY {
        uuid id PK
        uuid order_id FK
        varchar from_status
        varchar to_status
        uuid changed_by_user_id "auth.users (referência lógica)"
        timestamp changed_at
    }

```

## 6. ADR – Registros de Decisões Arquiteturais

### ADR 001: Processamento da Localização do Entregador

**Decisão:** Utilizar processamento em lote (Batch Work) com Redis e PostGIS.

**Justificativa:** O volume de escrita de GPS é alto demais para o banco relacional suportar em tempo real (OLTP). O processamento em lote reduz a carga de I/O no disco e evita locks desnecessários na tabela de histórico.

### ADR 002: Mensageria (RabbitMQ vs Kafka)

**Decisão:** Adotar RabbitMQ.

**Justificativa:** Para o estágio atual e volumetria do `fleet-auth` e notificações, o RabbitMQ oferece menor complexidade operacional, suporte nativo a prioridade e roteamento flexível (exchanges), além de garantir confirmação granular de entrega (ACKs). O Kafka seria overkill e adicionaria complexidade acidental neste momento.

### ADR 003: Separação de Bancos de Dados

**Decisão:** Utilizar bases de dados fisicamente separadas para Domínios distintos (`db_fleet_auth`, `db_fleet_orders`, `db_fleet_tracking`).

**Justificativa:**

- **Isolamento de Falhas:** Um pico de carga no rastreamento não derruba o login dos usuários.
- **Segurança:** Dados sensíveis (senhas) ficam inacessíveis ao serviço de pedidos.
- **Escalabilidade:** Permite escalar o hardware do banco de geolocalização (PostGIS) independentemente do banco relacional padrão.

**Consistência e Integridade Referencial:**

A separação física dos bancos remove as Foreign Keys entre domínios (ex: Pedidos → Usuários). A integridade referencial é garantida logicamente via aplicação através do padrão **Saga Choreography**: eventos de domínio (`UserDeleted`, `OrderCancelled`) são propagados via RabbitMQ, e cada serviço executa ações de compensação quando necessário (soft-delete, anonimização de dados órfãos).

### ADR 004: Garantia de Entrega (Idempotência)

**Decisão:** Consumidores devem ser Idempotentes.

**Justificativa:** Devido ao uso do Outbox Pattern e à natureza de redes distribuídas ("at-least-once delivery"), mensagens podem chegar duplicadas. Os serviços consumidores utilizam tabelas de controle ou chaves de negócio únicas para descartar duplicatas silenciosamente.

## 7. Trade-offs (Limitações Aceitas)

- **Consistência Eventual no Histórico:** O trajeto do entregador pode levar até 60 segundos para aparecer no histórico permanente (PostGIS), embora a posição atual (Redis) seja em tempo real.

- **Dependência Crítica do Redis:** Se o Redis falhar e não houver persistência em disco (AOF/RDB) configurada, pode haver perda de até 1 minuto de dados de telemetria (buffer).

- **Complexidade de Observabilidade:** Com a separação em microsserviços e bancos distintos, o rastreamento de erros exige ferramentas de Distributed Tracing (OpenTelemetry/Micrometer) para correlacionar logs entre Java, Node.js e banco de dados.

- **Integridade Referencial:** A separação dos bancos remove as Foreign Keys entre Pedidos e Usuários, exigindo que a consistência seja garantida via aplicação (eventos de compensação).

---

## 8. Mitigação de Riscos e Roadmap de Evolução

Esta seção documenta as estratégias de mitigação para os trade-offs aceitos e o caminho evolutivo para ambientes de maior criticidade.

### 8.1. Eliminação de Perda de Dados de Telemetria (Zero-Loss)

**Risco Atual:** Perda de até 60 segundos de coordenadas GPS em caso de falha do Redis.

**Mitigação Planejada:** Para ambientes de missão crítica (como aviação ou logística de alto valor), a arquitetura prevê evolução para um padrão de **Redundância de Escrita Dual-Path**:

```mermaid
graph LR
    TrackSvc["Tracking Service"] -->|"1. Hot Path (sync)"| Redis[("Redis")]
    TrackSvc -->|"2. Durable Path (async)"| Kafka[("Kafka/RabbitMQ Durable")]
    Kafka -->|"Consumer"| PostGIS[("PostGIS")]
    Redis -->|"Batch Job"| PostGIS
```

- **Hot Path:** Escrita síncrona no Redis para leitura em tempo real (latência < 1ms).
- **Durable Path:** Escrita assíncrona em fila durável (Kafka com `acks=all` ou RabbitMQ com `persistent=true`).
- **Resultado:** Mesmo com falha total do Redis, nenhum dado de telemetria é perdido, mantendo a latência de leitura inalterada.

### 8.2. Alta Disponibilidade do Redis

**Mitigação Atual:**

- Redis configurado com AOF (Append-Only File) para persistência.
- Snapshots RDB a cada 5 minutos.

**Evolução Planejada:**

- Deploy em modo **Redis Sentinel** (3 nós) para failover automático.
- Migração futura para **Redis Cluster** em caso de crescimento horizontal.

### 8.3. Observabilidade Distribuída

**Status Atual:**

- Logs estruturados (JSON) com correlation ID propagado via headers HTTP.
- Métricas expostas via Micrometer (Spring Boot) e prom-client (Node.js).

**Evolução Planejada:**

- Implementação completa de **OpenTelemetry Collector** para traces distribuídos.
- Dashboards Grafana com SLOs (Service Level Objectives) e alertas automáticos.
- Integração com PagerDuty/Opsgenie para on-call rotation.

### 8.4. Resiliência de Mensageria

**Mitigação Atual:**

- RabbitMQ com filas duráveis e `publisher confirms`.
- Transactional Outbox Pattern no Auth Service.

**Evolução Planejada:**

- Dead Letter Queues (DLQ) com retry exponencial e alertas.
- Circuit Breaker (Resilience4j) para chamadas síncronas entre serviços.
- Fallback graceful em caso de indisponibilidade de serviços downstream.
