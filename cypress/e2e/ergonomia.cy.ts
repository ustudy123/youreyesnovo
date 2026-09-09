/// <reference types="cypress" />

// =====================================================================
// Gestão de Risco Ergonômico (/ergonomia) — testes de tela (nível e2e).
//
// Cada it() corresponde a um caso documentado (ERGO-*), ligado pela ponte
// qa_cobertura_e2e. Escopo: a entrada do módulo — as 7 abas do fluxo GRO
// montam, o Guia Rápido abre e fecha, e a trava de risco sem título segura
// o cadastro. NADA aqui cria risco, então não depende de dado semeado.
// =====================================================================

import { credenciaisDeTeste } from "../support/credenciais";

describe("Gestão de Risco Ergonômico (/ergonomia)", () => {
  const { email, senha: password } = credenciaisDeTeste();
  const baseUrl = Cypress.config("baseUrl") as string;

  function login() {
    cy.visit(`${baseUrl}/login`);
    cy.get('input[type="email"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(email);
    cy.get('input[autocomplete="current-password"]', { timeout: 20000 })
      .should("exist").scrollIntoView().should("be.visible").clear().type(password, { log: false });
    cy.contains("button", /^Entrar$/).click();
    cy.aguardarSessaoSupabase();
    cy.wait(1500);
  }

  beforeEach(() => {
    login();
    cy.visit(`${baseUrl}/ergonomia`);
    cy.contains("h1", "Gestão de Risco Ergonômico", { timeout: 20000 }).should("be.visible");
  });

  // ERGO-001
  it("abre com as 7 abas do fluxo GRO", () => {
    [
      "Avaliar Riscos (AEP)",
      "Inventário GRO",
      "Riscos Prioritários",
      "Plano de Ação",
      "Monitoramento",
      "Análise por IA",
      "Base Ergonômica",
    ].forEach((t) => cy.contains('[role="tab"]', t).should("exist"));
  });

  // ERGO-002
  it("abre e fecha o Guia Rápido sem afetar a tela", () => {
    cy.get("#btn-ergo-guia-rapido").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Guia Rápido — Ergonomia");
    cy.get("body").type("{esc}");
    cy.get('[role="dialog"]').should("not.exist");
    cy.contains("h1", "Gestão de Risco Ergonômico").should("be.visible");
  });

  // ERGO-011
  it("bloqueia o cadastro de risco sem título", () => {
    cy.get("#btn-ergo-novo-risco").click({ force: true });
    cy.get('[role="dialog"]', { timeout: 20000 })
      .should("be.visible")
      .and("contain.text", "Cadastrar Risco Ergonômico");
    cy.contains("button", "Cadastrar Risco").should("be.disabled");
  });
});
