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
    MobileApp -->|"HTTPS / JSON"| Nginx
    AdminWeb -->|"HTTPS / JSON"| Nginx

    Nginx -->|"1. Validate Token"| AuthSvc
    Nginx -->|"2. Proxy Request"| CoreSvc
    Nginx -->|"2. Proxy Request"| TrackSvc
    Nginx -->|"2. Proxy Request"| AdminSvc

    CoreSvc -->|"CRUD"| DB_Core
    AdminSvc -->|"Read/Write"| DB_Core

    %% Fluxos Assíncronos
    AuthSvc -.->|"Session Data"| Redis
    linkStyle 8 stroke:#1565c0,stroke-width:2px,stroke-dasharray: 5 5;

    CoreSvc -.->|"Pub: OrderCreated"| RabbitMQ
    linkStyle 9 stroke:#f57f17,stroke-width:2px,stroke-dasharray: 5 5;

    RabbitMQ -.->|"Sub: CreateTracking"| TrackSvc
    linkStyle 10 stroke:#f57f17,stroke-width:2px,stroke-dasharray: 5 5;

    TrackSvc -.->|"1. Hot Write (Geo)"| Redis
    linkStyle 11 stroke:#2e7d32,stroke-width:2px,stroke-dasharray: 5 5;

    TrackSvc --->|"2. Batch Write (Cron)"| DB_Geo

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

| Componente       | Tecnologia           | Responsabilidade                                  |
| :--------------- | :------------------- | :------------------------------------------------ |
| API Gateway      | Nginx                | Roteamento, SSL, Rate Limiting                    |
| Auth Service     | Java (Spring Boot)   | Autenticação e JWT                                |
| Core Service     | Java (Spring Boot)   | Pedidos e pagamentos                              |
| Tracking Service | Node.js (NestJS)     | Telemetria e geo-cálculos                         |
| Backoffice       | PHP                  | Administração e relatórios                        |
| Bancos           | PostgreSQL + PostGIS | Dados relacionais e espaciais                     |
| Cache/Buffer     | Redis                | Cache, geolocalização em tempo real, write-behind |
| Mensageria       | RabbitMQ             | Comunicação assíncrona                            |

## 4. Decisões Estratégicas (Key Design Decisions)

### 4.1. Autenticação no Gateway (Token Introspection)

O Nginx valida o token via auth_request.

Servicios internos não precisam validar JWT.

Permite revogação centralizada e menor complexidade.

### 4.2. Telemetria em Alta Frequência (Node.js + PostGIS)

Problema: milhares de coordenadas chegando a cada 3s → Não fazer INSERT direto.

Solução: Write-Behind Pattern

Entrada: Tracking grava no Redis (Geo Set) → latência sub-ms.

Buffer: Redis armazena coordenadas em lista.

Persistência: Cron job faz batch inserts no PostGIS a cada 60s.

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

## 6. ADR – Registros de Decisões

### Redis – Processamento da Localização do Entregador

**Decisão:** Utilizar processamento em lote (Batch Work).

**Justificativa:** O processamento em lote permite agrupar e salvar dados periodicamente, reduzindo a carga sobre o banco de dados e otimizando a performance do sistema.

### RabbitMQ vs Kafka

**Decisão:** Adotar RabbitMQ.

**Justificativa:** RabbitMQ foi escolhido devido ao suporte para roteamento complexo, confirmação granular de mensagens (ACK), além de apresentar menor complexidade operacional em comparação ao Kafka.

### Separação de Bancos

**Decisão:** Utilizar bancos separados para pedidos (`db_fleet_order`) e rastreamento (`db_fleet_tracking`).

**Justificativa:** A separação lógica permite escalar o armazenamento e processamento de geodados de forma independente, sem impactar o banco principal de pedidos, garantindo maior flexibilidade e performance para cada tipo de dado.

## 7. Trade-offs

Consistência eventual de até 60s no histórico.

Dependência forte do Redis (possível perda de 1min de buffer)

Observabilidade distribuída necessária (Java + Node + PHP).
