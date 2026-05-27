---
name: amydgala
description: Describe what this skill does and when to use it. Include keywords that help agents identify relevant tasks.
---

<!-- Tip: Use /create-skill in chat to generate content with agent assistance -->

# Decentralised Persistent Memory for AI Agents — System Design

> **Project:** Decentralised, persistent, selective memory for AI agents on SUI blockchain.
> **Core idea:** Memory is a tool the agent calls, not a monolith passed into context. The agent retrieves only the relevant chunk it needs at that moment — like a human recalling a specific memory, not replaying their entire life.

---

## Table of contents

1. [Mental model](#1-mental-model)
2. [Layer 1 — Identity & credential model](#2-layer-1--identity--credential-model)
3. [Layer 2 — Agent ↔ memory interaction](#3-layer-2--agent--memory-interaction)
4. [Layer 3 — SUI Move object model & storage](#4-layer-3--sui-move-object-model--storage)
5. [Key design decisions](#5-key-design-decisions)
6. [Memory namespace taxonomy](#6-memory-namespace-taxonomy)
7. [Move module structure](#7-move-module-structure)
8. [Off-chain indexer design](#8-off-chain-indexer-design)
9. [Agent SDK interface](#9-agent-sdk-interface)
10. [Security threat model](#10-security-threat-model)
11. [Build order](#11-build-order)
12. [User dashboard](#12-user-dashboard)
13. [Memory marketplace](#13-memory-marketplace)

---

## 1. Mental model

If you ask a man what happened to his son yesterday that made him not come to school, he doesn't replay every memory from that day — his computer disk that got spilt, his boss yelling at him. He searches for the specific memory about his son and surfaces only that.

This is the design goal: AI agents operate with a very small context window, and memory is just another tool they call. The tool returns only what is relevant, right now, for the question at hand.

**What this is not:**
- Not passing the entire conversation history as a system prompt
- Not a RAG wrapper bolted onto a vector database
- Not a centralised memory API that requires trusting a single provider

**What this is:**
- A decentralised, user-owned memory store where ownership and access control live on-chain (SUI)
- A semantic retrieval layer that returns minimal, relevant chunks on demand
- A full audit trail of which agents read which memories and when
- A consent model where users explicitly grant agents scoped access

---

## 2. Layer 1 — Identity & credential model

### 2.1 Every actor is a DID

Every participant in the system — human users, operators/developers, and AI agents — gets a **Decentralised Identifier (DID)** anchored as a SUI Move object.

```
did:sui:<address>
```

The DID object holds:
- A public key (ed25519 or secp256k1)
- A capability flags field
- A pointer to the actor's verifiable credential objects
- A metadata URI (optional profile / service endpoint)

### 2.2 Three auth primitives

#### zkLogin — for human users

Users authenticate via OAuth (Google, Apple, Twitch, etc.). SUI's zkLogin derives a deterministic, unlinkable address from the JWT claim using a zero-knowledge proof. The user never manages a seed phrase. The address is recoverable as long as the OAuth provider relationship holds.

```
OAuth JWT → ZK proof → SUI address → DID registration
```

Use this for: end-user onboarding, consumer-facing apps, mobile clients.

#### Multisig wallets — for production agents

Production agent deployments use a `k-of-n` multisig where:
- The agent holds key `A` (generated at deploy time, stored in HSM/TEE)
- The operator holds key `B`
- Both must co-sign memory write transactions and capability escalations

This means a single compromised agent key cannot exfiltrate or corrupt memory without the operator's co-signature. It also means the operator has a hard kill switch.

```
agent_key_A + operator_key_B → valid tx
agent_key_A alone           → rejected
```

#### Session keys — per-conversation ephemeral keys

Each conversation or task session gets a fresh ephemeral keypair with a short TTL (configurable, typically 15 minutes to 4 hours).

Flow:
1. Agent framework generates ephemeral keypair `(sk_session, pk_session)` at session start
2. Operator multisig issues a SUI transaction authorising `pk_session` for a specific scope and TTL
3. Agent uses `sk_session` to sign all memory queries during the session
4. Key expires — leaked session key has a hard ceiling on blast radius

Session keys are the primary signing mechanism for memory read queries. Write operations still require the operator multisig or a pre-authorised write cap.

### 2.3 Verifiable Credentials (VCs)

Operators issue VCs to agent DIDs specifying what the agent is permitted to do. These are stored as SUI objects owned by the agent's address.

A VC contains:
- `issuer`: operator DID
- `subject`: agent DID
- `namespaces`: list of memory namespace prefixes the agent may access
- `permissions`: `[read, write, delete]` per namespace
- `expiry`: unix timestamp
- `revoked`: bool flag

The memory gateway checks the `AgentCap` object on every query. Revocation is immediate — flip the flag on-chain, and the next query fails. VCs remain the operator-issued policy source that can be used to mint or refresh an `AgentCap`, but they are not the runtime object the gateway authorises against.

### 2.4 Delegation objects

Users grant agents explicit, scoped access to their memory namespace via a `DelegationObject` on SUI.

```
User (owner) → creates DelegationObject → grants AgentDID access to namespace prefix
```

A delegation contains:
- `owner_did`: the user granting access
- `agent_did`: the agent being granted access
- `namespace_prefix`: e.g. `did:sui:abc/work/project-x`
- `permissions`: read-only or read-write
- `expiry`: timestamp
- `revoked`: bool

This is the **consent layer**. No agent can read a user's memory without a valid, non-expired, non-revoked delegation from that user.

---

## 3. Layer 2 — Agent ↔ memory interaction

### 3.1 Memory as a tool call

Memory is exposed to agents as a standard tool — identically to how a web search or code interpreter is exposed. The agent decides when it needs memory; it calls the tool; it gets back the relevant chunk(s).

```typescript
// Tool definition passed to the agent
{
  name: "memory_query",
  description: "Retrieve relevant memories for the current context. Call this when you need information from past interactions or stored knowledge that is not present in your current context.",
  parameters: {
    intent: {
      type: "string",
      description: "Natural language description of what you are looking for."
    },
    scope: {
      type: "string",
      description: "Namespace prefix to search within, e.g. 'work/project-x' or 'personal/health'."
    },
    max_chunks: {
      type: "number",
      description: "Maximum number of memory chunks to retrieve. Default 3.",
      default: 3
    }
  }
}
```

The agent's system prompt instructs it that when it identifies a gap in its context — something it knows it should know but does not — it calls `memory_query` before answering.

### 3.2 Query execution flow

```
1. Agent calls memory_query(intent, scope, max_chunks)
   │
2. Memory gateway receives call
   │
3. Auth & scope check
   ├── Verify session key is authorised (check on-chain session auth tx)
   ├── Load agent's AgentCap object from SUI
   ├── Confirm scope is within agent's permitted namespaces
   └── If any check fails → return error { code, reason }
   │
4. Semantic retrieval
   ├── Embed intent string using the same model used at write time
   ├── Run ANN search over the encrypted vector index for this namespace
   └── Retrieve top-k candidate chunk IDs
   │
5. Rank & filter
   ├── Score by cosine similarity
   ├── Apply recency decay (recent memories score higher by default)
   ├── Filter out chunks the agent's cap does not permit
   └── Select top max_chunks
   │
6. Sign access-log transaction
   ├── Construct AccessLog intent payload
   ├── Sign with session key
   └── Submit to SUI only after chunk decryption succeeds; if Seal key release fails, do not emit a success log and return an error instead
   │
7. Decrypt & return chunks
   ├── Request key release from SUI Seal (threshold decryption)
   ├── Decrypt chunk content
   └── Return structured chunks to agent
   │
8. Agent injects chunks into context window
   └── Responds using only the relevant retrieved memory
```

### 3.3 Write flow

An agent (or the conversation runtime) can write new memories. Write operations go through the memory writer service.

```
1. Agent calls memory_write(content, namespace, tags, ttl?)
   │
2. Memory gateway receives call
   ├── Verify session key has write permission for namespace
   └── Verify operator multisig pre-authorisation (or require co-sign)
   │
3. Gateway posts write-intent event on SUI
   │
4. Memory writer service (off-chain indexer) picks up the event
   ├── Chunks the content (fixed-size or semantic chunking)
   ├── Embeds each chunk
   ├── Encrypts using SUI Seal (access policy = valid AgentCap for namespace)
   ├── Pins encrypted blob to DA layer (IPFS / Walrus)
   └── Gets back CID
   │
5. Writer posts MemoryChunkRef on-chain
   └── { content_hash, cid, namespace, tags, access_policy }
   │
6. Vector index updated
   └── { chunk_id, embedding, namespace, metadata }
```

### 3.4 Delete flow

An agent or user can explicitly delete a memory when they have delete permission for the namespace.

```
1. Agent or user calls memory_delete(chunk_id)
   │
2. Memory gateway receives call
   ├── Verify delete permission on the relevant AgentCap or delegation
   └── Verify the chunk belongs to an authorised namespace
   │
3. Gateway posts DeleteChunkRef event on SUI
   │
4. Indexer processes DeleteChunkRef
   ├── Remove the chunk from the vector index and search cache
   ├── Mark the on-chain chunk reference as tombstoned or deleted, as the contract model allows
   └── Drop DA-layer pinning when retention policy no longer requires the blob
   │
5. Audit trail updated
   └── Emit a delete access log so the registry history shows who removed the memory and when
```

---

## 4. Layer 3 — SUI Move object model & storage

### 4.1 On-chain objects

#### `MemoryRegistry`

One per user (or namespace owner). The root object.

```move
public struct MemoryRegistry has key, store {
    id: UID,
    owner: address,
    agent_caps: Table<address, AgentCap>,   // agent_address → cap
    delegations: Table<address, Delegation>, // agent_address → delegation
    chunk_refs: Table<vector<u8>, MemoryChunkRef>, // content_hash → ref
    created_at: u64,
    version: u64,
}
```

#### `AgentCap`

A capability object scoped to a specific agent DID.

```move
public struct AgentCap has key, store {
    id: UID,
    registry_id: ID,
    agent_did: vector<u8>,
    agent_address: address,
    namespaces: vector<vector<u8>>,   // permitted namespace prefixes
    permissions: u8,                  // bitmask: READ=1, WRITE=2, DELETE=4
    session_key: Option<address>,     // current authorised session key
    session_expiry: Option<u64>,
    expiry: u64,
    revoked: bool,
}
```

#### `MemoryChunkRef`

Lightweight on-chain pointer to off-chain encrypted content.

```move
public struct MemoryChunkRef has store, drop {
    content_hash: vector<u8>,   // SHA-256 of plaintext — integrity proof
    cid: vector<u8>,            // IPFS CID or Walrus blob ID
    namespace: vector<u8>,
    tags: vector<vector<u8>>,
    access_policy: vector<u8>,  // Seal policy ID
    created_at: u64,
    created_by: address,        // agent address that wrote this chunk
    ttl: Option<u64>,           // optional expiry for ephemeral memories
}
```

#### `AccessLog` (event, not stored object)

Emitted on every read and write. Events are cheaper than stored objects on SUI.

```move
public struct AccessLog has copy, drop {
    registry_id: ID,
    agent_did: vector<u8>,
    chunk_ids: vector<vector<u8>>,
    operation: u8,              // READ=0, WRITE=1
    timestamp: u64,
    session_key: address,
}
```

### 4.2 Off-chain storage

| Layer | What lives here | Technology |
|---|---|---|
| Content store | Encrypted memory blobs | IPFS or SUI Walrus |
| Encryption | Threshold encryption, policy-gated key release | SUI Seal |
| Vector index | Embeddings + metadata, keyed by chunk ID | Qdrant / Weaviate (self-hosted) |
| Writer service | Orchestrates chunk → encrypt → pin → index → post ref | Node.js / Rust off-chain indexer |

**Why content is off-chain:** SUI storage costs scale with object size. Memory content can grow to gigabytes. The chain is the **trust layer** (integrity proofs, access control, audit log) — not the storage layer. The `content_hash` field in `MemoryChunkRef` is the integrity guarantee: anyone can verify the decrypted content matches the hash posted on-chain.

### 4.3 Encryption model — SUI Seal

SUI's Seal module provides **threshold encryption** where a decryption key is only released when an on-chain condition is satisfied at the moment of the request.

The access policy for each chunk is defined as: *"release the decryption key only if the requesting address holds a valid, non-revoked `AgentCap` for this chunk's namespace at time of request."*

This means:
- The encryption policy is enforced by the chain, not by trusting the off-chain storage server
- Revoking an `AgentCap` immediately prevents decryption of all chunks in that namespace, even if the encrypted blobs are still publicly pinned
- The storage server is completely untrusted — it holds ciphertext it cannot decrypt

---

## 5. Key design decisions

### Why session keys per conversation?

Agent frameworks (LangGraph, CrewAI, AutoGen) often spawn many concurrent agent instances. A shared long-lived key is catastrophic if leaked. Session keys give each conversation a bounded, auditable identity. The blast radius of a leak is bounded by the TTL and the narrow scope the session key was authorised for.

### Why multisig for production agents?

The operator needs a hard kill switch. If an agent starts behaving unexpectedly and begins writing corrupted memories or attempting out-of-scope reads, the operator can:
1. Refuse to co-sign future write transactions
2. Revoke the `AgentCap` on-chain
3. Rotate the operator key

No single key compromise leads to a full memory breach.

### Why emit `AccessLog` as events rather than storing objects?

Stored SUI objects cost ongoing storage rent. Events are emitted once and are queryable via the SUI event API without rent. Access logs are append-only audit data — they are never updated after creation — which makes events the correct primitive.

### Why not store embeddings on-chain?

Embedding vectors are 1536 floats (for `text-embedding-3-small`) = ~6KB per chunk. At scale, this is prohibitive on-chain. The vector index is off-chain, and the on-chain `MemoryChunkRef` is the source of truth for which chunks exist and who may access them. The indexer must stay consistent with on-chain state — it is always re-derivable from chain history if corrupted.

### Why Walrus over IPFS?

SUI-native Walrus provides erasure-coded blob storage with SUI-native payment and retrieval guarantees. IPFS pinning requires a separate pinning service with its own trust assumptions. For a fully SUI-native product, Walrus is the natural choice. IPFS remains a fallback for interoperability.

---

## 6. Memory namespace taxonomy

Define a hierarchical namespace for all memories:

```
{owner_did}/{domain}/{subdomain}/{...}
```

Examples:

```
did:sui:0xabc.../personal/health
did:sui:0xabc.../personal/relationships/family
did:sui:0xabc.../work/project-alpha/decisions
did:sui:0xabc.../work/project-alpha/codebase
did:sui:0xabc.../preferences/communication-style
did:sui:0xabc.../agent-logs/assistant/2025
```

`AgentCap` permissions are granted at a **prefix level**. An agent with access to `work/project-alpha` can read all memories under that prefix. An agent with access to only `work/project-alpha/decisions` cannot read `work/project-alpha/codebase`.

This is the mechanism that makes selective retrieval possible at the access-control layer — not just at the semantic search layer.

---

## 7. Move module structure

```
sources/
├── memory_registry.move     # MemoryRegistry CRUD, owner-only mutations
├── agent_cap.move           # AgentCap issuance, revocation, session key auth
├── delegation.move          # Delegation objects, grant/revoke flows
├── chunk_ref.move           # MemoryChunkRef posting, TTL enforcement
├── access_log.move          # AccessLog event emission
├── session_auth.move        # Session key authorisation transactions
└── namespace.move           # Namespace prefix matching utilities

tests/
├── memory_registry_tests.move
├── agent_cap_tests.move
├── delegation_tests.move
└── integration_tests.move
```

Key invariants to enforce in Move:
- Only the `MemoryRegistry` owner can add or revoke `AgentCap` objects
- An `AgentCap` can only reference namespaces that exist under the registry owner's DID prefix
- Session key authorisation must include an expiry; no infinite session keys
- `AccessLog` events must be emitted on every read, enforced by the gateway entry point function — not left to the caller

---

## 8. Off-chain indexer design

The memory writer service is an off-chain process that watches SUI for write-intent events and maintains the vector index.

```
┌─────────────────────────────────────────────────┐
│ Memory writer service                           │
│                                                 │
│  SUI event listener                             │
│    └── watches for WriteIntent events           │
│                                                 │
│  Pipeline per event:                            │
│    1. Validate write-intent tx signature        │
│    2. Fetch raw content from agent              │
│    3. Semantic chunk (LangChain text splitter)  │
│    4. Embed each chunk (OpenAI / local model)   │
│    5. Encrypt each chunk via SUI Seal           │
│    6. Pin to Walrus / IPFS, get CID             │
│    7. Compute SHA-256 content hash              │
│    8. Post MemoryChunkRef on SUI                │
│    9. Upsert embedding + metadata to Qdrant     │
└─────────────────────────────────────────────────┘
```

The indexer is **re-derivable from chain history**. If the vector index is corrupted or lost, all `MemoryChunkRef` objects on-chain can be replayed to recover chunk metadata and rebuild the index. For rebuilds that need plaintext, the indexer uses a dedicated Operator indexer key with read-only Seal rebuild permissions to re-decrypt chunks for re-embedding; normal user-scoped `AgentCap` objects are not used for this maintenance path. The chain is the canonical source of which chunks exist; the index is a derived, queryable view.

### Indexer consistency guarantee

After a `MemoryChunkRef` is confirmed on-chain, the chunk must be queryable via the vector index within a bounded time window (target: < 5 seconds). The indexer must process events in order and maintain a cursor (last processed SUI checkpoint). On restart, it replays from the cursor.

---

## 9. Agent SDK interface

Expose memory as a clean SDK that agent frameworks consume. The SDK abstracts all SUI interaction, key management, and retrieval.

```typescript
import { AgentMemory } from '@your-project/agent-memory-sdk';

// Initialise with agent credentials
const memory = new AgentMemory({
  agentDid: 'did:sui:0xagent...',
  sessionKey: ephemeralKeypair,         // generated per conversation
  gatewayUrl: 'https://memory.yourproject.xyz',
  suiRpcUrl: 'https://fullnode.mainnet.sui.io',
});

// Query memory — this is the tool the agent calls
const chunks = await memory.query({
  intent: "What happened with the user's son that made him miss school?",
  scope: 'personal/family',
  maxChunks: 3,
});
// Returns: [{ content: string, score: number, chunkId: string, createdAt: number }]

// Write a memory after a conversation
await memory.write({
  content: "User mentioned their son missed school on 2025-05-20 because their daughter won a medal at the regional science fair and the whole family attended the ceremony.",
  namespace: 'personal/family',
  tags: ['son', 'school', 'daughter', 'science-fair'],
});

// Revoke access (operator-side)
await memory.revokeAgentCap({ agentAddress: '0xagent...' });
```

### Tool registration for common frameworks

```typescript
// LangChain
import { DynamicStructuredTool } from 'langchain/tools';
import { z } from 'zod';

const memoryTool = new DynamicStructuredTool({
  name: 'memory_query',
  description: 'Retrieve relevant memories. Call this when you are missing context about the user or past interactions.',
  schema: z.object({
    intent: z.string().describe('What you are looking for, in natural language.'),
    scope: z.string().optional().describe('Namespace to search within.'),
    maxChunks: z.number().optional().default(3),
  }),
  func: async ({ intent, scope, maxChunks }) => {
    const chunks = await memory.query({ intent, scope, maxChunks });
    return JSON.stringify(chunks);
  },
});
```

---

## 10. Security threat model

| Threat | Mitigation |
|---|---|
| Compromised agent session key | Session keys are scoped and short-lived (TTL). Blast radius bounded by namespace and expiry. |
| Compromised operator key | Multisig requires agent key too. Rotate operator key; old agent cap revoked. |
| Malicious off-chain indexer | Content hash on-chain; clients verify hash matches decrypted content. Indexer cannot forge chunk content. |
| Unauthorised memory read | SUI Seal only releases decryption key if `AgentCap` is valid at time of request. Revoking cap immediately stops decryption. |
| Replay of old session key | Session keys carry an on-chain expiry. SUI validators reject transactions signed by expired session keys. |
| Namespace traversal | `AgentCap.namespaces` stores prefix list; gateway enforces prefix matching server-side before vector search. |
| DA layer content deletion | Content hash on-chain provides proof of existence. Pinning incentives (Walrus epochs) maintain availability. |
| Agent writing poisoned memories | Write transactions are logged on-chain with `created_by` field. Users can audit and flag. Operator multisig gates writes. |

---

## 11. Build order

Build in this sequence to validate each layer before depending on it:

1. **SUI Move contracts** — `MemoryRegistry`, `AgentCap`, `MemoryChunkRef`, `AccessLog` event. Deploy to devnet. Write tests.

2. **Identity & auth service** — zkLogin integration, session key issuance flow, multisig wallet setup for agent accounts.

3. **Memory gateway** — The off-chain API that agents call. Auth check → vector search → Seal key request → decrypt → return. No writes yet.

4. **Memory writer service** — Event listener, chunk pipeline, Qdrant upsert, `MemoryChunkRef` posting.

5. **Agent SDK** — Wrap gateway + writer behind the clean SDK interface. Tool adapters for LangChain, LlamaIndex, AutoGen.

6. **Delegation UI** — User-facing interface for granting and revoking agent access to memory namespaces.

7. **Audit dashboard** — Query `AccessLog` events by user address and visualise which agents accessed which memories and when. (See [Section 12](#12-user-dashboard))

8. **Memory marketplace** — `MemoryListing` Move contracts, escrow, access-rights purchase flow. (See [Section 13](#13-memory-marketplace))

---

## 12. User dashboard

The dashboard is a **read layer** over data that already exists: SUI events, on-chain objects, and the off-chain vector index. No new trust assumptions are introduced — everything shown to the user is derived from chain-verifiable sources.

### 12.1 Dashboard sections

#### Memory browser

Displays all `MemoryChunkRef` objects owned by the user's `MemoryRegistry`, grouped by namespace.

- Tree view of namespace hierarchy (e.g. `personal/family`, `work/project-alpha`)
- Per-chunk: preview of decrypted content snippet, tags, creation date, author (which agent wrote it), TTL countdown if set
- Search bar that runs a live `memory_query` against the user's own index
- Delete / archive controls (posts a `DeleteChunkRef` tx on-chain, removes from index)
- Bulk export as JSON or plain text

**Data sources:**
- On-chain: `MemoryChunkRef` objects from `MemoryRegistry` (SUI RPC `getOwnedObjects`)
- Off-chain: vector index for search, DA layer for content preview (decrypt client-side using user's key)

#### Access control panel

Shows every `AgentCap` and `Delegation` currently active under the user's registry.

- List of agents with access: agent DID, granted namespaces, permission level, expiry
- Revoke button per agent (posts `revoke_agent_cap` tx)
- Grant new delegation wizard (select agent DID → select namespace prefix → set expiry → sign tx)
- Pending delegation requests (agents that have requested access but not yet been approved)

**Data sources:** On-chain `AgentCap` and `Delegation` objects via SUI RPC.

#### Activity feed

A chronological stream of everything that has happened on the user's memory registry.

- Memory written (by which agent, to which namespace, timestamp)
- Memory read (by which agent, which chunk IDs, timestamp)
- Agent access granted / revoked
- Session key authorisations
- Marketplace listings created / sold

Each entry links to the SUI transaction explorer for the underlying tx digest.

**Data source:** `AccessLog` events queried via SUI event API, filtered by `registry_id`.

```typescript
// Fetch activity feed
const events = await suiClient.queryEvents({
  query: {
    MoveEventField: {
      path: '/registry_id',
      value: userRegistryId,
    },
  },
  order: 'descending',
  limit: 50,
});
```

#### Recent queries panel

Shows the last N `memory_query` calls made by any agent against the user's memory, with:

- Agent DID that queried
- Intent string passed (natural language)
- Namespace scope queried
- Chunks returned (IDs)
- Timestamp
- Whether the query was authorised or rejected

**Data source:** `AccessLog` events with `operation = READ`.

#### Analytics

Aggregated views over the event history:

- Query volume over time (chart — queries per day / week)
- Most accessed namespaces (bar chart)
- Most active agents (ranked by query count)
- Memory growth over time (total chunks, total estimated size)
- Rejected access attempts (agents that tried to query without a valid cap)

#### Notifications

Real-time alerts for:
- A new agent was granted access to your memory
- An agent accessed a sensitive namespace (user-configured sensitivity flags per namespace)
- A memory chunk is approaching its TTL expiry
- A marketplace listing received a purchase offer

Implemented via SUI WebSocket subscription to `AccessLog` events.

```typescript
suiClient.subscribeEvent({
  filter: { MoveEventField: { path: '/registry_id', value: userRegistryId } },
  onMessage: (event) => notificationHandler(event),
});
```

### 12.2 Dashboard architecture

```
┌──────────────────────────────────────────────────┐
│ Dashboard frontend (Next.js / React)             │
│                                                  │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  │
│  │  Memory    │  │  Access    │  │ Activity / │  │
│  │  browser   │  │  control   │  │ Analytics  │  │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  │
│        │               │               │          │
│        └───────────────┴───────────────┘          │
│                        │                          │
│              Dashboard API layer                  │
│         (aggregates + caches chain data)          │
└────────────────────────┬─────────────────────────┘
                         │
          ┌──────────────┼──────────────┐
          │              │              │
     SUI RPC        SUI Events     Off-chain
  (objects,         (AccessLog,    indexer API
   balances)         writes)       (search, chunks)
```

The **dashboard API layer** is a lightweight backend that:
- Caches and indexes `AccessLog` events into a queryable store (Postgres or similar)
- Aggregates analytics
- Handles WebSocket fan-out to connected dashboard clients
- Decrypts content previews server-side only if the user has authenticated and provided their key, or handles client-side decryption via the browser wallet

**Authentication for the dashboard:** zkLogin. The user signs in with their OAuth provider, which derives their SUI address, which is the owner of their `MemoryRegistry`. No separate account system needed.

---

## 13. Memory marketplace

The marketplace lets users **sell access rights to memory namespaces** — not the raw data. The buyer receives a scoped `AgentCap` object upon purchase. The seller retains full ownership of their `MemoryRegistry` and can revoke the sold cap at any time (with reputational and possibly escrow consequences).

This is the correct model: you are selling a **licence to query**, not transferring data.

### 13.1 What can be listed

- A **namespace** (e.g. `did:sui:abc/research/llm-papers`) — buyer's agents can query all memory in this namespace
- A **tag-filtered subset** — e.g. all chunks tagged `[python, tutorial]` across any namespace
- A **curated bundle** — the seller manually selects specific chunk IDs to include in the listing
- A **live subscription** — buyer gets ongoing access as new memories are added to the namespace (recurring payment model)

### 13.2 SUI Move objects for the marketplace

#### `MemoryListing`

```move
public struct MemoryListing has key, store {
    id: UID,
    seller: address,
    registry_id: ID,
    listing_type: u8,           // NAMESPACE=0, TAG_FILTER=1, BUNDLE=2, SUBSCRIPTION=3
    namespace_prefix: Option<vector<u8>>,
    tag_filter: Option<vector<vector<u8>>>,
    chunk_ids: Option<vector<vector<u8>>>,
    price: u64,                 // in MIST (SUI base unit)
    subscription_period: Option<u64>, // seconds, for subscription type
    access_duration: u64,       // how long the purchased AgentCap is valid
    permissions: u8,            // READ only for marketplace sales
    title: vector<u8>,
    description: vector<u8>,
    preview_chunk_ids: vector<vector<u8>>, // free preview chunks
    total_sales: u64,
    rating_sum: u64,
    rating_count: u64,
    active: bool,
    created_at: u64,
}
```

#### `PurchaseReceipt`

```move
public struct PurchaseReceipt has key, store {
    id: UID,
    listing_id: ID,
    buyer: address,
    seller: address,
    agent_cap_id: ID,       // the AgentCap minted on purchase
    price_paid: u64,
    purchased_at: u64,
    expires_at: u64,
}
```

#### `MarketplaceEscrow`

Holds payment during the access window. Releases to seller in tranches (or fully upfront, configurable).

```move
public struct MarketplaceEscrow has key {
    id: UID,
    listing_id: ID,
    buyer: address,
    seller: address,
    amount: Balance<SUI>,
    release_schedule: u8,   // UPFRONT=0, LINEAR=1, ON_EXPIRY=2
    released: u64,
    created_at: u64,
}
```

### 13.3 Purchase flow

```
1. Seller creates MemoryListing on-chain
   └── Sets price, access_duration, namespace_prefix, title, description

2. Buyer browses marketplace (off-chain index of active listings)
   ├── Views listing metadata
   ├── Reads free preview chunks (decrypted client-side using Seal)
   └── Decides to purchase

3. Buyer submits purchase transaction
   ├── Pays price into MarketplaceEscrow object
   ├── Marketplace contract mints a new AgentCap scoped to listing's namespace
   │   └── AgentCap.expiry = now + access_duration
   │   └── AgentCap.permissions = READ only
   └── PurchaseReceipt emitted as event, stored as object in buyer's address

4. Payment release (configurable per listing)
   ├── UPFRONT: seller receives payment immediately on purchase
   ├── LINEAR: payment streams to seller over access_duration
   └── ON_EXPIRY: seller receives payment when AgentCap expires (buyer protection)

5. Buyer's agent uses purchased AgentCap to query seller's memory namespace
   └── Same query flow as standard memory_query — gateway checks AgentCap as normal

6. Access expires
   ├── AgentCap.expiry passes → gateway rejects future queries
   └── Buyer can renew (new purchase tx) or let it lapse
```

### 13.4 Seller controls

- **Revoke at will:** Seller can revoke any sold `AgentCap` at any time. If the escrow is `ON_EXPIRY` or `LINEAR`, revocation triggers a partial refund calculation. If `UPFRONT`, no refund — buyers should choose listing types accordingly.
- **Delist:** Seller sets `listing.active = false`. No new purchases. Existing purchased caps remain valid until expiry.
- **Namespace privacy:** The seller's raw memory content is never exposed on-chain. The buyer queries through the same Seal-encrypted retrieval path. The marketplace never has access to plaintext.
- **Preview chunks:** Seller designates specific chunk IDs as free previews. These are decryptable by anyone who loads the listing, without purchase.

### 13.5 Marketplace discovery (off-chain index)

The marketplace frontend is backed by an off-chain indexer that watches for `MemoryListing` creation events and builds a searchable catalogue.

Each listing in the catalogue includes:
- Title, description, seller DID
- Listing type, namespace tags
- Price, access duration
- Aggregate rating (from `PurchaseReceipt` + buyer rating tx)
- Total sales count
- Preview chunk previews (fetched and decrypted from DA layer)

Search is semantic — the indexer embeds listing descriptions and preview chunk content so buyers can search by intent ("I want memories about Rust programming from senior engineers") rather than just by keyword.

### 13.6 Ratings and reputation

After a purchased `AgentCap` expires, the buyer can submit a rating transaction:

```move
public struct Rating has key, store {
    id: UID,
    listing_id: ID,
    buyer: address,
    receipt_id: ID,     // must hold a valid expired PurchaseReceipt to rate
    score: u8,          // 1–5
    comment_hash: vector<u8>, // hash of off-chain comment stored on IPFS
    created_at: u64,
}
```

Ratings are aggregated into `listing.rating_sum / listing.rating_count`. Buyers can only rate once per purchase receipt — no spam ratings.

### 13.7 Revenue share

The marketplace contract takes a configurable protocol fee (e.g. 2.5%) on each purchase, held in a treasury object. Fee percentage is a governance parameter.

```
Purchase price: 100 SUI
Protocol fee (2.5%): 2.5 SUI → treasury
Seller receives: 97.5 SUI (per release schedule)
```

### 13.8 Marketplace Move module additions

```
sources/
├── marketplace/
│   ├── memory_listing.move      # Listing CRUD, active/delist controls
│   ├── purchase.move            # Purchase tx, AgentCap minting, escrow creation
│   ├── escrow.move              # Payment release schedules, refund logic
│   ├── rating.move              # Post-expiry buyer ratings
│   └── treasury.move            # Protocol fee collection, governance
```

### 13.9 Updated build order additions

Add these steps after the core system is live:

9. **Marketplace Move contracts** — `MemoryListing`, `MarketplaceEscrow`, `PurchaseReceipt`, `Rating`, `treasury`. Deploy to testnet.

10. **Marketplace indexer** — Watch for listing events, build semantic search catalogue, embed preview chunks.

11. **Marketplace frontend** — Browse, search, preview, purchase, rate. Integrates with existing dashboard (listed namespaces appear in the access control panel).

12. **Subscription billing** — Recurring payment logic using SUI programmable transaction blocks for auto-renewal.

---

*This document is the authoritative system design for the decentralised AI memory project. All implementation decisions should be traced back to the principles here. When in doubt: the chain is the trust layer, memory is a tool not a prompt, and the user always controls access.*