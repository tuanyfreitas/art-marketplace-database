# Art Marketplace — Database Architecture

### Projeto de Banco de Dados | PostgreSQL

## Sobre o projeto

O **Art Marketplace** é um projeto de portfólio que apresenta a arquitetura e a modelagem de um banco de dados relacional para uma plataforma de comercialização de obras de arte.

O objetivo é demonstrar conhecimentos em administração de bancos de dados, modelagem relacional, integridade de dados, automação de regras de negócio e organização de estruturas SQL.

O projeto contempla o gerenciamento de artistas, clientes, obras, pedidos, pagamentos, repasses financeiros e operações relacionadas ao marketplace.

## Tecnologias utilizadas

- **PostgreSQL** — Banco de dados relacional
- **SQL e PL/pgSQL** — Estruturas, consultas, funções e triggers
- **Flyway** — Versionamento e controle de migrações
- **Git e GitHub** — Versionamento e documentação do projeto

## Principais funcionalidades modeladas

**Gestão de usuários e artistas**
- Cadastro de usuários e endereços
- Gerenciamento de artistas e seus status
- Controle de perfis e permissões

**Catálogo de obras de arte**
- Cadastro de obras, categorias e imagens
- Controle de estoque e reservas
- Histórico de preços e curadoria

**Pedidos e pagamentos**
- Carrinho de compras
- Registro de pedidos e seus itens
- Histórico de status
- Pagamentos e operações PIX
- Divisão financeira entre artistas e marketplace
- Registro de notas fiscais e reembolsos

**Integridade, segurança e auditoria**
- Chaves primárias e estrangeiras
- Constraints e validações
- Índices para otimização de consultas
- Triggers e funções PL/pgSQL
- Registros de auditoria e históricos de alterações

## Arquitetura e modelagem

O banco utiliza modelagem relacional, com relacionamentos entre entidades, regras de integridade referencial e mecanismos de validação.

As regras de negócio são implementadas também na camada de banco de dados, buscando preservar a consistência das informações durante as operações do marketplace.

## Organização do repositório

Os scripts SQL estão organizados em migrações versionadas com Flyway.

```text
art-marketplace-database/
├── README.md
├── migrations/
│   └── Scripts SQL versionados
└── docs/
    └── Documentação e diagramas
```

## Status do projeto

**Em desenvolvimento e validação técnica.**

A estrutura SQL e as regras de negócio estão sendo revisadas. Os testes finais de integração e execução das migrações ainda estão pendentes.

Este repositório tem finalidade educacional e de demonstração técnica, não sendo apresentado como sistema pronto para produção.

## Objetivo profissional

Demonstrar competências aplicáveis às áreas de:

- Administração de Banco de Dados (DBA)
- Engenharia de Dados
- Modelagem e Arquitetura de Dados
- Desenvolvimento SQL e PL/pgSQL
- Integridade e Governança de Dados

---

**Projeto de portfólio técnico desenvolvido para demonstrar conhecimentos em bancos de dados relacionais e arquitetura de dados.**
