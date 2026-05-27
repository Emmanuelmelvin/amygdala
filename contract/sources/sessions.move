module amygdala::sessions;

use std::string::String;
use sui::event;
use sui::object::{Self, ID};
use amygdala::verifiable_credential::VerifiableCredential;

const EInvalidSessionKeyLength: u64 = 0;

public struct SessionCreatedEvent has copy, drop {
    credential_id: ID,
    session_key: String,
}

public fun create_session(
    credential: &VerifiableCredential,
    session_key: String,
) {
    let key_len = std::string::length(&session_key);
    assert!(key_len >= 10 && key_len <= 14, EInvalidSessionKeyLength);

    event::emit(SessionCreatedEvent {
        credential_id: object::id(credential),
        session_key,
    });
}
