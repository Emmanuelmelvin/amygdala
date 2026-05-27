import re

with open('/workspaces/amygdala/.agents/skills/amydgala/SKILL.md', 'r') as f:
    text = f.read()

text = text.replace('MemoryRegistry', 'MemoryRegister')
text = text.replace('AgentCap', 'VerifiableCredential')
text = text.replace('revoke_agent_cap', 'revoke_credential')

# Register
old_reg = "public struct MemoryRegister has key, store {"
new_reg = """public struct MemoryRegister has key, store {
    id: UID,
    register_id: String,
    name: String,
    description: String,
    created_by: address,
    namespaces: vector<Namespace>,
    revoked_verifiable_credentials: vector<ID>,
    created_on: u64,
    image_url: Url,
}

public struct MemoryRegisterCap has key, store {
    id: UID,
    register_id: ID,
}

public enum Permission has copy, drop, store {
    Read,
    Write,
    Delete
}

public struct Namespace has store, copy, drop {
    prefix: String,
    permissions: vector<Permission>,
}"""
text = re.sub(r'public struct MemoryRegister has key, store \{[\s\S]*?version: u64,\n\}', new_reg, text)


old_vc = "public struct VerifiableCredential has key, store {"
new_vc = """public struct VerifiableCredential has key, store {
    id: UID,
    registry_id: ID,
    agent_did: String,
    agent_address: address,
    namespaces: vector<Namespace>,
    ttl: Option<u64>,
    revoked: bool,
}

public struct SessionCreatedEvent has copy, drop {
    credential_id: ID,
    session_key: String,
}"""
text = re.sub(r'public struct VerifiableCredential has key, store \{[\s\S]*?revoked: bool,\n\}', new_vc, text)

# Marketplace
new_market = """public struct MemoryRegisterMarketObject has key, store {
    id: UID,
    amount_in_usdc: u64,
    seller: address,
    register: MemoryRegister,
}"""
text = re.sub(r'public struct MemoryListing has key, store \{[\s\S]*?created_at: u64,\n\}', new_market, text)
text = text.replace('MemoryListing', 'MemoryRegisterMarketObject')

with open('/workspaces/amygdala/.agents/skills/amydgala/SKILL.md', 'w') as f:
    f.write(text)

