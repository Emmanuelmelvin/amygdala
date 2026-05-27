module amygdala::verifiable_credential;

use std::string::String;
use std::option::Option;
use amygdala::memory_register::{Self, Namespace, MemoryRegisterCap};

public struct VerifiableCredential has key, store {
    id: UID,
    registry_id: ID,
    agent_did: String,
    agent_address: address,
    namespaces: vector<Namespace>,
    ttl: Option<u64>,
    revoked: bool,
}

public fun create_credential(
    cap: &MemoryRegisterCap,
    agent_did: String,
    agent_address: address,
    namespaces: vector<Namespace>,
    ttl: Option<u64>,
    ctx: &mut TxContext
) {
    let credential = VerifiableCredential {
        id: object::new(ctx),
        registry_id: memory_register::register_id(cap),
        agent_did,
        agent_address,
        namespaces,
        ttl,
        revoked: false,
    };

    transfer::public_transfer(credential, agent_address);
}
