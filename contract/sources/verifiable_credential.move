module amygdala::verifiable_credential;

use std::string::String;
use std::option::Option;
use amygdala::memory_register::{Self, Namespace, MemoryRegisterCap};
const ENotAuthorized: u64 = 0;

public struct VerifiableCredential has key, store {
    id: UID,
    registry_id: ID,
    agent_did: String,
    agent_address: address,
    namespaces: vector<Namespace>,
    ttl: Option<u64>,
    revoked: bool,
}

public struct VerifiableCredentialCap has key, store {
    id: UID,
    credential_id: ID,
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

    let  credential_cap = VerifiableCredentialCap {
        id: object::new(ctx),   
        credential_id: object::uid_to_inner(&credential.id),
    };
    transfer::public_transfer(credential_cap, agent_address);
    transfer::public_share_object(credential);
}

public fun revoke_credential(
    cap: &MemoryRegisterCap,
    credential: &mut VerifiableCredential,
    ctx: &mut TxContext
) {
    assert!(credential.registry_id == memory_register::register_id(cap), ENotAuthorized);
    credential.revoked = true;
}
